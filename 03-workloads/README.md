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

### 1.4 Deployment : ce qui se passe réellement
Un Deployment ne gère **pas** les Pods : il gère des **ReplicaSets**. Le `pod-template-hash` est un hash du `spec.template` ajouté en label ; toute modification du *template* (image, variables, ressources…) crée un nouveau ReplicaSet, alors qu'un changement de `replicas` ne touche que le ReplicaSet courant. Pour un rolling update :
```
RS-v1 : 4 → 3 → 2 → 1 → 0
RS-v2 : 0 → 1 → 2 → 3 → 4
```
à chaque étape, Kubernetes respecte `maxSurge` (Pods en plus du souhaité, 25 % par défaut) et `maxUnavailable` (Pods manquants tolérés, 25 % par défaut) — mais **uniquement des Pods Ready** : la **readiness probe** conditionne la progression. Sans readiness probe, Kubernetes considère les Pods prêts dès qu'ils tournent et une mise à jour défaillante peut remplacer tous les Pods sains.

| Champ | Rôle | Conseil |
|---|---|---|
| `minReadySeconds` | durée pendant laquelle un Pod doit rester Ready avant d'être compté | 5–30 s pour détecter les plantages précoces |
| `progressDeadlineSeconds` | délai (600 s) avant de déclarer le déploiement bloqué (`ProgressDeadlineExceeded`) | adapter au temps de démarrage |
| `revisionHistoryLimit` | nombre d'anciens ReplicaSets conservés pour le rollback | 3–10 |
| `strategy.rollingUpdate` | rythme du remplacement | `maxUnavailable: 0` pour ne jamais perdre de capacité |

**Un rollout ne se bloque pas par magie** : avec `maxUnavailable: 0`, si les nouveaux Pods ne deviennent jamais Ready, l'ancienne version continue de servir : le service est préservé, le déploiement reste « en cours ». C'est la raison d'être des probes.

### 1.5 Pièges des mises à jour
- **Changer un ConfigMap ne redémarre pas** les Pods. Techniques : `kubectl rollout restart deploy/x`, ou nommer le ConfigMap avec un hash (Kustomize `configMapGenerator`, Helm `checksum/config` en annotation), ou le monter en volume et recharger à chaud.
- **Tag `latest`** : un `apply` identique ne déclenche aucun rollout (le template n'a pas changé).
- **Connexions longues** : un Pod `Terminating` coupe les connexions existantes ; prévoir SIGTERM gracieux et `preStop`.
- **Migrations de base de données** : le schéma doit rester compatible avec l'ancienne **et** la nouvelle version pendant le rollout (pattern *expand/contract*).
- **Données partagées** : deux versions de l'application coexistent forcément ; sinon utiliser `Recreate`.

### 1.6 Stratégies de livraison avancées
| Stratégie | Principe | Mise en œuvre |
|---|---|---|
| **Rolling update** | remplacement progressif | natif |
| **Recreate** | arrêt puis redémarrage | natif, avec coupure |
| **Blue/Green** | deux environnements complets, bascule du Service | 2 Deployments + changement du `selector` ; retour arrière immédiat, coût double |
| **Canary** | une fraction du trafic vers la nouvelle version | 2 Deployments (nombre de réplicas ≈ pourcentage) ou Ingress/Gateway pondéré ; **Argo Rollouts / Flagger** pour l'analyse automatique |
| **Feature flags** | découpler déploiement et activation | côté application |
Critère de choix : un retour arrière doit être **rapide, simple et testé**.

### 1.7 StatefulSet en profondeur
- **Identité stable** : nom `<sts>-<ordinal>`, DNS `<pod>.<service-headless>`, volume dédié (`volumeClaimTemplates` → PVC `data-<sts>-<n>`).
- **Ordre** : `podManagementPolicy: OrderedReady` (défaut : démarrage séquentiel 0, 1, 2 ; arrêt inverse) ou `Parallel`.
- **Mises à jour** : `RollingUpdate` (du plus grand ordinal au plus petit) avec `partition` pour faire un *canary* (seuls les Pods d'ordinal ≥ partition sont mis à jour) ; `OnDelete` pour un contrôle manuel.
- **Suppression** : supprimer ou réduire un StatefulSet **ne supprime pas** les PVC (protection des données) ; `persistentVolumeClaimRetentionPolicy` permet de changer ce comportement (`whenDeleted`, `whenScaled`).
- **Ce qu'un StatefulSet ne fait pas** : sauvegarde, réplication des données, élection de leader, bascule : c'est le travail de l'application ou d'un **opérateur** (CloudNativePG, Strimzi…). Exécuter une base en StatefulSet « à la main » n'est raisonnable que si l'on maîtrise ces aspects.

### 1.8 DaemonSet en profondeur
Cas d'usage : collecte de logs (Fluent Bit, Alloy), métriques (node-exporter), réseau (CNI, kube-proxy), stockage (CSI node), sécurité (Falco). Particularités : pas de champ `replicas` ; un Pod par nœud **éligible** (`nodeSelector`, affinité, tolerations) ; les nouveaux nœuds reçoivent automatiquement le Pod. Mise à jour : `RollingUpdate` avec `maxUnavailable` (nœuds mis à jour en parallèle) ; `OnDelete` pour une maîtrise totale. Les DaemonSets système tolèrent généralement les taints (`operator: Exists`) pour tourner partout, control plane compris.

### 1.9 Job et CronJob en profondeur
**Job**
| Champ | Rôle |
|---|---|
| `completions` | nombre de réussites nécessaires |
| `parallelism` | Pods simultanés |
| `backoffLimit` | tentatives avant échec (6 par défaut), délai exponentiel |
| `activeDeadlineSeconds` | durée maximale totale |
| `ttlSecondsAfterFinished` | nettoyage automatique du Job et de ses Pods |
| `completionMode: Indexed` | chaque Pod reçoit un index (`JOB_COMPLETION_INDEX`) : traitement de lots partitionnés |
| `restartPolicy` | obligatoirement `OnFailure` ou `Never` (jamais `Always`) |
Un Job doit être **idempotent** : une tentative peut être rejouée, voire exécutée deux fois dans de rares cas.

**CronJob**
| Champ | Rôle |
|---|---|
| `schedule` | syntaxe cron (`*/5 * * * *`) ; fuseau UTC par défaut, `timeZone` (GA 1.27) pour un autre |
| `concurrencyPolicy` | `Allow` (défaut), `Forbid` (saute si le précédent tourne), `Replace` |
| `startingDeadlineSeconds` | délai de rattrapage si une exécution a été manquée |
| `successfulJobsHistoryLimit` / `failedJobsHistoryLimit` | historique conservé (3 / 1 par défaut) |
| `suspend` | mise en pause |
Attention : au-delà de 100 exécutions manquées consécutives, le CronJob cesse de planifier. Un CronJob n'est pas un orchestrateur de workflows (dépendances, reprise) : pour cela, Argo Workflows, Airflow, Tekton.

### 1.10 Choisir son contrôleur : arbre de décision
```
Mon programme s'arrête-t-il de lui-même ?
├─ Oui ── à intervalles réguliers ? ── Oui → CronJob      Non → Job
└─ Non (service permanent)
     ├─ un Pod par nœud ? ───────────────────────────── DaemonSet
     ├─ identité/volume/ordre par réplica ? ──────────── StatefulSet (ou opérateur)
     └─ sinon (stateless) ─────────────────────────────── Deployment
```

### 1.11 Dimensionner le nombre de réplicas
- **Disponibilité** : au moins 2 réplicas pour tout service critique, répartis sur des nœuds/zones différents (anti-affinity, topologySpread, module 06) ; un **PodDisruptionBudget** protège lors des maintenances.
- **Capacité** : répartir la charge sur N réplicas = chaque Pod porte 1/N ; en cas de perte d'un Pod, les autres doivent absorber 1/(N-1).
- **Élasticité** : HPA (module 06) ajuste `replicas` ; dans ce cas, **ne pas** fixer `replicas` dans le manifeste appliqué par GitOps (sinon conflit).

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
kubectl delete pod $(kubectl get pods -l app=web -o name | head -1)
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
