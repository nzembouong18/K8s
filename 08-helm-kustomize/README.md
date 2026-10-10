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
