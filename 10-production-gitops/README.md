# Module 10 — Production, GitOps et Opérations

⏱ 4 h · 🔴 Avancé

## Objectifs
- Adopter **GitOps** avec Argo CD (déploiement continu déclaratif)
- Construire un pipeline CI/CD sûr (build → scan → push → mise à jour du dépôt GitOps)
- Opérer un cluster : **kubeadm**, haute disponibilité, **upgrade**, **sauvegarde etcd**, **drain/cordon**
- Maîtriser les extensions : CRD, Operators ; notions de service mesh, FinOps, multi-tenancy

## 1. Cours

### 1.1 GitOps
Principes : (1) l'état désiré est **déclaratif**, (2) **versionné** dans Git, (3) **tiré** automatiquement par un agent, (4) **réconcilié** en continu (détection de dérive, *self-heal*).
```
Dev ─push→ Git (code) ─CI→ build+test+scan → image registry
                              └─ commit tag image → Git (config/GitOps repo)
Argo CD / Flux ◄─ pull ── Git (config)  ──apply──► Cluster(s)
```
Avantages : audit (git log), rollback = `git revert`, aucun secret cluster dans la CI, reproductibilité. Argo CD : `Application`, `AppProject`, `ApplicationSet` (multi-cluster / multi-env), sync policies (`automated`, `prune`, `selfHeal`). Secrets : Sealed Secrets / SOPS / External Secrets.

Livraison progressive : **Argo Rollouts** / **Flagger** (canary, blue-green, analyse automatique de métriques).

### 1.2 Cluster en production
| Sujet | Bonnes pratiques |
|---|---|
| **HA control plane** | ≥ 3 nœuds control plane (quorum etcd), load-balancer devant l'API |
| **etcd** | Disques SSD rapides, snapshots réguliers **testés en restauration** |
| **Workers** | Pools séparés (système / apps / GPU), autoscaling (Karpenter / Cluster Autoscaler) |
| **Upgrades** | Une version mineure à la fois, control plane puis workers, `drain`, PDB, canary de nœuds |
| **Multi-zone** | topologySpread, PV zonaux, `WaitForFirstConsumer` |
| **Sécurité** | RBAC strict, PSA restricted, NetworkPolicies, audit logs, rotation certificats |
| **Réseau** | CNI avec policies (Cilium/Calico), Ingress/Gateway redondant, DNS dimensionné |
| **Coûts (FinOps)** | Requests réalistes, Spot, extinction hors heures, Kubecost/OpenCost |
| **Multi-tenancy** | Namespaces + quotas + RBAC + NetworkPolicy ; vcluster / clusters dédiés si forte isolation |

### 1.3 Installation et cycle de vie avec kubeadm
```bash
# Sur chaque nœud : containerd, kubeadm, kubelet, kubectl, swap off, modules br_netfilter/overlay, sysctl ip_forward
kubeadm init --control-plane-endpoint "k8s-api.example.com:6443" --upload-certs --pod-network-cidr=10.244.0.0/16
kubeadm join ... --control-plane --certificate-key ...      # autres CP
kubeadm join ...                                            # workers
# CNI : kubectl apply -f <cilium|calico>
```
Upgrade : `kubeadm upgrade plan` → `kubeadm upgrade apply v1.X.Y` (1er CP) → `kubeadm upgrade node` (autres CP) → pour chaque worker : `drain` → maj paquets kubelet → `systemctl restart kubelet` → `uncordon`.

Sauvegarde etcd :
```bash
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%F).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
etcdutl snapshot restore /backup/etcd.db --data-dir /var/lib/etcd-restore   # puis pointer le static pod vers ce dir
```
Applications : **Velero** (objets + volumes), snapshots CSI.

### 1.4 Extensibilité
**CRD** = nouveau type d'objet ; **Operator** = CRD + contrôleur qui encode l'expertise d'exploitation (ex. CloudNativePG, Strimzi, cert-manager, Prometheus Operator). Points d'extension : CRI, CNI, CSI, admission webhooks, schedulers custom.

## 2. 🎬 Démo (60 min)

### Démo A — Argo CD
```bash
kubectl create ns argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo
kubectl -n argocd port-forward svc/argocd-server 8443:443        # https://localhost:8443  (admin)
```
Créez une `Application` pointant vers votre dépôt (remplacer `REPO_URL`) :
```bash
sed 's#REPO_URL#https://github.com/<vous>/<depot-gitops>.git#' manifests/01-argocd-app.yaml | kubectl apply -f -
```
Démonstration : modifier `replicas` dans Git → sync automatique ; `kubectl scale` manuel → *self-heal* annule la dérive ; `git revert` → rollback.

### Démo B — Sauvegarde / restauration etcd (sur nœud kind)
```bash
docker exec -it formation-control-plane bash
apt-get update -qq && apt-get install -y -qq etcd-client >/dev/null
ETCDCTL_API=3 etcdctl snapshot save /tmp/snap.db \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key
ETCDCTL_API=3 etcdctl snapshot status /tmp/snap.db -w table
```

### Démo C — Maintenance d'un nœud
```bash
kubectl cordon formation-worker2
kubectl drain formation-worker2 --ignore-daemonsets --delete-emptydir-data
kubectl get pods -A -o wide | grep worker2
kubectl uncordon formation-worker2
```

## 3. 🧪 Labos

### Lab 10.1 ⭐⭐ — Premier déploiement GitOps
1. Créez un dépôt Git avec un dossier `apps/guestbook/` contenant un Deployment + Service (utilisez `manifests/02-gitops-repo-example/`).
2. Installez Argo CD, créez l'`Application` (sync auto, prune, selfHeal).
3. Changez l'image dans Git ; observez la synchronisation. Faites un `kubectl edit` manuel : que se passe-t-il ?

<details><summary>Corrigé</summary>
Argo CD détecte la dérive (`OutOfSync`) et, avec `selfHeal: true`, restaure l'état Git en quelques secondes. Le seul moyen durable de modifier = commit Git.
</details>

### Lab 10.2 ⭐⭐ — ApplicationSet multi-environnements
Générez une Application par environnement (`dev`, `prod`) à partir des overlays Kustomize du module 08.

<details><summary>Corrigé</summary>
Voir `manifests/03-applicationset.yaml` (générateur `list`, chemin `overlays/{{env}}`).
</details>

### Lab 10.3 ⭐⭐ — Pipeline CI (GitHub Actions)
Écrivez un workflow qui : build l'image → scan Trivy (échec si CRITICAL) → push → ouvre une PR sur le dépôt GitOps avec le nouveau tag.

<details><summary>Corrigé</summary>
Voir `ci/github-actions.yaml` (modèle à copier dans `.github/workflows/ci.yaml`).
</details>

### Lab 10.4 ⭐⭐⭐ — Sauvegarde et restauration etcd
Sauvegardez etcd, supprimez un namespace de test, puis expliquez la procédure de restauration (arrêt des static pods, restore vers un nouveau `data-dir`, modification du manifest etcd). Pourquoi une restauration etcd revient-elle à **remonter dans le temps** pour tout le cluster ?

<details><summary>Corrigé</summary>
La restauration remplace tout l'état (objets, secrets, RBAC). Les ressources créées après le snapshot disparaissent ; les Pods réels sur les nœuds sont réconciliés ensuite. Pour des restaurations **fines** (un namespace, des PV) utilisez **Velero**.
</details>

### Lab 10.5 ⭐⭐⭐ — Upgrade rolling d'un nœud (simulation)
Sans mettre à jour réellement kind : décrivez et rejouez les étapes `cordon → drain → (upgrade kubelet) → uncordon` sur un worker avec l'application `web` du module 04 (3 réplicas ; ajoutez-lui un PDB `minAvailable: 2`). Montrez zéro indisponibilité (boucle `curl` sur le Service pendant le drain).

<details><summary>Corrigé</summary>

```bash
kubectl run probe --image=curlimages/curl --restart=Never -- sh -c 'while true; do curl -s -o /dev/null -w "%{http_code}\n" http://web.lab-reseau; sleep 0.5; done'
kubectl drain formation-worker --ignore-daemonsets --delete-emptydir-data
kubectl logs probe | sort | uniq -c       # que des 200
kubectl uncordon formation-worker
```
</details>

### Lab 10.6 ⭐⭐⭐ — Opérateur : une base PostgreSQL HA
Installez **CloudNativePG**, créez un `Cluster` de 3 instances, tuez le primaire et observez la bascule automatique.

<details><summary>Corrigé</summary>

```bash
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.0.yaml
kubectl apply -f manifests/05-cnpg-cluster.yaml
kubectl get cluster,pods -w
kubectl delete pod pg-1       # si pg-1 est le primaire → promotion d'un réplica
```
</details>

### Lab 10.7 ⭐⭐⭐ — Canary avec Argo Rollouts (optionnel)
Installez Argo Rollouts, déployez un `Rollout` avec étapes 20 % → pause → 60 % → 100 % et promouvez manuellement.

<details><summary>Corrigé</summary>
`kubectl argo rollouts get rollout app --watch` et `promote`. En production, ajoutez une `AnalysisTemplate` basée sur Prometheus (taux d'erreur) pour un rollback automatique.
</details>

### Lab 10.8 ⭐⭐⭐ — Revue de readiness production
Évaluez un cluster avec la checklist ci-dessous. Notez chaque point 0/1 et proposez un plan d'action priorisé.

- [ ] Control plane HA (≥ 3) · [ ] backups etcd testés · [ ] upgrades planifiés
- [ ] Requests/limits sur 100 % des workloads · [ ] probes · [ ] PDB · [ ] HPA/VPA
- [ ] RBAC moindre privilège · [ ] PSA restricted · [ ] NetworkPolicies default-deny
- [ ] Secrets chiffrés + gestionnaire externe · [ ] images scannées/signées
- [ ] Métriques + alertes + logs centralisés · [ ] runbooks
- [ ] GitOps (zéro `kubectl apply` manuel) · [ ] quotas par namespace · [ ] suivi des coûts

## 4. Quiz
1. Pull vs push en CD ? → GitOps = l'agent *dans* le cluster tire depuis Git ; pas d'identifiants cluster en CI.
2. Combien de membres etcd pour tolérer 1 panne ? → 3 (quorum 2). Pour 2 pannes ? → 5.
3. Ordre d'un upgrade kubeadm ? → CP d'abord (`upgrade apply` puis `upgrade node`), puis workers ; une mineure à la fois.
4. Qu'est-ce qu'un Operator ? → CRD + contrôleur automatisant l'exploitation d'une application.
5. `selfHeal` dans Argo CD ? → annule les modifications manuelles hors Git.

Nettoyage : `kubectl delete ns argocd cnpg-system ; kubectl delete cluster.postgresql.cnpg.io pg`
