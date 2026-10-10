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
kubectl run qos-be --image=nginx:1.27
kubectl run qos-b --image=nginx:1.27 --requests='cpu=100m'
kubectl run qos-g --image=nginx:1.27 --requests='cpu=100m,memory=64Mi' --limits='cpu=100m,memory=64Mi'
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
