# Module 09 — Observabilité et Dépannage

⏱ 3 h · 🟡🔴

## Objectifs
- Superviser avec **metrics-server**, **Prometheus**, **Grafana**, **Alertmanager**
- Collecter et interroger les logs (kubectl, stern, Loki)
- Appliquer une **méthode de débogage** structurée ; utiliser `kubectl debug`

## 1. Cours

### 1.1 Les trois piliers (+1)
| Pilier | Question | Outils |
|---|---|---|
| **Métriques** | Quelle est la santé / la tendance ? | metrics-server (`kubectl top`), Prometheus, Grafana |
| **Logs** | Que s'est-il passé ? | stdout/stderr → Loki / EFK / cloud |
| **Traces** | Où le temps est-il perdu ? | OpenTelemetry, Tempo, Jaeger |
| **Événements** | Que fait le cluster ? | `kubectl get events`, kube-state-metrics |

### 1.2 Prometheus dans Kubernetes
Modèle *pull* : scrape de `/metrics`. Sources clés : **kubelet/cAdvisor** (conteneurs), **kube-state-metrics** (objets), **node-exporter** (OS), apps instrumentées. Avec le **Prometheus Operator** : CRD `ServiceMonitor`, `PodMonitor`, `PrometheusRule`. Le chart **kube-prometheus-stack** installe tout (+ dashboards Grafana + alertes de base).

PromQL utile :
```promql
sum(rate(container_cpu_usage_seconds_total{namespace="lab-obs"}[5m])) by (pod)
sum(kube_pod_container_status_restarts_total) by (pod) > 3
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
```
Méthodes : **RED** (Rate, Errors, Duration) pour les services ; **USE** (Utilization, Saturation, Errors) pour les ressources ; **4 golden signals**.

### 1.3 Logs
Les conteneurs écrivent sur **stdout/stderr** ; le runtime garde des fichiers sur le nœud (rotation kubelet). Pour la rétention et la recherche : agent DaemonSet (Promtail/Alloy, Fluent Bit, Vector) → Loki/Elasticsearch.

### 1.4 Méthode de dépannage
```
Pod Pending            → describe: Insufficient cpu/memory, taints, PVC non lié, nodeSelector
ImagePullBackOff       → nom/tag, registre privé (imagePullSecrets), réseau
CrashLoopBackOff       → logs --previous, exit code, probe, config manquante, OOMKilled (137)
Running mais 0/1       → readiness probe, describe, endpoints
Service injoignable    → endpoints vides ? selector ? targetPort ? NetworkPolicy ? DNS ?
Ingress 404/502/503    → host/path, service/port, endpoints, logs du contrôleur
Nœud NotReady          → kubelet (journalctl), runtime, disque/mémoire, CNI
```
Réflexe : **`get` → `describe` (Events) → `logs` → `exec`/`debug` → événements → nœud**.

### 1.5 Les types de métriques Prometheus
| Type | Description | Exemple | Requête type |
|---|---|---|---|
| **Counter** | ne fait qu'augmenter (redémarre à 0) | `http_requests_total` | `rate(...[5m])` |
| **Gauge** | monte et descend | `memory_usage_bytes`, `queue_length` | valeur brute, `avg_over_time` |
| **Histogram** | répartition en *buckets* + somme + compte | `http_request_duration_seconds_bucket` | `histogram_quantile(0.95, …)` |
| **Summary** | quantiles calculés côté client | rarement préférable à l'histogramme | — |
Règles : un counter se lit toujours avec `rate()`/`increase()` ; les quantiles d'histogrammes s'agrègent, pas ceux des summaries ; **attention à la cardinalité** : chaque combinaison de labels crée une série (ne jamais mettre d'identifiant utilisateur ou d'URL complète en label).

### 1.6 Dans le cluster : qui expose quoi ?
| Source | Expose | Exemples de métriques |
|---|---|---|
| **kubelet / cAdvisor** | consommation par conteneur | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes` |
| **kube-state-metrics** | état des objets API | `kube_pod_status_phase`, `kube_deployment_status_replicas_available`, `kube_pod_container_status_restarts_total` |
| **node-exporter** | métriques de l'OS du nœud | `node_cpu_seconds_total`, `node_filesystem_avail_bytes` |
| **metrics-server** | métriques « instantanées » pour `kubectl top` et l'HPA | (API `metrics.k8s.io`) |
| **Composants du control plane** | API server, etcd, scheduler | `apiserver_request_duration_seconds`, `etcd_server_has_leader` |
| **Applications** | métriques métier et techniques | via bibliothèques client + `/metrics` |
**Découverte** : avec le Prometheus Operator, un `ServiceMonitor` (sélecteur de Service + port) ou un `PodMonitor` déclare quoi scraper ; les règles d'alerte sont des `PrometheusRule`. Le label `release: <nom-du-chart>` est souvent requis pour que Prometheus les sélectionne (piège classique : « ma cible n'apparaît pas »).

### 1.7 Alerter intelligemment
Principes d'une bonne alerte :
- elle signale un **symptôme ressenti par l'utilisateur** (erreurs, latence) plutôt qu'une cause supposée (CPU à 80 %) ;
- elle est **actionnable** : un humain sait quoi faire, avec un lien vers un runbook ;
- elle est **urgente** si elle réveille quelqu'un ; sinon, un ticket ;
- elle évite le bruit : durée `for: 5m`, regroupement, inhibition.
```yaml
- alert: HighErrorRate
  expr: sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.05
  for: 10m
  labels: {severity: page}
  annotations:
    summary: "Plus de 5 % d'erreurs 5xx"
    runbook_url: https://wiki.exemple.com/runbooks/high-error-rate
```
**Alertmanager** gère le routage (par `severity`, `team`), le regroupement (`group_by`), la mise en silence et l'inhibition, vers Slack, PagerDuty, e-mail.
**SLO et budget d'erreur** : définir un objectif (99,9 % de requêtes réussies sur 30 jours), mesurer des **SLI**, alerter sur la **vitesse de consommation du budget** (burn rate) plutôt que sur chaque pic.

### 1.8 Logs : bonnes pratiques
- Écrire sur **stdout/stderr**, en **JSON structuré** (niveau, horodatage, identifiant de requête/trace) ; ne pas écrire de fichiers dans le conteneur.
- Ne jamais journaliser de secrets ni de données personnelles.
- Pile typique : agent en DaemonSet (**Alloy, Promtail, Fluent Bit, Vector**) → **Loki** (index par labels, stockage objet bon marché) ou Elasticsearch/OpenSearch.
- Requêtes LogQL : `{namespace="app", app="api"} |= "error" | json | level="error"`, `rate({app="api"} |= "error"[5m])`.
- Rétention et coûts : filtrer à la source, échantillonner, durées différentes par criticité.
- `kubectl logs` : `-f` (suivi), `--previous`, `--since=10m`, `-c conteneur`, `-l app=web --all-containers --prefix`, `stern` pour agréger plusieurs Pods. La rotation sur le nœud limite ce que `kubectl logs` voit.

### 1.9 Traces distribuées
Une **trace** suit une requête à travers plusieurs services ; un **span** est une étape. **OpenTelemetry** (standard) instrumente les applications (SDK ou auto-instrumentation via l'opérateur OTel) et envoie les données via un **Collector** vers Tempo, Jaeger, ou un service commercial. Propager l'identifiant de trace (en-tête `traceparent`) et l'inscrire dans les logs permet de passer d'une alerte → trace → logs de la requête fautive.

### 1.10 Événements Kubernetes
`kubectl get events --sort-by=.lastTimestamp` : raisons (`Scheduled`, `Pulled`, `FailedScheduling`, `BackOff`, `Unhealthy`, `Evicted`, `OOMKilling`…). Les événements sont **éphémères** (≈ 1 h) : pour l'historique, exportez-les (kubernetes-event-exporter, Alloy) vers Loki/Elasticsearch. Ils sont aussi une source d'alertes précieuse.

### 1.11 Dashboards utiles à construire
1. **Vue cluster** : nœuds Ready, saturation CPU/mémoire/disque, Pods non Ready, Pods Pending, redémarrages.
2. **Vue namespace/application** : réplicas disponibles vs désirés, requests vs usage, redémarrages, OOMKilled.
3. **Vue service (RED)** : débit, taux d'erreur, latence p50/p95/p99.
4. **Vue ressources (USE)** : utilisation, saturation, erreurs des nœuds et volumes.
5. **Vue control plane** : latence de l'API, taille d'etcd, file d'attente du scheduler.
Éviter les « murs de graphiques » : chaque dashboard répond à une question précise.

### 1.12 Outils de diagnostic interactif
```bash
kubectl top pods --containers --sort-by=memory
kubectl debug -it pod/api --image=busybox:1.36 --target=api          # conteneur éphémère
kubectl debug node/worker1 -it --image=ubuntu                        # shell sur le nœud (chroot /host)
kubectl debug pod/api --copy-to=api-debug --container=api -- sleep 1d  # copie modifiable du Pod
kubectl get pod api -o jsonpath='{.status.containerStatuses[0].lastState}'
kubectl get --raw /metrics | head                                    # métriques de l'API server
kubectl auth can-i ... ; kubectl get events -A --field-selector type=Warning
```
**k9s**, **Lens** et **Headlamp** offrent une vue interactive ; **Hubble** (Cilium) et **Pixie** donnent de la visibilité réseau/applicative sans modifier le code.

### 1.13 Études de cas : du symptôme à la cause
| Symptôme | Hypothèses | Vérifications |
|---|---|---|
| Latence en hausse | saturation CPU (throttling), base lente, GC, réseau | `container_cpu_cfs_throttled_*`, traces, métriques de la base |
| Redémarrages en boucle | OOMKilled, liveness trop stricte, config manquante | code de sortie, `logs --previous`, événements |
| 503 intermittents après déploiement | readiness absente, arrêt non gracieux | probes, `preStop`, journaux du contrôleur d'Ingress |
| Pods `Pending` | requests > capacité, quota atteint, taints | `describe pod`, `describe node`, ResourceQuota |
| Nœud `NotReady` | kubelet arrêté, disque plein, pression mémoire, CNI | `journalctl -u kubelet`, `df -h`, conditions du nœud |
| Disque du nœud plein | logs, images inutilisées, `emptyDir` | `crictl images`, nettoyage (GC kubelet), quotas éphémères |

## 2. 🎬 Démo (45 min)

```bash
# metrics-server
make -C .. metrics            # depuis la racine du dépôt
kubectl top nodes ; kubectl top pods -A --sort-by=memory | head

# kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm install kps prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
  --set grafana.adminPassword=formation \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set kubeEtcd.enabled=false --set kubeControllerManager.enabled=false \
  --set kubeScheduler.enabled=false --set kubeProxy.enabled=false
kubectl -n monitoring get pods -w
kubectl -n monitoring port-forward svc/kps-grafana 3000:80          # admin / formation
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090

# Application instrumentée + ServiceMonitor + alerte
kubectl create ns lab-obs
kubectl apply -f manifests/01-app-metrics.yaml
kubectl apply -f manifests/02-servicemonitor-rule.yaml
# Prometheus → Status → Targets : "lab-obs/demo-app" UP ; Alerts : DemoAppDown
```

Dans Grafana : *Dashboards → Kubernetes / Compute Resources / Namespace (Pods)*, *Node Exporter / Nodes*.

## 3. 🧪 Labos

### Lab 9.1 ⭐ — kubectl top
Identifiez le Pod le plus consommateur en CPU et en mémoire du cluster. Quel nœud est le plus chargé ?

<details><summary>Corrigé</summary>

```bash
kubectl top pods -A --sort-by=cpu | head -5
kubectl top pods -A --sort-by=memory | head -5
kubectl top nodes
```
</details>

### Lab 9.2 ⭐⭐ — Logs efficaces
Avec `kubectl logs` : dernières 20 lignes, avec horodatage, depuis 5 min, tous les Pods d'un label (`-l app=web --prefix`), conteneur précédent. Installez `stern` pour suivre plusieurs Pods.

<details><summary>Corrigé</summary>

```bash
kubectl logs deploy/web --tail=20 --timestamps
kubectl logs -l app=web --since=5m --prefix --max-log-requests=10
kubectl logs pod/x --previous
stern -n lab-obs demo
```
</details>

### Lab 9.3 ⭐⭐ — Chasse aux pannes (« 5 scénarios »)
Appliquez `manifests/03-pannes.yaml` (crée le namespace `lab-pannes`) : 5 applications `app1`…`app5` ont chacune un défaut différent. Trouvez et corrigez chacune sans lire les solutions.

<details><summary>Corrigé</summary>

| App | Symptôme | Cause | Correction |
|---|---|---|---|
| app1 | `ImagePullBackOff` | tag `nginx:1.27.99` inexistant | `nginx:1.27` |
| app2 | `CreateContainerConfigError` | Secret `app2-secret` manquant | créer le Secret |
| app3 | Service sans Endpoints | selector `app: app-3` ≠ label `app3` | corriger le selector |
| app4 | `0/1 Running` | readiness sur `/health` (404) | chemin `/` |
| app5 | `Pending` | `nodeSelector: gpu=true` inexistant | retirer / labelliser un nœud |
</details>

### Lab 9.4 ⭐⭐ — Métriques applicatives
Déployez l'app (`01-app-metrics.yaml`, expose `/metrics`), ajoutez le `ServiceMonitor`, retrouvez la série `nginx_*`/`http_*` dans Prometheus, puis créez un graphe Grafana (*Explore*).

<details><summary>Corrigé</summary>
Vérifier : Service avec un port **nommé** (`metrics`), label du Service = `selector` du ServiceMonitor, ServiceMonitor visible (`serviceMonitorSelectorNilUsesHelmValues=false`). Targets UP dans l'UI Prometheus.
</details>

### Lab 9.5 ⭐⭐⭐ — Alerte
Provoquez l'alerte `DemoAppDown` (scale à 0), constatez l'état Pending → Firing dans Prometheus, puis dans Alertmanager (`port-forward svc/kps-kube-prometheus-stack-alertmanager 9093`).

<details><summary>Corrigé</summary>
`kubectl -n lab-obs scale deploy demo-app --replicas=0` ; attendre `for: 1m`. Restaurer avec `--replicas=2`.
</details>

### Lab 9.6 ⭐⭐⭐ — kubectl debug
Un Pod distroless n'a pas de shell. Utilisez un conteneur éphémère : `kubectl debug -it <pod> --image=busybox:1.36 --target=<conteneur>`. Puis déboguez un **nœud** : `kubectl debug node/formation-worker -it --image=busybox:1.36`.

<details><summary>Corrigé</summary>

```bash
kubectl debug -it demo-app-xxx -n lab-obs --image=busybox:1.36 --target=nginx -- sh
kubectl debug node/formation-worker -it --image=busybox:1.36   # FS hôte sous /host
```
</details>

### Lab 9.7 ⭐⭐ — Événements et nœud
Listez les 10 derniers événements `Warning` du cluster et analysez-en un. Consultez ensuite les logs du kubelet d'un nœud kind : `docker exec formation-worker journalctl -u kubelet --no-pager | tail`.

<details><summary>Corrigé</summary>

```bash
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -10
```
</details>

## 4. Quiz
1. `kubectl top` utilise quel composant ? → metrics-server (API `metrics.k8s.io`).
2. Que fait un `ServiceMonitor` ? → déclare à Prometheus Operator quels Services scraper.
3. Que signifie exit code 137 ? → SIGKILL (souvent OOMKilled).
4. Où retrouver les logs d'un Pod supprimé ? → uniquement dans un stockage centralisé (Loki/EFK).
5. Méthode RED ? → Rate, Errors, Duration.

Nettoyage : `helm uninstall kps -n monitoring ; kubectl delete ns monitoring lab-obs`
