# Module 08 — Helm et Kustomize

⏱ 3 h · 🟡 Intermédiaire

## Objectifs
- Installer des applications tierces avec **Helm** (repos, values, upgrade, rollback)
- Écrire un **chart** (templates, values, helpers)
- Gérer plusieurs environnements avec **Kustomize** (base / overlays)
- Choisir entre Helm et Kustomize

## 1. Cours

### 1.1 Le problème
Copier-coller du YAML par environnement ne passe pas à l'échelle : on veut **paramétrer** et **versionner**.

| | Helm | Kustomize |
|---|---|---|
| Principe | Moteur de templates Go + gestion de *releases* | Patchs déclaratifs sans template |
| Distribution | Charts (repos/OCI) | Dossiers Git |
| Cycle de vie | `install/upgrade/rollback/uninstall` (stocké en Secrets) | `kubectl apply -k` |
| Idéal pour | Packager/distribuer, apps tierces | Variantes d'env. de **vos** manifests |
| Combinaison | `helm template` puis Kustomize, ou Argo CD/Flux avec les deux | |

### 1.2 Helm — vocabulaire
**Chart** (paquet) · **Release** (instance installée) · **Repository** · **Values** (`values.yaml`, `-f`, `--set`). Structure :
```
chart/ Chart.yaml  values.yaml  templates/ (*.yaml, _helpers.tpl, NOTES.txt)  charts/ (dépendances)
```
Templates : `{{ .Values.x }}`, `{{ .Release.Name }}`, `{{ include "…" . | nindent 4 }}`, `{{- if }}`, `{{- range }}`, `{{ toYaml … }}`, `default`, `quote`.
Commandes : `helm repo add|update`, `helm search repo`, `helm show values`, `helm install|upgrade --install`, `helm template`, `helm lint`, `helm diff` (plugin), `helm history|rollback|uninstall`.

### 1.3 Kustomize
`base/` (ressources communes) + `overlays/<env>/` (namespace, préfixes, images, replicas, patchs strategic-merge/JSON6902, `configMapGenerator` avec hash → rollout automatique quand la config change).

### 1.4 Helm en profondeur

**Cycle de vie d'une release.** `helm install` rend les templates avec les *values*, envoie les manifestes à l'API et enregistre la release (un Secret `sh.helm.release.v1.<nom>.vN` par révision dans le namespace). `helm upgrade` crée une révision `N+1` ; `helm rollback <release> <rev>` redéploie une révision précédente (en créant une nouvelle révision). `helm uninstall` supprime les objets de la release.

**Hiérarchie des values** (la dernière gagne) : `values.yaml` du chart → `-f fichier1.yaml -f fichier2.yaml` (dans l'ordre) → `--set clé=valeur`. Pour réutiliser les valeurs d'une release précédente : `--reuse-values` (à manier avec prudence, car les nouveaux défauts du chart ne sont plus pris en compte) ; en pratique, versionnez un fichier de values complet par environnement.

**Syntaxe des templates (Go templates + Sprig)**
```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "app.fullname" . }}
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}   # redémarre si la config change
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          {{- with .Values.resources }}
          resources: {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- if .Values.env }}
          env:
            {{- range $k, $v := .Values.env }}
            - {name: {{ $k }}, value: {{ $v | quote }}}
            {{- end }}
          {{- end }}
```
Points de vigilance : `nindent` (indentation correcte), `{{-` / `-}}` (suppression des blancs), `quote` (forcer une chaîne), `required "message" .Values.x` (échouer si absent), `default`, `lookup` (lire le cluster, absent en `helm template`), `tpl` (rendre une chaîne comme template). Le fichier `_helpers.tpl` contient les `define` réutilisables (noms, labels).

**Dépendances et sous-charts** : déclarées dans `Chart.yaml` (`dependencies:`), téléchargées par `helm dependency update` (répertoire `charts/`, fichier `Chart.lock`). Les values d'un sous-chart se placent sous sa clé (`postgresql: { auth: {...} }`). `condition: postgresql.enabled` active/désactive la dépendance. Les **valeurs globales** (`global:`) sont partagées.

**Hooks** : annotations `helm.sh/hook: pre-install,pre-upgrade` (Jobs de migration), `post-install`, `test`… Utiles mais source de pièges (ressources hors release, ordre, suppression) ; préférez des Jobs gérés par le déploiement quand c'est possible.

**CRDs** : le répertoire `crds/` du chart n'est installé qu'à l'installation, **jamais mis à jour ni supprimé** par Helm. La gestion des CRDs (version, cycle de vie) se traite à part (chart dédié, GitOps).

**Qualité d'un chart** : `helm lint`, `helm template … | kubeconform`, `helm unittest`, `chart-testing (ct)` en CI, `values.schema.json` (validation JSON Schema des values : les erreurs sont détectées dès `helm install`).

**Distribution** : dépôts HTTP (`index.yaml`) ou **registre OCI** (`helm push chart.tgz oci://ghcr.io/acme/charts`), signatures `helm package --sign` / cosign. Épinglez toujours `--version` d'un chart tiers et relisez le rendu (`helm template`) avant de l'installer.

### 1.5 Kustomize en profondeur
```
app/
├── base/
│   ├── kustomization.yaml      # resources: [deployment.yaml, service.yaml]
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/kustomization.yaml  # resources: [../../base] ; namespace: dev ; replicas ; images
    └── prod/
        ├── kustomization.yaml
        └── patch-resources.yaml
```
```yaml
# overlays/prod/kustomization.yaml
resources: [../../base]
namespace: prod
namePrefix: prod-
labels: [{pairs: {env: prod}, includeSelectors: false}]
images: [{name: ghcr.io/acme/api, newTag: "1.4.2"}]
replicas: [{name: api, count: 4}]
patches:
  - path: patch-resources.yaml                      # strategic merge
  - target: {kind: Deployment, name: api}           # JSON 6902
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value: {name: LOG_LEVEL, value: warn}
configMapGenerator:
  - name: app-config
    files: [app.properties]                         # génère app-config-<hash> → rollout si changement
secretGenerator: [...]
components: [../../components/monitoring]           # briques réutilisables
```
- `kubectl kustomize overlays/prod` affiche le rendu ; `kubectl apply -k overlays/prod` l'applique ; `kubectl diff -k` montre l'écart.
- **Patch strategic-merge** : fusionne par clé (nom de conteneur) ; **JSON 6902** : opérations `add/replace/remove` à un chemin précis ; plus verbeux, plus précis.
- Kustomize **n'a pas de templates** : on part d'un YAML valide et on le transforme. Avantage : lisibilité et absence de langage à apprendre ; limite : peu d'abstraction (pas de boucles/conditions).
- `replacements` copient une valeur d'un champ vers d'autres (remplace les anciennes `vars`).
- `helmCharts:` dans un `kustomization.yaml` rend un chart Helm puis applique des patchs (`kustomize build --enable-helm`) : la combinaison des deux outils.

### 1.6 Choisir : Helm, Kustomize ou les deux ?
| Situation | Recommandation |
|---|---|
| Installer une application tierce (Prometheus, Ingress, cert-manager) | **Helm** (chart officiel), values versionnées |
| Déployer vos propres services, 2–5 environnements | **Kustomize** (base + overlays) ou un chart maison simple |
| Distribuer un produit à des clients externes | **Helm** (paramétrage, versions, registre OCI) |
| Besoin de modifier un chart tiers sans le forker | Helm → `helm template` → **Kustomize** (post-rendering) |
| GitOps (Argo CD / Flux) | les deux sont supportés nativement |
| Logique complexe, nombreux paramètres | Helm ; ou générer le YAML avec un autre outil (CUE, jsonnet, KCL) |

### 1.7 Bonnes pratiques de gestion des manifestes
- **Un dépôt GitOps** (ou un répertoire) par environnement/application, séparé du code applicatif.
- **Pas de `--set` à la main** en production : toute valeur est dans Git.
- **Rendu vérifié en CI** : `helm lint`, `helm template | kubeconform -strict`, `kustomize build | kubeconform`, `kube-linter`/`kubescape`, `conftest` (politiques).
- **Versions épinglées** : chart, image (tag immuable ou digest), outils CLI.
- **Différences minimales** entre environnements : seules les valeurs changent (taille, replicas, domaines), pas la structure.
- **Secrets** : jamais dans les values en clair → SOPS, Sealed Secrets, External Secrets, `helm-secrets`.
- **Documentation** : README du chart (valeurs principales), `NOTES.txt` pour l'utilisateur, CHANGELOG.
- **Mises à jour** : Renovate/Dependabot pour les versions de charts et d'images, avec le rendu différentiel dans la PR (`helm diff`, `kubectl diff`).

### 1.8 Dépannage
| Symptôme | Cause probable | Piste |
|---|---|---|
| `rendered manifests contain a resource that already exists` | objet créé hors Helm | `kubectl delete` ou adopter via annotations `meta.helm.sh/release-name` + label `managed-by` |
| `another operation (install/upgrade/rollback) is in progress` | release bloquée en `pending-*` | `helm history`, `helm rollback` ou supprimer le Secret de la révision bloquée |
| Valeurs ignorées | clé erronée / mauvaise indentation | `helm get values`, `helm template --debug`, `values.schema.json` |
| YAML invalide après templating | `nindent`/`indent` incorrect | `helm template --debug` |
| Kustomize ne trouve pas une ressource | chemin/`target` faux | `kustomize build` en local |
| Patch sans effet | nom/kind ne correspond pas à la ressource | vérifier `target`, les `namePrefix` appliqués avant |
| Rollback Helm n'annule pas la base de données | Helm ne gère pas les données | migrations réversibles, sauvegardes |

## 2. 🎬 Démo (40 min)

```bash
# --- Helm : app tierce ---
helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update
helm search repo nginx
helm show values bitnami/nginx | head -60
helm install demo bitnami/nginx -n lab-helm --create-namespace --set service.type=ClusterIP --set replicaCount=2
helm list -n lab-helm ; kubectl -n lab-helm get all
helm upgrade demo bitnami/nginx -n lab-helm --reuse-values --set replicaCount=3
helm history demo -n lab-helm ; helm rollback demo 1 -n lab-helm
helm uninstall demo -n lab-helm

# --- Notre chart ---
helm lint chart-demo
helm template mon-app chart-demo --set ingress.enabled=true | less
helm install mon-app chart-demo -n lab-helm --set env.APP_ENV=dev
kubectl -n lab-helm port-forward svc/mon-app-webapp 8080:80

# --- Kustomize ---
kubectl kustomize kustomize/overlays/dev        # rendu sans appliquer
kubectl kustomize kustomize/overlays/prod
kubectl create ns app-dev ; kubectl create ns app-prod
kubectl apply -k kustomize/overlays/dev
kubectl apply -k kustomize/overlays/prod
kubectl -n app-prod get deploy,cm
```

## 3. 🧪 Labos

### Lab 8.1 ⭐ — Installer une application avec Helm
Installez `bitnami/redis` en `architecture=standalone` (sans persistance : `master.persistence.enabled=false`) dans `lab-helm`. Récupérez le mot de passe depuis le Secret et testez `redis-cli ping`.

<details><summary>Corrigé</summary>

```bash
helm install redis bitnami/redis -n lab-helm --create-namespace \
  --set architecture=standalone --set master.persistence.enabled=false
PW=$(kubectl -n lab-helm get secret redis -o jsonpath='{.data.redis-password}' | base64 -d)
kubectl -n lab-helm exec redis-master-0 -- redis-cli -a "$PW" ping
```
</details>

### Lab 8.2 ⭐⭐ — Values et upgrade
Créez `my-values.yaml` pour le chart `chart-demo` (3 réplicas, tag `1.26`, `env.COLOR=blue`). Installez, puis `upgrade` avec le tag `1.27`, vérifiez `helm history` et faites un `rollback`.

<details><summary>Corrigé</summary>

```bash
cat > my-values.yaml <<EOF
replicaCount: 3
image: {tag: "1.26"}
env: {COLOR: blue}
EOF
helm upgrade --install web ./chart-demo -n lab-helm -f my-values.yaml
helm upgrade web ./chart-demo -n lab-helm -f my-values.yaml --set image.tag=1.27
helm history web -n lab-helm && helm rollback web 1 -n lab-helm
```
</details>

### Lab 8.3 ⭐⭐ — Compléter le chart
Ajoutez au chart : (a) un `ConfigMap` alimenté par `values.config`, injecté via `envFrom` ; (b) une annotation `checksum/config` sur le Pod template pour redéployer quand la config change.

<details><summary>Corrigé</summary>
Template : `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}` dans `spec.template.metadata.annotations`. Valider par `helm template` + `helm lint`.
</details>

### Lab 8.4 ⭐⭐ — Kustomize multi-environnements
Déployez les overlays `dev` et `prod`. Constatez : noms préfixés, replicas, tag d'image, valeur `LOG_LEVEL`. Modifiez `APP_ENV` dans la base : que se passe-t-il pour le nom du ConfigMap (suffixe hash) et les Pods ?

<details><summary>Corrigé</summary>
Le nom du ConfigMap inclut un hash du contenu ; sa modification change le nom → le Deployment est mis à jour → **rolling update automatique**.
</details>

### Lab 8.5 ⭐⭐⭐ — Nouvel overlay `staging`
Créez `overlays/staging` : namespace `app-staging`, 2 réplicas, Ingress ajouté par un patch, label commun `env=staging` (`labels:`).

<details><summary>Corrigé</summary>
Ajoutez `labels: - pairs: {env: staging}` et un `resources: - ingress.yaml` local à l'overlay. Validez avec `kubectl kustomize`.
</details>

### Lab 8.6 ⭐⭐⭐ — Helm + Kustomize (post-rendering)
Rendez un chart tiers avec `helm template`, et appliquez un patch Kustomize pour ajouter un `securityContext` que le chart n'expose pas.

<details><summary>Corrigé</summary>

```bash
helm template demo bitnami/nginx > all.yaml
cat > kustomization.yaml <<EOF
resources: [all.yaml]
patches:
  - target: {kind: Deployment}
    patch: |-
      - op: add
        path: /spec/template/spec/securityContext
        value: {runAsNonRoot: true}
EOF
kubectl kustomize .
```
</details>

## 4. Quiz
1. Où Helm stocke-t-il l'état d'une release ? → Secrets `sh.helm.release.v1.*` du namespace.
2. `helm install` vs `helm upgrade --install` ? → le second est idempotent (CI/CD).
3. Pourquoi `--reuse-values` est-il risqué ? → masque les nouveaux défauts du chart ; préférer `-f values.yaml`.
4. Avantage du hash de `configMapGenerator` ? → rollout automatique au changement de config.
5. Quand préférer Kustomize ? → variantes d'environnement de vos propres manifests, sans template.

Nettoyage : `helm uninstall -n lab-helm --all` (ou `kubectl delete ns lab-helm app-dev app-prod`)
