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
