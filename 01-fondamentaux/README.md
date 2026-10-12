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

### 1.6 Les composants en détail

**kube-apiserver — le pipeline d'une requête.** Chaque appel (`kubectl`, kubelet, contrôleur) traverse la même chaîne :
1. **Authentification** (qui es-tu ? certificat client, jeton de ServiceAccount, OIDC) ;
2. **Autorisation** (as-tu le droit ? RBAC) ;
3. **Admission mutante** (modifie l'objet : injection de sidecar, valeurs par défaut) ;
4. **Validation du schéma** (l'objet respecte-t-il l'API ?) ;
5. **Admission validante** (politiques : Pod Security, Kyverno, ValidatingAdmissionPolicy) ;
6. **Persistance** dans etcd, puis notification aux observateurs (`watch`).
L'API server est **sans état** : on peut en avoir plusieurs derrière un load-balancer.

**etcd — la mémoire du cluster.** Base clé-valeur répliquée par le consensus **Raft** : une écriture n'est validée que si la **majorité** (quorum) des membres l'a enregistrée.
| Membres | Quorum | Pannes tolérées |
|:---:|:---:|:---:|
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 5 | 3 | 2 |
Toujours un nombre **impair** (4 membres ne tolèrent pas plus de pannes que 3). Perdre le quorum = cluster en lecture seule. Les performances d'etcd dépendent de la latence disque : SSD obligatoire en production.

**kube-scheduler — deux phases.** Pour chaque Pod non affecté : (1) **filtrage** (quels nœuds *peuvent* l'accueillir ? ressources, taints, affinités, volumes) ; (2) **notation** (parmi eux, lequel est le *meilleur* ? répartition, localité d'image). Il ne démarre rien : il écrit seulement `spec.nodeName`.

**kube-controller-manager — des dizaines de boucles.** Chaque contrôleur observe un type d'objet et agit : ReplicaSet (nombre de Pods), Deployment (révisions), Node (détection de nœud perdu), Job, EndpointSlice, ServiceAccount, Namespace (nettoyage à la suppression)… Un **cloud-controller-manager** gère la partie spécifique au cloud (LoadBalancer, volumes, routes).

**kubelet — l'agent du nœud.** Observe les Pods affectés à son nœud, demande au runtime (CRI) de créer sandbox et conteneurs, exécute les **probes**, monte les volumes, remonte `status` et heartbeats (objet `Lease`). Il peut aussi lancer des **static Pods** depuis `/etc/kubernetes/manifests` : c'est ainsi que kubeadm démarre apiserver, scheduler, controller-manager et etcd.

**kube-proxy — les Services.** Programme sur chaque nœud des règles (iptables, IPVS ou nftables) qui redirigent l'IP virtuelle d'un Service vers l'un de ses Pods. Certains CNI (Cilium) le remplacent par eBPF.

**Les trois interfaces d'extension.** **CRI** (runtime de conteneurs : containerd, CRI-O), **CNI** (réseau des Pods), **CSI** (stockage). Docker n'est plus un runtime supporté directement depuis Kubernetes 1.24 (retrait de *dockershim*) : les images Docker restent parfaitement utilisables.

### 1.7 L'API Kubernetes
Tout est une **ressource REST** : `GET /api/v1/namespaces/default/pods`, `POST /apis/apps/v1/namespaces/default/deployments`. Un objet est identifié par **groupe / version / type** :
| `apiVersion` | Contient |
|---|---|
| `v1` (groupe « core ») | Pod, Service, ConfigMap, Secret, Namespace, PersistentVolumeClaim, Node |
| `apps/v1` | Deployment, StatefulSet, DaemonSet, ReplicaSet |
| `batch/v1` | Job, CronJob |
| `networking.k8s.io/v1` | Ingress, NetworkPolicy |
| `rbac.authorization.k8s.io/v1` | Role, ClusterRole, RoleBinding… |
| `autoscaling/v2` | HorizontalPodAutoscaler |
| `<groupe-crd>/v1alpha1` | vos CRD (opérateurs) |
Versions : `alpha` (désactivées par défaut, peuvent disparaître), `beta` (activées, susceptibles d'évoluer), `v1` (stable). Des API sont **dépréciées puis retirées** à chaque version mineure : vérifiez-les avant une montée de version (`kubectl convert`, outils Pluto / kubent).

**Anatomie d'un objet.** `metadata.name` (unique par type et namespace), `uid`, `resourceVersion` (verrouillage optimiste), `generation`, `labels`, `annotations`, `ownerReferences` (qui possède cet objet : suppression en cascade), `finalizers` (tâches à terminer avant suppression), `creationTimestamp`.

**`watch` et `resourceVersion`.** Les contrôleurs ne font pas de sondage : ils ouvrent un flux `watch` et reçoivent les événements `ADDED/MODIFIED/DELETED`. C'est ce qui rend Kubernetes réactif.

**Client-side vs server-side apply.** `kubectl apply` (côté client) calcule un patch à partir de l'annotation `last-applied-configuration`. `kubectl apply --server-side` laisse le serveur fusionner et suivre **qui possède quels champs** (`managedFields`) : indispensable quand plusieurs outils (Helm, HPA, Argo CD) touchent le même objet.

### 1.8 Catalogue des objets à connaître
| Famille | Objets | Module |
|---|---|:---:|
| Exécution | Pod, Deployment, ReplicaSet, StatefulSet, DaemonSet, Job, CronJob | 02–03 |
| Réseau | Service, EndpointSlice, Ingress, Gateway/HTTPRoute, NetworkPolicy | 04 |
| Configuration | ConfigMap, Secret | 05 |
| Stockage | Volume, PV, PVC, StorageClass, VolumeSnapshot | 05 |
| Ressources | LimitRange, ResourceQuota, HPA, PriorityClass, PodDisruptionBudget | 06 |
| Sécurité | ServiceAccount, Role, ClusterRole, bindings, Pod Security | 07 |
| Organisation | Namespace, Node, labels/annotations | 01 |
| Extension | CustomResourceDefinition, webhooks | 10 |

### 1.9 YAML sans surprise
- L'indentation se fait en **espaces** (jamais de tabulations), 2 par niveau par convention.
- Les listes s'écrivent avec `- `, les maps avec `clé: valeur`.
- Piège des types : `port: "80"` (texte) ≠ `port: 80` (nombre) ; `value: yes` / `on` / `true` deviennent des booléens ; pour une chaîne, **mettez des guillemets** (`"true"`, `"1.20"` sinon lu comme nombre 1.2).
- Plusieurs objets dans un fichier : séparateur `---`.
- Chaînes multi-lignes : `|` (conserve les retours à la ligne) et `>` (les replie).
- Validez avant d'appliquer : `kubectl apply --dry-run=server -f x.yaml` (le serveur valide vraiment), `kubectl diff -f x.yaml`, `kubeconform` en CI.

### 1.10 `kubectl` en profondeur
```bash
# Contextes et namespaces
kubectl config get-contexts ; kubectl config use-context kind-formation
kubectl config set-context --current --namespace=lab-x       # namespace par défaut
# Sélection
kubectl get pods -l app=web -o wide                          # par label
kubectl get pods --field-selector status.phase=Running       # par champ
kubectl get all -n lab-x                                     # (« all » n'inclut pas tout !)
# Formats de sortie
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'
kubectl get pods -o custom-columns=NOM:.metadata.name,NOEUD:.spec.nodeName,IP:.status.podIP
kubectl get pods --sort-by=.metadata.creationTimestamp
# Modifier
kubectl edit deploy web                                      # ouvre l'éditeur
kubectl patch deploy web -p '{"spec":{"replicas":3}}'        # patch fusion (strategic merge)
kubectl set image deploy/web nginx=nginx:1.27
kubectl label|annotate ...
kubectl delete -f x.yaml ; kubectl delete pod -l app=web
# Attendre
kubectl wait --for=condition=available deploy/web --timeout=120s
kubectl rollout status deploy/web
# Générer sans créer
kubectl create deployment web --image=nginx --dry-run=client -o yaml
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh
```
Autocomplétion et alias : `source <(kubectl completion bash)`, `alias k=kubectl`, `complete -o default -F __start_kubectl k`. Plugins utiles : `kubectx/kubens`, `stern` (logs multi-pods), `k9s` (interface terminal), `kubectl-neat`, `kubectl-tree` (arbre des `ownerReferences`).

### 1.11 Namespaces : ce qu'ils isolent… et ce qu'ils n'isolent pas
Ils isolent les **noms** (deux `web` dans deux namespaces), les **droits** (RBAC par namespace), les **quotas** et, avec NetworkPolicy, les flux. Ils **n'isolent pas** le réseau par défaut (tout Pod joint tout Pod), ni les nœuds (les Pods de tous les namespaces partagent les mêmes machines et le même noyau). Namespaces système : `kube-system`, `kube-public`, `kube-node-lease`, `default` (à ne pas utiliser pour de vraies applications). Certaines ressources ne sont **pas** namespacées (`Node`, `PersistentVolume`, `StorageClass`, `ClusterRole`, `Namespace`) : `kubectl api-resources --namespaced=false`.

### 1.12 Erreurs fréquentes des débutants
| Erreur | Explication | Correctif |
|---|---|---|
| Éditer un Pod créé par un Deployment | le Deployment remettra l'ancienne version | modifier le Deployment |
| Oublier `-n namespace` | commande exécutée dans `default` | fixer le namespace du contexte |
| `kubectl apply` après `kubectl edit` / `scale` | divergence entre le fichier et le cluster | tout passer par les fichiers |
| Utiliser `latest` comme tag | image non reproductible, comportement de pull variable | tag précis ou digest |
| Confondre `port`, `targetPort`, `containerPort`, `nodePort` | voir module 04 | schéma du module 04 |
| Supprimer un Pod pour « relancer » une mise à jour de config | non maîtrisé | `kubectl rollout restart` |
| Penser que `Running` = application prête | seule la **readiness** le dit | configurer les probes (module 06) |

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
