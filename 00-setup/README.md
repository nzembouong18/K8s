# Module 00 — Mise en place de l'environnement

⏱ 45 min · 🟢 Débutant

## Objectifs
- Installer `kubectl`, `kind`, `helm`
- Créer un cluster local multi-nœuds
- Configurer le shell (alias, autocomplétion) pour être efficace

## 1. Cours : pourquoi kind ?

| Outil | Usage | Multi-nœuds | Remarque |
|---|---|---|---|
| **kind** | Labs, CI | ✅ | Nœuds = conteneurs Docker. Choisi ici |
| minikube | Poste dev | ✅ | Plus de drivers (VM, Docker) |
| k3s / k3d | Edge, labs légers | ✅ | Distribution allégée |
| kubeadm | Cluster « vrai » | ✅ | Voir module 10 |
| EKS / AKS / GKE | Production cloud | ✅ | Control plane managé |

### Pour aller plus loin : comprendre ce que l'on installe

**Comment fonctionne kind ?** Chaque « nœud » est un conteneur Docker qui embarque `systemd`, `containerd` et les binaires Kubernetes. kind génère les certificats, lance `kubeadm init` dans le premier conteneur (control plane) puis `kubeadm join` dans les autres, installe un CNI (kindnet) et une StorageClass locale. C'est donc un **vrai** cluster Kubernetes, simplement empaqueté dans Docker : tout ce qui est appris ici (API, manifests, `kubectl`) se transpose tel quel sur un cluster de production.

**Limites à connaître**
| Sujet | Sur kind | En production |
|---|---|---|
| LoadBalancer | pas d'IP externe (il faut MetalLB ou `cloud-provider-kind`) | fourni par le cloud |
| Stockage | `local-path` (disque de l'hôte), RWO uniquement | CSI : EBS, PD, Ceph, NFS… |
| NetworkPolicy | non appliquée par kindnet | Calico/Cilium |
| Haute disponibilité | 1 control plane (configurable à 3) | ≥ 3 control planes |
| Performances | partagées avec la machine hôte | dimensionnées |
| Images | à charger avec `kind load docker-image` si locales | registre accessible par les nœuds |

**`kubeconfig`, contextes, utilisateurs.** Le fichier `~/.kube/config` contient trois listes : `clusters` (URL de l'API + CA), `users` (certificat, jeton ou plugin d'authentification) et `contexts` (association cluster + utilisateur + namespace par défaut). `kubectl config use-context` change le contexte courant ; la variable `KUBECONFIG` peut en fusionner plusieurs. **Vérifiez toujours le contexte avant une commande destructive** : c'est la première cause d'erreur en exploitation (afficher le contexte dans le prompt avec `kube-ps1`).

**Fichier de configuration kind.** Il décrit la topologie : nombre et rôle des nœuds, mappings de ports (`extraPortMappings` pour exposer 80/443 de l'Ingress), labels (`ingress-ready=true`), montages, version de l'image (`kindest/node:vX.Y.Z`). Reproductible et versionnable : le fichier de config *est* l'infrastructure du labo.

**Dépannage de l'installation**
| Symptôme | Cause fréquente | Piste |
|---|---|---|
| `Cannot connect to the Docker daemon` | Docker arrêté / droits | `systemctl start docker`, groupe `docker` |
| Création de cluster très lente ou échec | ressources insuffisantes, téléchargement de l'image | ≥ 4 Go de RAM, relancer, `--retain` puis `kind export logs` |
| `kubectl` pointe vers un autre cluster | mauvais contexte | `kubectl config get-contexts` |
| Ports 80/443 déjà utilisés | autre service local | changer les `hostPort` du fichier kind |
| Erreur de quota `inotify` (Linux) | limites système basses | augmenter `fs.inotify.max_user_watches` / `max_user_instances` |

**Hygiène de laboratoire.** Un cluster jetable se recrée en 2 minutes : n'hésitez pas à `make clean && make cluster` après une expérience qui a mal tourné — c'est le gros avantage d'un environnement éphémère. Prenez l'habitude de travailler dans un **namespace par labo** et de le supprimer ensuite.

## 2. Installation

```bash
./scripts/install-tools.sh
make -C .. cluster          # depuis 00-setup : cd .. && make cluster
kubectl get nodes -o wide
```

Résultat attendu : 3 nœuds `Ready` (`formation-control-plane`, `formation-worker`, `formation-worker2`).

## 3. Confort shell

```bash
source <(kubectl completion bash)        # ou zsh
alias k=kubectl
complete -o default -F __start_kubectl k
export do="--dry-run=client -o yaml"     # k run nginx --image=nginx $do
export now="--force --grace-period 0"
```

Outils recommandés (optionnels) : `kubectx/kubens`, `k9s`, `stern`, `kubectl-neat`.

## 4. 🎬 Démo — Premier contact (10 min)

```bash
kubectl cluster-info
kubectl get nodes --show-labels
kubectl get pods -A                       # les composants système
docker ps --format '{{.Names}}'           # chaque nœud est un conteneur
kubectl config get-contexts               # kubeconfig : cluster, user, context
```

Points à commenter : le kubeconfig (`~/.kube/config`), le contexte courant, les pods de `kube-system` (apiserver, etcd, scheduler, controller-manager, kube-proxy, coredns, CNI).

## 5. 🧪 Labos

### Lab 0.1 ⭐ — Cluster opérationnel
1. Installer les outils et créer le cluster.
2. Lancer `make check` : tous les tests doivent être ✅.
3. Lister les labels du nœud `formation-worker` : quelle valeur a `disk` ?

<details><summary>Corrigé</summary>

```bash
kubectl get node formation-worker --show-labels | tr ',' '\n' | grep disk   # disk=ssd
```
</details>

### Lab 0.2 ⭐ — Trouver les composants du control plane
Identifiez les pods `etcd`, `kube-apiserver`, `kube-scheduler`, `kube-controller-manager`. Sur quel nœud tournent-ils ? Pourquoi ne peut-on pas les supprimer avec `kubectl delete` de façon définitive ?

<details><summary>Corrigé</summary>

```bash
kubectl -n kube-system get pods -o wide | grep -E 'etcd|apiserver|scheduler|controller'
```
Ce sont des **static pods** : définis dans `/etc/kubernetes/manifests` du nœud, gérés par le kubelet. Le pod affiché dans l'API n'est qu'un *mirror pod*.
</details>

### Lab 0.3 ⭐⭐ — Plusieurs contextes
Créez un second cluster `kind create cluster --name autre`, listez les contextes, basculez de l'un à l'autre, puis supprimez `autre`.

<details><summary>Corrigé</summary>

```bash
kind create cluster --name autre
kubectl config get-contexts
kubectl config use-context kind-formation
kind delete cluster --name autre
```
</details>

## 6. Quiz
1. Quel fichier contient les informations d'accès au cluster ? → `~/.kube/config` (variable `KUBECONFIG`)
2. Que représente un nœud kind ? → un conteneur Docker exécutant kubelet + containerd.
3. À quoi sert un *context* ? → associe cluster + utilisateur + namespace par défaut.
