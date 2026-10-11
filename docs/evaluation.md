# Évaluation et certifications

## 1. Modalités

| Moment | Outil | Barème |
|---|---|---|
| Fin de chaque module | Quiz (5 questions, en fin de README) + labos validés | formatif |
| Fin J3 | **QCM intermédiaire** (§2) | 20 pts |
| Fin J5 | **Projet final** (module 11) + soutenance | 100 pts |
| Optionnel | **Examen pratique chronométré** (§4) | 100 pts |

Attestation de réussite : ≥ 70 % au projet **et** ≥ 70 % au QCM.

## 2. QCM (20 questions, 1 point chacune) — réponses en §3

1. Quel composant est la seule porte d'entrée de l'API ? a) etcd b) kube-apiserver c) kubelet d) scheduler
2. Un Pod supprimé créé par un Deployment… a) disparaît b) est recréé par le ReplicaSet c) est recréé par le kubelet d) reste Terminating
3. Quel objet pour une base avec identité stable et stockage par réplica ? a) Deployment b) DaemonSet c) StatefulSet d) Job
4. `maxUnavailable: 0` signifie… a) aucune mise à jour b) jamais de Pod indisponible pendant le rollout c) 0 réplica d) rollback auto
5. Type de Service par défaut ? a) NodePort b) LoadBalancer c) ClusterIP d) ExternalName
6. Un Service n'a aucun Endpoint. Cause la plus probable ? a) CNI b) selector ne correspond à aucun Pod Ready c) DNS d) Ingress
7. Un Ingress nécessite… a) un Ingress Controller b) un LoadBalancer cloud c) un Service NodePort d) un DaemonSet
8. Une NetworkPolicy est ignorée si… a) pas de namespace b) le CNI ne la supporte pas c) pas de label d) Pod privilégié
9. Un Secret est… a) chiffré par défaut b) encodé en base64 c) hashé d) inaccessible aux admins
10. Une modification de ConfigMap monté en volume est répercutée… a) immédiatement dans les env b) après un délai, dans les fichiers (hors subPath) c) jamais d) seulement après `kubectl delete`
11. `ReadWriteOnce` signifie… a) un seul Pod b) un seul nœud c) un seul namespace d) lecture seule
12. Dépassement de la limite mémoire → a) throttling b) OOMKilled c) Pending d) évincé par le scheduler
13. La readiness probe en échec → a) redémarre le conteneur b) retire le Pod des Endpoints c) supprime le Pod d) rien
14. Pour attirer un Pod sur un nœud taint, il faut… a) toleration seule b) nodeSelector seul c) toleration + nodeSelector/affinity d) priorityClass
15. Le HPA nécessite… a) VPA b) metrics-server et des requests c) Prometheus d) un Ingress
16. RBAC est… a) additif (allow-only) b) avec règles deny c) uniquement par namespace d) optionnel et désactivé
17. Niveau Pod Security le plus strict ? a) baseline b) restricted c) privileged d) hardened
18. Quel outil pour déployer plusieurs variantes d'environnement sans templates ? a) Helm b) Kustomize c) Terraform d) Ansible
19. Principe GitOps clé ? a) push depuis la CI vers le cluster b) Git = source de vérité, agent qui tire et réconcilie c) pas de Git d) kubectl edit en prod
20. Combien de membres etcd pour tolérer 2 pannes ? a) 3 b) 4 c) 5 d) 2

## 3. Corrigé
1b · 2b · 3c · 4b · 5c · 6b · 7a · 8b · 9b · 10b · 11b · 12b · 13b · 14c · 15b · 16a · 17b · 18b · 19b · 20c

## 4. Examen pratique (2 h, 12 tâches, 100 pts) — exemples

Format type CKAD/CKA : cluster fourni, doc officielle autorisée (kubernetes.io), alias `k` autorisé.

| # | Tâche | Pts |
|---|---|---|
| 1 | Créer un Pod `p1` (nginx:1.27) avec label `tier=front` et variable `ENV=prod` dans `exam` | 5 |
| 2 | Créer un Deployment 3 réplicas, le mettre à jour, puis revenir à la révision précédente | 8 |
| 3 | Exposer le Deployment en ClusterIP et vérifier par `curl` depuis un Pod | 6 |
| 4 | Créer un Ingress `app.exam` → service `app:80` | 8 |
| 5 | ConfigMap + Secret montés (fichier + variable) dans un Pod | 8 |
| 6 | PVC 200Mi monté dans un Pod, prouver la persistance | 8 |
| 7 | Dépanner un Deployment qui ne démarre pas (3 défauts cachés) | 12 |
| 8 | Ajouter requests/limits + readiness/liveness | 8 |
| 9 | Créer SA + Role + RoleBinding (lecture pods) et le prouver avec `auth can-i` | 10 |
| 10 | NetworkPolicy : n'autoriser que `frontend` → `backend:8080` | 10 |
| 11 | CronJob toutes les 5 min avec `concurrencyPolicy: Forbid` | 7 |
| 12 | Drain d'un nœud puis uncordon, sans perte de service (PDB) | 10 |

Tâches « admin » (type CKA, niveau avancé) : sauvegarde/restauration etcd, upgrade kubeadm, réparation d'un nœud `NotReady` (kubelet arrêté), ajout d'un worker (`kubeadm token create --print-join-command`), configuration d'un StorageClass par défaut, troubleshooting DNS.

## 5. Préparation aux certifications

| Certification | Public | Domaines | Conseils |
|---|---|---|---|
| **CKAD** (Application Developer) | Développeurs | Pods, workloads, config, réseau, observabilité, sécurité applicative | Modules 02-08. Savoir générer du YAML vite (`$do`), `kubectl explain` |
| **CKA** (Administrator) | Admins / SRE | Installation, stockage, réseau, troubleshooting, RBAC, etcd, upgrades | Modules 01-10 ; pratiquer kubeadm sur VM |
| **CKS** (Security Specialist) | Sécurité | Durcissement, supply chain, runtime | Module 07 approfondi (+ Falco, Trivy, AppArmor/seccomp) |

Format : examen **pratique** en ligne (2 h), ~15-20 tâches, doc officielle autorisée. Vérifier le programme et les versions sur le site de la CNCF / Linux Foundation avant de s'inscrire.

Plan d'entraînement (4 semaines) : S1 objets de base à vitesse (Pods/Deployments/Services en < 2 min) · S2 config, stockage, réseau · S3 sécurité, scheduling, troubleshooting · S4 examens blancs chronométrés (killer.sh) + refaire les labos ⭐⭐⭐.

## 6. Pour aller plus loin
- Service mesh (Istio / Linkerd), eBPF (Cilium, Hubble), Gateway API avancée
- Multi-cluster et plateformes internes (Backstage, Crossplane, Cluster API)
- Policy-as-code (Kyverno, OPA Gatekeeper), runtime security (Falco, Tetragon)
- FinOps (OpenCost), Karpenter, KEDA, VPA
- Opérateurs avec Kubebuilder / Operator SDK
