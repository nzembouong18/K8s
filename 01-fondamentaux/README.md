# Module 01 — Fondamentaux de Kubernetes

⏱ 2 h · 🟢 Débutant

## Objectifs
- Expliquer pourquoi Kubernetes existe et ce qu'il résout
- Décrire l'architecture (control plane, nœuds) et le rôle de chaque composant
- Comprendre le modèle déclaratif, la boucle de réconciliation et l'API
- Utiliser `kubectl` : `get`, `describe`, `explain`, `apply`, `delete`

## 1. Cours

### 1.1 Du conteneur à l'orchestrateur
Un conteneur isole un processus (namespaces + cgroups) avec son filesystem. Mais en production il faut : planifier sur plusieurs machines, redémarrer en cas de panne, répartir la charge, mettre à jour sans coupure, scaler, gérer config et secrets. **Kubernetes (K8s)** est l'orchestrateur standard (CNCF, issu de Google Borg).

### 1.2 Architecture

```
                 ┌────────────────────── CONTROL PLANE ──────────────────────┐
 kubectl ──────► │ kube-apiserver ◄──► etcd (état du cluster)                  │
 (HTTPS/REST)    │      ▲                                                       │
                 │      ├── kube-scheduler (choisit le nœud d'un Pod)           │
                 │      └── kube-controller-manager (boucles de réconciliation) │
                 └──────────────────────────────────────────────────────────────┘
                        │ watch / update                      │
        ┌───────────────▼───────────┐          ┌──────────────▼────────────┐
        │ NODE                      │          │ NODE                      │
        │ kubelet · kube-proxy      │          │ kubelet · kube-proxy      │
        │ container runtime (CRI)   │          │ container runtime (CRI)   │
        │ [Pod][Pod][Pod]           │          │ [Pod][Pod]                │
        └───────────────────────────┘          └───────────────────────────┘
```

| Composant | Rôle |
|---|---|
| **kube-apiserver** | Seule porte d'entrée (REST). Authentifie, autorise, valide, persiste dans etcd |
| **etcd** | Base clé/valeur distribuée (Raft) : source de vérité |
| **kube-scheduler** | Affecte les Pods sans nœud (ressources, affinités, taints) |
| **controller-manager** | Contrôleurs : Deployment, ReplicaSet, Node, Job… |
| **kubelet** | Agent du nœud : démarre les conteneurs via CRI, remonte l'état |
| **kube-proxy** | Programme iptables/IPVS pour les Services |
| **CRI** (containerd, CRI-O) | Exécute les conteneurs |
| **CNI** (Calico, Cilium, Flannel) | Réseau des Pods |
| **CoreDNS** | DNS interne du cluster |

### 1.3 Modèle déclaratif et réconciliation
On décrit **l'état désiré** (YAML) ; les contrôleurs comparent en boucle *état observé* vs *état désiré* et agissent. Exemple : `replicas: 3` mais 2 Pods → le ReplicaSet en crée un.

Flux de `kubectl apply -f deploy.yaml` :
1. kubectl → apiserver (authN → authZ → admission → validation) → etcd
2. Deployment controller crée un ReplicaSet → crée les Pods (sans nœud)
3. Scheduler affecte un nœud → kubelet démarre les conteneurs → statut remonté

### 1.4 Objets de base et structure d'un manifest

```yaml
apiVersion: v1          # groupe/version de l'API
kind: Pod               # type d'objet
metadata:               # identité : name, namespace, labels, annotations
  name: demo
spec:                   # état DÉSIRÉ (écrit par vous)
  containers: [...]
# status:               # état OBSERVÉ (écrit par le cluster)
```

- **Namespace** : partition logique (isolation de noms, quotas, RBAC)
- **Labels / selectors** : liaison souple entre objets (`app=web`)
- **Annotations** : métadonnées non sélectives (outils, docs)

### 1.5 kubectl — commandes essentielles
`get`, `describe`, `logs`, `exec`, `apply`, `delete`, `explain`, `api-resources`, `diff`, `-o yaml|wide|json|jsonpath`, `-n <ns>`, `-A`, `-l <label>`, `--watch`.

## 2. 🎬 Démo (20 min) — « Ce qui se passe quand on crée un Deployment »

```bash
kubectl create ns lab-fondamentaux
kubectl -n lab-fondamentaux create deployment web --image=nginx:1.27 --replicas=3
kubectl -n lab-fondamentaux get deploy,rs,pods -o wide
kubectl -n lab-fondamentaux get events --sort-by=.lastTimestamp     # la chaîne d'événements
kubectl -n lab-fondamentaux delete pod -l app=web --wait=false      # self-healing
kubectl -n lab-fondamentaux get pods -w
kubectl explain deployment.spec.strategy --recursive | head -30
kubectl api-resources | head -20
kubectl get --raw /version
kubectl -n lab-fondamentaux get deploy web -o yaml | less           # spec vs status
```
À commenter : la hiérarchie Deployment → ReplicaSet → Pod (`ownerReferences`), l'auto-réparation, l'`explain`.

## 3. 🧪 Labos

### Lab 1.1 ⭐ — Explorer le cluster
1. Combien de namespaces existent ? Lesquels sont système ?
2. Quelle est la version de Kubernetes du serveur ? du kubelet de chaque nœud ?
3. Quel plugin CNI est utilisé (indice : pods de `kube-system`) ?

<details><summary>Corrigé</summary>

```bash
kubectl get ns
kubectl version
kubectl get nodes -o custom-columns=NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion
kubectl -n kube-system get pods     # kindnet (CNI de kind)
```
</details>

### Lab 1.2 ⭐ — Impératif vs déclaratif
1. Générez le YAML d'un Deployment `api` (image `nginx:1.27`, 2 réplicas) **sans le créer**, sauvegardez-le dans `api.yaml`.
2. Appliquez-le, puis modifiez `replicas: 4` dans le fichier, utilisez `kubectl diff` puis `apply`.

<details><summary>Corrigé</summary>

```bash
kubectl create deployment api --image=nginx:1.27 --replicas=2 --dry-run=client -o yaml > api.yaml
kubectl -n lab-fondamentaux apply -f api.yaml
sed -i 's/replicas: 2/replicas: 4/' api.yaml
kubectl -n lab-fondamentaux diff -f api.yaml
kubectl -n lab-fondamentaux apply -f api.yaml
```
</details>

### Lab 1.3 ⭐⭐ — Lire la doc depuis le terminal
Sans internet, retrouvez : (a) les valeurs possibles de `spec.strategy.type` d'un Deployment, (b) le champ qui définit la politique de pull d'image d'un conteneur, (c) la liste des ressources du groupe `apps`.

<details><summary>Corrigé</summary>

```bash
kubectl explain deployment.spec.strategy.type      # RollingUpdate | Recreate
kubectl explain pod.spec.containers.imagePullPolicy
kubectl api-resources --api-group=apps
```
</details>

### Lab 1.4 ⭐⭐ — Self-healing observé
Supprimez le nœud worker 2 du point de vue Kubernetes en l'arrêtant (`docker stop formation-worker2`). Observez l'état du nœud et des Pods pendant ~5 min (`kubectl get nodes -w`). Redémarrez-le. Expliquez le délai (indice : `node-monitor-grace-period`, tolérances `node.kubernetes.io/unreachable` de 300 s).

<details><summary>Corrigé</summary>
Le nœud passe `NotReady` après ~40 s ; les Pods ne sont évincés qu'après 300 s (toleration par défaut `tolerationSeconds: 300`). Les Pods d'un Deployment sont recréés ailleurs ; ceux d'un DaemonSet restent liés au nœud.
</details>

## 4. Quiz
1. Quel composant écrit dans etcd ? → uniquement **kube-apiserver**.
2. Différence `spec` / `status` ? → désiré vs observé.
3. Qui place un Pod sur un nœud ? → kube-scheduler ; qui le démarre ? → kubelet.
4. Pourquoi privilégier `apply` à `create` en production ? → idempotent, versionnable (GitOps), diff possible.
5. Que fait un contrôleur ? → réconcilie en boucle état observé → état désiré.

Nettoyage : `kubectl delete ns lab-fondamentaux`
