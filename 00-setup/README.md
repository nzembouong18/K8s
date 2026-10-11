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
