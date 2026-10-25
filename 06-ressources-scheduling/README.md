# Module 06 — Ressources, Probes, Scheduling et Autoscaling

⏱ 3 h 30 · 🟡 Intermédiaire

## Objectifs
- Dimensionner les Pods (requests/limits, QoS) et éviter OOMKilled / throttling
- Configurer liveness / readiness / startup probes
- Contrôler le placement : nodeSelector, affinités, taints/tolerations, topology spread
- Mettre en place HPA, ResourceQuota, LimitRange, PodDisruptionBudget

## 1. Cours

### 1.1 Requests et limits
- **request** : réservé, utilisé par le **scheduler** (un Pod n'est placé que si la somme des requests tient dans l'`allocatable`).
- **limit** : plafond. CPU dépassé → *throttling* ; mémoire dépassée → **OOMKilled**.
- Unités : `500m` = 0,5 vCPU ; `128Mi`, `1Gi`.

**Classes QoS** (ordre d'éviction en cas de pression mémoire) :
| Classe | Condition |
|---|---|
| `Guaranteed` | requests = limits (CPU et mémoire) pour tous les conteneurs |
| `Burstable` | au moins une request/limit |
| `BestEffort` | rien → évincé en premier |

Bonne pratique courante : request mémoire = limit mémoire ; request CPU définie, limit CPU souvent omise (ou large).

### 1.2 Probes
| Probe | Question | Action en cas d'échec |
|---|---|---|
| **startup** | L'app a-t-elle fini de démarrer ? | Redémarre (bloque les deux autres) |
| **liveness** | L'app est-elle bloquée ? | **Redémarre** le conteneur |
| **readiness** | Peut-elle recevoir du trafic ? | Retire des Endpoints du Service |

Mécanismes : `httpGet`, `tcpSocket`, `exec`, `grpc`. Piège classique : liveness qui dépend de la base de données → redémarrages en cascade.

### 1.3 Scheduling
- `nodeSelector` : simple égalité de labels
- **Node affinity** : `required…` (dur) / `preferred…` (souple)
- **Pod affinity / anti-affinity** : colocaliser / répartir (ex. un réplica par nœud)
- **Taints (nœud) & Tolerations (Pod)** : réserver des nœuds (GPU, control-plane). Effets : `NoSchedule`, `PreferNoSchedule`, `NoExecute`
- **topologySpreadConstraints** : répartition équilibrée par zone/nœud
- `priorityClassName` : préemption

### 1.4 Autoscaling & garde-fous
- **HPA** (`autoscaling/v2`) : ajuste les réplicas selon CPU/mémoire/métriques custom (nécessite **metrics-server** et des **requests CPU**)
- **VPA** : recommande/ajuste les requests ; **Cluster Autoscaler / Karpenter** : ajoute des nœuds ; **KEDA** : scaling événementiel
- **ResourceQuota** : plafonne un namespace ; **LimitRange** : défauts/min/max par conteneur
- **PodDisruptionBudget** : nombre minimal de Pods disponibles pendant `drain`/maintenance

### 1.5 Dimensionner les ressources : la démarche
1. **Mesurer** en conditions réelles (tests de charge) : `kubectl top pods`, Prometheus (`container_memory_working_set_bytes`, `container_cpu_usage_seconds_total`), VPA en mode `Off` (recommandations).
2. **Fixer les requests** près de l'usage typique (percentile 90–95) : elles garantissent la capacité et orientent le scheduler.
3. **Fixer la limite mémoire** au-dessus du pic observé avec marge (20–30 %) : dépasser = OOMKilled.
4. **Limite CPU** : débat ouvert. Une limite provoque du *throttling* même quand le nœud est inoccupé ; beaucoup d'équipes ne posent que des **requests CPU** et laissent les Pods consommer le CPU disponible.
5. **Réviser** régulièrement : l'application évolue.
Risques : *requests trop hautes* → nœuds sous-utilisés, coûts gonflés ; *trop basses* → surcharge des nœuds, voisins bruyants, évictions ; *pas de requests* → BestEffort, évincé en premier, pas d'HPA possible.

**Comment le CPU et la mémoire sont appliqués.** Les requests CPU deviennent des `cpu.weight` (parts proportionnelles) dans les cgroups ; les limites CPU des quotas (`cpu.max`) → throttling. La mémoire est incompressible : au-delà de la limite, le noyau tue le processus (OOM killer). Une **fuite mémoire** se traduit par des redémarrages cycliques (`OOMKilled`).
**Mémoire du nœud** : si un nœud manque de mémoire, le kubelet **évince** d'abord les Pods BestEffort puis les Burstable qui dépassent leurs requests (seuils `eviction-hard`). `allocatable` = capacité − réserves système/kubelet : c'est ce que le scheduler utilise.
**Ressources étendues** : GPU (`nvidia.com/gpu: 1`), hugepages, ressources personnalisées, déclarées par des *device plugins* ; non partageables en fraction par défaut.

### 1.6 Probes : bien les régler
```yaml
startupProbe:   {httpGet: {path: /healthz, port: http}, failureThreshold: 30, periodSeconds: 5}   # jusqu'à 150 s de démarrage
readinessProbe: {httpGet: {path: /ready,   port: http}, periodSeconds: 5,  failureThreshold: 3}
livenessProbe:  {httpGet: {path: /healthz, port: http}, periodSeconds: 10, failureThreshold: 3, timeoutSeconds: 2}
```
| Paramètre | Défaut | Rôle |
|---|---|---|
| `initialDelaySeconds` | 0 | attente avant la 1ʳᵉ sonde (préférer une startupProbe) |
| `periodSeconds` | 10 | fréquence |
| `timeoutSeconds` | 1 | délai de réponse |
| `failureThreshold` | 3 | échecs consécutifs avant action |
| `successThreshold` | 1 | succès nécessaires (readiness) |
Règles d'or :
- **Readiness** = « puis-je servir ? » : peut dépendre de la base de données, du cache chaud. Elle retire le Pod du Service **sans** le redémarrer.
- **Liveness** = « suis-je bloqué ? » : doit être **simple et interne** (ne dépend pas d'autres services). Une liveness trop agressive ou dépendante d'un tiers provoque des cascades de redémarrages lors d'un incident.
- **Startup** pour les applications lentes à démarrer (JVM) : désactive les deux autres tant qu'elle n'a pas réussi.
- Séparer les endpoints (`/live`, `/ready`) ; ne pas journaliser chaque sonde.
- Sans readiness probe, un rolling update envoie du trafic à des Pods qui ne sont pas prêts.

### 1.7 Scheduling : comprendre les décisions
Le scheduler applique d'abord des **filtres** (« le nœud est-il éligible ? ») puis des **scores** (« quel est le meilleur ? »).
| Mécanisme | Dur / souple | Cas d'usage |
|---|---|---|
| `nodeSelector` | dur | cibler un pool (`disk=ssd`) |
| `nodeAffinity` required / preferred | dur / souple | expressions riches (`In`, `NotIn`, `Exists`, `Gt`) |
| `podAffinity` | dur / souple | rapprocher un Pod d'un autre (cache près de l'app) |
| `podAntiAffinity` | dur / souple | répartir les réplicas (un par nœud / zone) |
| `topologySpreadConstraints` | dur (`DoNotSchedule`) / souple (`ScheduleAnyway`) | répartition **équilibrée** (`maxSkew`) par zone, nœud, etc. |
| Taints / tolerations | dur (`NoSchedule`, `NoExecute`) | nœuds dédiés (GPU, système), évictions automatiques |
| `priorityClassName` | — | prioritaire : peut **préempter** (évincer) des Pods moins prioritaires |
| `nodeName` | forcé | contourne le scheduler : à éviter |
Les taints automatiques `node.kubernetes.io/not-ready` et `unreachable` (`NoExecute`) évincent les Pods après `tolerationSeconds` (300 s par défaut). Labels bien connus : `kubernetes.io/hostname`, `topology.kubernetes.io/zone`, `node.kubernetes.io/instance-type`.
**Pourquoi un Pod reste Pending ?** `kubectl describe pod` → `FailedScheduling: 0/3 nodes are available: 1 Insufficient cpu, 2 node(s) had untolerated taint…` : le message énumère les raisons nœud par nœud.

### 1.8 HPA : fonctionnement et réglages
Formule : `replicasDésirés = ceil( replicasActuels × valeurActuelle / valeurCible )`. Exemple : 4 Pods à 90 % CPU avec cible 60 % → `ceil(4 × 90 / 60) = 6`.
- Le pourcentage est calculé **par rapport aux requests** : pas de requests CPU → pas d'autoscaling.
- Le comportement est réglable : `behavior.scaleUp/scaleDown` (`stabilizationWindowSeconds`, `policies` en Pods ou %), pour éviter le *flapping* (300 s de stabilisation à la descente par défaut).
- Métriques : `Resource` (CPU/mémoire), `Pods`/`Object` (via adaptateur Prometheus), `External` (file d'attente) ; **KEDA** simplifie le scaling piloté par les événements (Kafka, SQS, cron) et peut descendre à zéro.
- Ne combinez pas HPA et VPA sur la même métrique ; ne fixez pas `replicas` dans le manifeste d'un Deployment géré par un HPA.
- L'HPA agit sur les Pods : si les nœuds sont pleins, des Pods restent `Pending` tant que **Cluster Autoscaler/Karpenter** n'ajoute pas de capacité.

### 1.9 Garde-fous par namespace
```yaml
kind: ResourceQuota
spec:
  hard: {requests.cpu: "4", requests.memory: 8Gi, limits.memory: 16Gi, pods: "30", persistentvolumeclaims: "10", count/deployments.apps: "20"}
---
kind: LimitRange
spec:
  limits:
    - type: Container
      default:        {cpu: 500m, memory: 256Mi}   # limits par défaut
      defaultRequest: {cpu: 100m, memory: 128Mi}   # requests par défaut
      max:            {cpu: "2",  memory: 2Gi}
```
Une fois un `ResourceQuota` sur `requests.*`/`limits.*` posé, tout Pod **doit** déclarer ces ressources (ou hériter d'un `LimitRange`), sinon il est refusé. Ces objets sont la base de la **multi-location** : ils empêchent une équipe d'affamer les autres.

### 1.10 Disponibilité pendant les opérations
- **PodDisruptionBudget** : `minAvailable` ou `maxUnavailable`. Il protège contre les **perturbations volontaires** (drain, upgrade de nœud, autoscaler) — pas contre les pannes. Un PDB trop strict (`minAvailable` = nombre de réplicas) **bloque** les drains.
- `kubectl drain` : `cordon` (plus de nouveaux Pods) puis éviction respectueuse des PDB et du `terminationGracePeriodSeconds`.
- **Priorité et préemption** : réserver une `PriorityClass` haute aux composants critiques, une classe basse (voire `preemptionPolicy: Never`) aux tâches batch.
- **Haute disponibilité d'un service** : ≥ 2 réplicas + anti-affinity/topologySpread + PDB + readiness + arrêt gracieux.

### 1.11 Le coût des ressources
Un cluster paie ce qui est **réservé** (requests), pas ce qui est utilisé. Leviers : right-sizing (VPA, Goldilocks), consolidation de nœuds (Karpenter), instances Spot/préemptibles pour le stateless tolérant, extinction hors heures des environnements de dev, suivi par namespace/label (OpenCost, Kubecost).

## 2. 🎬 Démo (45 min)

Prérequis : `make metrics`

```bash
kubectl create ns lab-ressources && kubectl config set-context --current --namespace=lab-ressources

# QoS & OOM
kubectl apply -f manifests/01-oom.yaml
kubectl get pod oom -w                         # OOMKilled -> CrashLoopBackOff
kubectl describe pod oom | grep -A3 'Last State'
kubectl get pod oom -o jsonpath='{.status.qosClass}'

# Probes
kubectl apply -f manifests/02-probes.yaml
kubectl get pods -w                            # liveness-demo redémarre (RESTARTS augmente)

# Taints / affinité
kubectl taint nodes formation-worker2 dedie=gpu:NoSchedule
kubectl apply -f manifests/03-scheduling.yaml && kubectl get pods -o wide
kubectl taint nodes formation-worker2 dedie=gpu:NoSchedule-

# HPA
kubectl apply -f manifests/04-hpa.yaml
kubectl run load --image=busybox:1.36 --restart=Never -- sh -c 'while true; do wget -q -O- http://php-apache; done'
kubectl get hpa -w
kubectl delete pod load
```

## 3. 🧪 Labos

> Namespace : `lab-ressources`

### Lab 6.1 ⭐ — Requests, limits, QoS
Créez trois Pods : `qos-g` (Guaranteed), `qos-b` (Burstable), `qos-be` (BestEffort). Vérifiez `status.qosClass`.

<details><summary>Corrigé</summary>

```bash
kubectl run qos-be --image=nginx:1.27                     # BestEffort
kubectl apply -f manifests/07-qos.yaml                    # qos-b (Burstable) et qos-g (Guaranteed)
kubectl get pods -o custom-columns=N:.metadata.name,QOS:.status.qosClass
```
</details>

### Lab 6.2 ⭐⭐ — Diagnostiquer un OOMKilled
Le Pod `oom` consomme 200 Mi pour une limite de 100 Mi. Prouvez la cause (`Reason: OOMKilled`, exit code 137) et corrigez en réglant la limite à 300 Mi.

<details><summary>Corrigé</summary>
`kubectl describe pod oom` → `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`. Corriger `limits.memory: 300Mi` puis recréer le Pod.
</details>

### Lab 6.3 ⭐⭐ — Probes
1. Ajoutez une readiness probe `/` à nginx. Cassez-la (mauvais chemin) : le Pod reste `0/1` et sort des Endpoints, sans redémarrer.
2. Ajoutez une liveness probe qui échoue : le conteneur redémarre. Comparez.

<details><summary>Corrigé</summary>
Voir `02-probes.yaml`. `kubectl get endpoints` montre l'absence du Pod en cas d'échec de readiness.
</details>

### Lab 6.4 ⭐⭐ — Taints et tolerations
Taintez `formation-worker2` avec `dedie=gpu:NoSchedule`. Déployez 4 réplicas : tous sur les autres nœuds. Ajoutez une toleration + `nodeSelector` pour qu'un Deployment `gpu-app` ne tourne **que** sur ce nœud.

<details><summary>Corrigé</summary>
Voir `03-scheduling.yaml` (Deployment `gpu-app`). Il faut **les deux** : la toleration autorise, le nodeSelector/affinity attire.
</details>

### Lab 6.5 ⭐⭐ — Anti-affinity et topologySpread
Déployez 3 réplicas de `web` qui doivent se répartir sur des nœuds différents (`podAntiAffinity` ou `topologySpreadConstraints` sur `kubernetes.io/hostname`). Que se passe-t-il avec 5 réplicas si l'anti-affinity est `required` ? Et avec `maxSkew: 1` + `ScheduleAnyway` ?

<details><summary>Corrigé</summary>
Avec `required` anti-affinity et 3 nœuds éligibles, les réplicas 4-5 restent `Pending`. Avec topologySpread `ScheduleAnyway` ils sont placés au mieux (répartition 2/2/1).
</details>

### Lab 6.6 ⭐⭐ — HPA
Déployez `php-apache` avec requests CPU 200m et un HPA cible 50 % CPU, min 1, max 5. Générez de la charge et observez la montée, puis la descente (stabilisation 5 min par défaut).

<details><summary>Corrigé</summary>
Voir `04-hpa.yaml`. Si `TARGETS` reste `<unknown>` : metrics-server absent ou requests manquantes.
</details>

### Lab 6.7 ⭐⭐ — Quota et LimitRange
Dans un namespace dédié (`kubectl create ns lab-quota`), créez un `ResourceQuota` (`pods=5`, `requests.cpu=1`, `requests.memory=1Gi`) et un `LimitRange` (défaut 100m/128Mi). Créez 6 Pods : le 6ᵉ est refusé. Créez un Pod sans resources : valeurs par défaut injectées.

<details><summary>Corrigé</summary>
Voir `05-quota.yaml` (namespace `lab-quota`, à créer avant ; `-n lab-quota` pour les commandes). Erreur : `exceeded quota`. `kubectl describe quota` montre la consommation.
</details>

### Lab 6.8 ⭐⭐⭐ — PodDisruptionBudget et drain
Déployez 3 réplicas avec un PDB `minAvailable: 2`. Faites `kubectl drain formation-worker --ignore-daemonsets --delete-emptydir-data` et observez que les évictions respectent le PDB. `kubectl uncordon` ensuite.

<details><summary>Corrigé</summary>
Voir `06-pdb.yaml`. `drain` évince Pod par Pod en attendant que le PDB soit satisfait ; avec `minAvailable` trop strict (= replicas), le drain **bloque**.
</details>

### Lab 6.9 ⭐⭐⭐ — Dimensionnement
À partir de `kubectl top pods`, proposez des requests/limits pour `php-apache` après charge. Justifiez : p95 d'usage, marge, QoS visée.

<details><summary>Corrigé</summary>
Pas de réponse unique : request ≈ p90-p95 de l'usage CPU, mémoire request = limit ≈ pic + 20-30 %. En production, utilisez VPA en mode recommandation + Prometheus.
</details>

## 4. Quiz
1. Dépassement de limite mémoire ? → OOMKilled (137). CPU ? → throttling.
2. Readiness vs liveness ? → retrait du trafic vs redémarrage.
3. Pourquoi mon HPA affiche `<unknown>` ? → pas de metrics-server ou pas de requests CPU.
4. Toleration suffit-elle à attirer un Pod sur un nœud taint ? → non, elle autorise seulement.
5. PDB protège contre quoi ? → évictions *volontaires* (drain, upgrade), pas les pannes.

Nettoyage : `kubectl delete ns lab-ressources lab-quota` et `kubectl uncordon formation-worker`
