# Module 03 — Workloads : Deployments, StatefulSets, DaemonSets, Jobs

⏱ 3 h · 🟢🟡

## Objectifs
- Déployer et scaler une application avec un **Deployment**
- Réaliser un **rolling update** et un **rollback** ; choisir une stratégie
- Choisir entre Deployment, StatefulSet, DaemonSet, Job, CronJob

## 1. Cours

### 1.1 Hiérarchie
`Deployment` → `ReplicaSet` (une révision = un RS) → `Pod`.
Le Deployment pilote les mises à jour en créant un nouveau ReplicaSet et en réduisant l'ancien.

### 1.2 Stratégies de mise à jour
| Stratégie | Comportement | Usage |
|---|---|---|
| `RollingUpdate` (défaut) | Remplacement progressif ; `maxSurge` (Pods en plus) / `maxUnavailable` | Zéro-downtime |
| `Recreate` | Tout arrêter puis recréer | Apps qui ne tolèrent pas 2 versions |

Autres : blue/green (2 Deployments + bascule du Service), canary (Argo Rollouts / Flagger / 2 Deployments pondérés).

`kubectl rollout status|history|undo|pause|resume|restart deploy/<nom>`. Gardez `revisionHistoryLimit` raisonnable (10 par défaut).

### 1.3 Choisir le bon contrôleur
| Besoin | Objet |
|---|---|
| Application stateless, N réplicas | **Deployment** |
| Identité stable, stockage par réplica, ordre (BDD, Kafka, etcd) | **StatefulSet** (+ Service headless) |
| 1 Pod par nœud (logs, monitoring, CNI) | **DaemonSet** |
| Tâche finie | **Job** (`completions`, `parallelism`, `backoffLimit`) |
| Tâche planifiée | **CronJob** (`schedule`, `concurrencyPolicy`) |

StatefulSet : Pods `nom-0`, `nom-1`…, DNS stable `nom-0.svc`, `volumeClaimTemplates` (un PVC par Pod), démarrage ordonné.

## 2. 🎬 Démo (30 min)

```bash
kubectl create ns lab-workloads && kubectl config set-context --current --namespace=lab-workloads
kubectl apply -f manifests/01-deployment.yaml
kubectl get deploy,rs,pods
kubectl scale deploy web --replicas=5

# Rolling update (observer dans un 2e terminal : kubectl get pods -w)
kubectl set image deploy/web nginx=nginx:1.27-alpine
kubectl rollout status deploy/web
kubectl rollout history deploy/web
kubectl get rs                                   # ancien RS à 0, nouveau à 5

# Mise à jour ratée + rollback
kubectl set image deploy/web nginx=nginx:does-not-exist
kubectl rollout status deploy/web --timeout=30s  # bloqué, mais le service reste disponible !
kubectl rollout undo deploy/web

# Autres contrôleurs
kubectl apply -f manifests/02-statefulset.yaml && kubectl get pods -w
kubectl apply -f manifests/03-daemonset.yaml && kubectl get ds,pods -o wide
kubectl apply -f manifests/04-job.yaml && kubectl logs job/calcul-pi
kubectl apply -f manifests/05-cronjob.yaml && kubectl get cronjob,jobs -w
```

## 3. 🧪 Labos

> Namespace : `lab-workloads`

### Lab 3.1 ⭐ — Déployer et scaler
1. Créez le Deployment `web` (3 réplicas de `nginx:1.26`).
2. Passez à 5 réplicas, puis revenez à 2.
3. Supprimez un Pod : que se passe-t-il ? Pourquoi son nom change-t-il ?

<details><summary>Corrigé</summary>

```bash
kubectl apply -f manifests/01-deployment.yaml
kubectl scale deploy web --replicas=5 ; kubectl scale deploy web --replicas=2
kubectl delete pod -l app=web --field-selector=status.phase=Running --wait=false
```
Le ReplicaSet recrée un Pod : nouveau Pod = nouveau nom (suffixe aléatoire) et nouvelle IP.
</details>

### Lab 3.2 ⭐⭐ — Rolling update maîtrisé
Configurez `maxSurge: 1`, `maxUnavailable: 0`, 4 réplicas. Mettez à jour vers `nginx:1.27`. Observez que le nombre de Pods Ready ne descend jamais sous 4. Consultez `rollout history`, annotez la cause avec `kubectl annotate deploy web kubernetes.io/change-cause="nginx 1.27"`.

<details><summary>Corrigé</summary>

```bash
kubectl patch deploy web -p '{"spec":{"replicas":4,"strategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl annotate deploy web kubernetes.io/change-cause="nginx 1.27"
kubectl set image deploy/web nginx=nginx:1.27
kubectl get pods -w
kubectl rollout history deploy/web
```
</details>

### Lab 3.3 ⭐⭐ — Rollback
Déployez une mauvaise image, constatez le blocage, revenez à la révision 1 avec `--to-revision`.

<details><summary>Corrigé</summary>

```bash
kubectl set image deploy/web nginx=nginx:bad
kubectl rollout history deploy/web
kubectl rollout undo deploy/web --to-revision=1
```
</details>

### Lab 3.4 ⭐⭐ — StatefulSet et identité stable
Appliquez `02-statefulset.yaml` (3 réplicas). Supprimez `db-1` : vérifiez qu'il revient avec le **même nom** et le **même volume**. Écrivez un fichier dans `/data` de `db-0`, supprimez `db-0`, relisez le fichier.

<details><summary>Corrigé</summary>

```bash
kubectl exec db-0 -- sh -c 'echo persistant > /data/test.txt'
kubectl delete pod db-0 && kubectl wait --for=condition=ready pod/db-0
kubectl exec db-0 -- cat /data/test.txt
kubectl get pvc          # data-db-0, data-db-1, data-db-2 (restent après scale down !)
```
</details>

### Lab 3.5 ⭐⭐ — DaemonSet
Déployez un DaemonSet `node-agent` : 1 Pod par worker, **sans** Pod sur le control-plane. Puis faites-le tourner aussi sur le control-plane avec une toleration.

<details><summary>Corrigé</summary>
Par défaut le control-plane a le taint `node-role.kubernetes.io/control-plane:NoSchedule`. Ajouter :

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```
</details>

### Lab 3.6 ⭐⭐ — Jobs parallèles
Job de 6 complétions, 2 en parallèle, qui dort 5 s puis affiche son nom. Observez les vagues de 2 Pods.

<details><summary>Corrigé</summary>
`manifests/04-job.yaml` (second document) : `completions: 6`, `parallelism: 2`.
</details>

### Lab 3.7 ⭐⭐⭐ — CronJob de sauvegarde simulée
CronJob toutes les minutes, `concurrencyPolicy: Forbid`, garde 2 jobs réussis et 1 échec. Suspendez-le (`kubectl patch ... suspend:true`) et déclenchez un run manuel : `kubectl create job --from=cronjob/backup backup-manuel`.

<details><summary>Corrigé</summary>
Voir `manifests/05-cronjob.yaml`.
</details>

### Lab 3.8 ⭐⭐⭐ — Blue/Green avec deux Deployments
Créez `app-blue` (nginx:1.26, label `version=blue`) et `app-green` (nginx:1.27, `version=green`) derrière un Service qui sélectionne `version=blue`. Basculez sur green avec un `kubectl patch svc` — sans coupure. (Nécessite le module 04 pour le Service ; fait en fil rouge.)

<details><summary>Corrigé</summary>

```bash
kubectl patch svc app -p '{"spec":{"selector":{"app":"app","version":"green"}}}'
```
</details>

## 4. Quiz
1. Quel objet garde l'historique de révisions ? → les ReplicaSets.
2. `maxUnavailable: 0` + `maxSurge: 1` apporte quoi ? → jamais moins de Pods Ready que souhaité (au prix de ressources supplémentaires temporaires).
3. Pourquoi un StatefulSet a-t-il besoin d'un Service headless ? → DNS stable par Pod (`db-0.db`).
4. Les PVC d'un StatefulSet sont-ils supprimés au scale down ? → non (sauf `persistentVolumeClaimRetentionPolicy`).
5. Différence Job / CronJob / DaemonSet ? → fini / planifié / un par nœud.

Nettoyage : `kubectl delete ns lab-workloads`
