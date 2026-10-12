# Module 02 — Les Pods

⏱ 2 h 30 · 🟢 Débutant

## Objectifs
- Écrire un Pod complet (image, ports, env, commande)
- Maîtriser labels, selectors, namespaces
- Comprendre cycle de vie, restartPolicy, phases
- Utiliser initContainers et sidecars ; déboguer (`logs`, `exec`, `describe`, `port-forward`)

## 1. Cours

### 1.1 Le Pod
Plus petite unité déployable : **1 ou plusieurs conteneurs** qui partagent le réseau (une IP, `localhost`), les volumes et l'IPC. Un Pod est **éphémère** : jamais « réparé », toujours remplacé → on ne crée presque jamais de Pod nu en production (voir Deployment, module 03).

### 1.2 Cycle de vie
Phases : `Pending` → `Running` → `Succeeded` / `Failed` (`Unknown`).
États de conteneur : `Waiting` (ex. `ImagePullBackOff`, `CrashLoopBackOff`), `Running`, `Terminated`.
`restartPolicy` : `Always` (défaut) · `OnFailure` · `Never`.

Arrêt gracieux : SIGTERM → attente `terminationGracePeriodSeconds` (30 s) → SIGKILL. Hook `preStop` possible.

### 1.3 Conteneurs multiples — patterns
| Pattern | Exemple |
|---|---|
| **Init container** | Attendre une base, migrer un schéma, télécharger une config (séquentiel, avant l'app) |
| **Sidecar** | Collecte de logs, proxy mTLS (K8s ≥ 1.29 : `initContainers` avec `restartPolicy: Always`) |
| **Adapter / Ambassador** | Normaliser des métriques, proxy vers un service distant |

### 1.4 Labels, selectors, namespaces
```bash
kubectl get pods -l app=web,tier=front
kubectl get pods -l 'env in (prod,staging)'
kubectl label pod demo env=dev --overwrite
```

### 1.5 Anatomie complète d'un Pod
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api
  labels: {app: api, tier: back}
spec:
  serviceAccountName: api              # identité vis-à-vis de l'API (module 07)
  restartPolicy: Always
  terminationGracePeriodSeconds: 30
  initContainers: [...]                # exécutés dans l'ordre, avant l'application
  containers:
    - name: api
      image: ghcr.io/acme/api:1.4.2    # tag précis, jamais « latest » en production
      imagePullPolicy: IfNotPresent
      command: ["/app/server"]         # remplace ENTRYPOINT de l'image
      args: ["--port=8080"]            # remplace CMD de l'image
      ports: [{name: http, containerPort: 8080}]
      env:
        - {name: LOG_LEVEL, value: info}
        - name: POD_IP
          valueFrom: {fieldRef: {fieldPath: status.podIP}}   # Downward API
      resources:                       # module 06
        requests: {cpu: 100m, memory: 128Mi}
        limits: {memory: 256Mi}
      readinessProbe: {httpGet: {path: /ready, port: http}}
      volumeMounts: [{name: tmp, mountPath: /tmp}]
  volumes:
    - name: tmp
      emptyDir: {}
```
**`command` / `args` vs `ENTRYPOINT` / `CMD`** : `command` remplace `ENTRYPOINT` et `args` remplace `CMD`. Si vous ne fournissez que `args`, l'`ENTRYPOINT` de l'image est conservé. Une confusion fréquente qui produit des `CrashLoopBackOff` mystérieux.

**`imagePullPolicy`** : `Always` (vérifie le registre à chaque démarrage), `IfNotPresent` (utilise l'image locale si elle existe), `Never`. Le défaut est `Always` si le tag est `latest` (ou absent), `IfNotPresent` sinon. Un tag mutable (`1.4`) peut pointer vers des contenus différents selon les nœuds : préférez un **tag immuable** ou un **digest** (`image@sha256:…`).

**Registre privé** : créer un Secret `kubernetes.io/dockerconfigjson` (`kubectl create secret docker-registry …`) et le référencer dans `imagePullSecrets` du Pod ou du ServiceAccount.

### 1.6 Cycle de vie en détail
```
Pending ──(scheduler + images tirées)──► Running ──(tous les conteneurs terminés)──► Succeeded / Failed
   │                                         │
   └─ Unschedulable, ImagePullBackOff       └─ CrashLoopBackOff : redémarrages avec délai croissant (10 s, 20 s, 40 s… plafonné à 5 min)
```
**Conditions** d'un Pod (`kubectl describe pod`) : `PodScheduled` → `Initialized` (init containers terminés) → `ContainersReady` → `Ready` (le Pod peut recevoir du trafic). Un Pod `Running` peut ne pas être `Ready`.

**Codes de sortie à reconnaître** : `0` succès ; `1` erreur applicative ; `137` = SIGKILL (souvent **OOMKilled** : mémoire dépassée) ; `139` = segfault ; `143` = SIGTERM (arrêt normal). `kubectl describe pod` → `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`.

**Séquence d'arrêt d'un Pod** (suppression, mise à jour, éviction) :
1. Le Pod passe en `Terminating` et est **retiré des Endpoints** des Services ;
2. le hook `preStop` s'exécute (s'il existe) ;
3. SIGTERM est envoyé au PID 1 de chaque conteneur ;
4. après `terminationGracePeriodSeconds`, SIGKILL.
Les étapes 1 et 3 sont **concurrentes** : pendant quelques instants des requêtes peuvent encore arriver alors que l'application s'arrête. Parades : `preStop: sleep 5`, gestion propre de SIGTERM (finir les requêtes en cours, refuser les nouvelles), grace period adaptée.

**Hooks** : `postStart` (juste après le démarrage, sans garantie d'ordre avec l'ENTRYPOINT) et `preStop`. À utiliser avec parcimonie.

### 1.7 PID 1 et signaux dans les conteneurs
Le premier processus du conteneur (PID 1) a un comportement spécial : sans gestionnaire de signal explicite, **SIGTERM est ignoré** ; il doit en outre récupérer (*reap*) les processus orphelins. Conséquences : lancer l'application via un shell (`sh -c "app"`) place le shell en PID 1, qui ne transmet pas les signaux. Solutions : utiliser la forme *exec* (`exec app`), le champ `command` sous forme de liste, ou un mini-init (`tini`, `dumb-init`, `shareProcessNamespace` ou `init: true` côté Docker).

### 1.8 Partage de ressources entre conteneurs d'un Pod
| Ressource | Partagée ? | Détail |
|---|:---:|---|
| Réseau (IP, ports, `localhost`) | ✅ | deux conteneurs ne peuvent pas écouter sur le même port |
| Volumes | ✅ si montés | `emptyDir` pour échanger des fichiers |
| IPC / PID | optionnel | `shareProcessNamespace: true` (débogage, sidecar de monitoring) |
| Système de fichiers racine | ❌ | chaque conteneur a le sien |
| Ressources CPU/mémoire | ❌ | requests/limits **par conteneur**, le Pod = somme |
Pour le scheduling, la demande d'un Pod = **max(plus gros init container, somme des conteneurs d'application)**.

### 1.9 Sidecars natifs et conteneurs éphémères
- **Sidecar natif** (Kubernetes ≥ 1.29 en beta, activé par défaut) : un `initContainer` avec `restartPolicy: Always` démarre avant l'application, y reste pendant toute la vie du Pod, puis s'arrête **après** elle. Il résout les problèmes classiques : un sidecar qui bloque la fin d'un `Job`, ou qui démarre trop tard.
- **Conteneur éphémère** (`kubectl debug -it pod/x --image=busybox --target=app`) : ajoute temporairement un conteneur de diagnostic dans un Pod en cours d'exécution, sans le redéployer. Idéal pour les images « distroless » dépourvues de shell.
- **Static Pods** : gérés directement par le kubelet depuis un répertoire du nœud (control plane kubeadm).

### 1.10 Downward API : donner au Pod la connaissance de lui-même
Exposer le nom du Pod, son namespace, son IP, ses labels ou ses limites de ressources via des variables (`fieldRef`, `resourceFieldRef`) ou un volume `downwardAPI`. Utile pour les logs structurés, le nommage et le dimensionnement (ex. `GOMAXPROCS`, taille du tas JVM).

### 1.11 Labels, annotations et bonnes pratiques de nommage
Labels recommandés (`app.kubernetes.io/*`) : `name`, `instance`, `version`, `component`, `part-of`, `managed-by`. Ils servent à **sélectionner** (Service, Deployment, NetworkPolicy) : un label modifié par erreur peut déconnecter un Pod de son Service. Les **annotations** ne servent jamais à sélectionner : documentation, configuration d'outils (Ingress, Prometheus), traçabilité (`kubernetes.io/change-cause`).
Syntaxe : clé `[préfixe/]nom` (nom ≤ 63 caractères, alphanumérique, `-`, `_`, `.`), valeur ≤ 63 caractères.

### 1.12 Pourquoi on ne crée (presque) jamais de Pod nu
Un Pod nu n'a **aucun contrôleur** : si le nœud tombe ou si le Pod est évincé, il disparaît définitivement. Les Pods nus sont acceptables pour : un test (`kubectl run`), un débogage, ou une tâche ponctuelle. Dès qu'il faut de la durabilité : Deployment, StatefulSet, DaemonSet ou Job (module 03).

### 1.13 Diagnostic d'un Pod : grille de lecture
| État affiché (`STATUS`) | Signification | Premier réflexe |
|---|---|---|
| `Pending` | non planifié (ressources, taints, PVC) ou images en cours de pull | `describe` → section *Events* |
| `ContainerCreating` | montage de volumes, pull d'image | `describe` ; volumes/secret manquants |
| `ImagePullBackOff` / `ErrImagePull` | image introuvable, tag erroné, droits | nom/tag, `imagePullSecrets` |
| `CrashLoopBackOff` | le conteneur plante en boucle | `logs --previous`, code de sortie |
| `CreateContainerConfigError` | ConfigMap/Secret référencé introuvable | `describe`, créer la ressource |
| `Error` / `OOMKilled` | échec / mémoire dépassée | code de sortie, limits |
| `Completed` | Pod terminé avec succès (Job) | normal |
| `Terminating` bloqué | finalizer, nœud injoignable, volume | `describe`, `--force --grace-period=0` en dernier recours |
| `Running` mais `0/1 Ready` | readiness en échec | probe, port, logs |

## 2. 🎬 Démo (25 min)

```bash
kubectl create ns lab-pods
kubectl config set-context --current --namespace=lab-pods
kubectl apply -f manifests/01-pod-simple.yaml
kubectl get pod web -o wide
kubectl describe pod web                       # section Events !
kubectl port-forward pod/web 8080:80 &         # curl localhost:8080
kubectl exec -it web -- sh
kubectl logs web
kubectl apply -f manifests/03-pod-crashloop.yaml
kubectl get pod crash -w                       # CrashLoopBackOff + backoff exponentiel
kubectl logs crash --previous
kubectl apply -f manifests/04-pod-init.yaml && kubectl get pod init-demo -w
kubectl apply -f manifests/05-pod-sidecar.yaml && kubectl logs sidecar-demo -c log-reader
```

## 3. 🧪 Labos

> Namespace : `lab-pods`

### Lab 2.1 ⭐ — Premier Pod
Créez le Pod `web` (nginx:1.27) avec les labels `app=web, tier=front`, exposez-le via `port-forward` et vérifiez la page d'accueil. Listez-le avec le selector `tier=front`.

<details><summary>Corrigé</summary>

```bash
kubectl apply -f manifests/01-pod-simple.yaml
kubectl port-forward pod/web 8080:80 &
curl -s localhost:8080 | grep -i welcome
kubectl get pods -l tier=front
```
</details>

### Lab 2.2 ⭐ — Variables d'environnement et commande
Créez un Pod `hello` (busybox:1.36) qui affiche `Bonjour $NOM` toutes les 5 s, avec `NOM=Kube`. Lisez ses logs.

<details><summary>Corrigé</summary>

```bash
kubectl apply -f manifests/02-pod-env.yaml
kubectl logs hello -f
```
</details>

### Lab 2.3 ⭐⭐ — Dépanner trois Pods cassés
Appliquez `manifests/06-pods-casses.yaml`. Trois Pods échouent. Pour chacun : diagnostiquez (`describe`, `logs`, `events`) et corrigez **sans changer de nom de Pod**.

<details><summary>Corrigé</summary>

- `casse-image` → `ErrImagePull` : tag inexistant `nginx:1.99.99` → utiliser `nginx:1.27`
- `casse-cmd` → `CrashLoopBackOff` : commande `exit 1` → corriger la commande (`sleep 3600`)
- `casse-pending` → `Pending` : demande 100 CPU → `describe` montre `Insufficient cpu` → réduire à `100m`

Un Pod est largement immuable : `kubectl delete pod X && kubectl apply -f ...` (ou `kubectl replace --force`).
</details>

### Lab 2.4 ⭐⭐ — Init container
Écrivez un Pod dont l'init container écrit `Prêt à <date>` dans un `emptyDir` ; le conteneur principal (nginx) sert ce fichier comme `index.html`. Vérifiez via `port-forward`.

<details><summary>Corrigé</summary>
Voir `manifests/04-pod-init.yaml`. Le volume `emptyDir` est monté dans l'init sur `/work` et dans nginx sur `/usr/share/nginx/html`.
</details>

### Lab 2.5 ⭐⭐⭐ — Sidecar de logs
Un conteneur `app` écrit un log dans `/var/log/app.log` (volume partagé) ; un sidecar lit ce fichier avec `tail -F` et l'affiche sur stdout. Vérifiez avec `kubectl logs <pod> -c <sidecar>`.

<details><summary>Corrigé</summary>
Voir `manifests/05-pod-sidecar.yaml`.
</details>

### Lab 2.6 ⭐⭐⭐ — Arrêt gracieux
Créez un Pod qui intercepte SIGTERM (`trap`), affiche « arrêt propre » puis quitte. Supprimez-le et mesurez le temps ; refaites en retirant le `trap` : que constatez-vous (30 s) ? Pourquoi ?

<details><summary>Corrigé</summary>
Avec `sleep` en PID 1 sans handler, SIGTERM est ignoré (PID 1 n'a pas de handler par défaut) → attente de 30 s puis SIGKILL. Avec `trap`, sortie immédiate. En prod : gérer SIGTERM dans l'app ou utiliser `tini`/`dumb-init`.
</details>

## 4. Quiz
1. Pourquoi un Pod nu est-il déconseillé ? → pas de recréation si le nœud tombe.
2. Les conteneurs d'un Pod communiquent comment ? → `localhost`, volumes partagés.
3. `CrashLoopBackOff` ? → le conteneur redémarre en boucle avec délai croissant (10 s → 5 min).
4. Quel flag lit les logs du conteneur précédent ? → `--previous`.
5. Différence init container / sidecar ? → init : séquentiel et terminé avant l'app ; sidecar : tourne en parallèle.

Nettoyage : `kubectl delete ns lab-pods`
