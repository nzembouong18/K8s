# Module 11 — Projet final : application 3-tiers « Voting App » en production

⏱ 4 h (travail en binôme) · 🔴 Avancé

## Contexte
Déployer l'application de vote (frontend `vote`, `result`, `worker`, `redis`, `postgres`) comme en production, en mobilisant **tous** les acquis de la formation.

```
 Utilisateur ──► Ingress ──► vote (Flask) ──► redis ──► worker ──► postgres ◄── result (Node)
                    └──────────────────────────────────────────────────────────────┘
```

## Cahier des charges

| # | Exigence | Module |
|---|---|---|
| 1 | Namespace `vote` ; labels standard `app.kubernetes.io/*` | 01-02 |
| 2 | `vote` (2+ réplicas), `result` (2), `worker` (1) en **Deployment** ; `postgres` en **StatefulSet** avec PVC 1Gi ; `redis` en Deployment | 03 |
| 3 | Services ClusterIP ; **Ingress** `vote.local` (→ vote) et `result.local` (→ result) | 04 |
| 4 | Identifiants Postgres en **Secret** ; config applicative en **ConfigMap** | 05 |
| 5 | **Requests/limits** partout ; **readiness/liveness** sur vote et result ; **HPA** sur vote (2→6, 60 % CPU) ; **PDB** sur vote | 06 |
| 6 | **NetworkPolicies** default-deny + flux strictement nécessaires | 04-07 |
| 7 | **SecurityContext** : non-root, `allowPrivilegeEscalation: false`, `drop ALL`, seccomp `RuntimeDefault` (là où l'image le permet) ; ServiceAccount dédié sans token monté ; namespace PSA `baseline` enforce + `restricted` warn | 07 |
| 8 | Packaging **Kustomize** (base + overlays `dev`/`prod`) *ou* chart **Helm** | 08 |
| 9 | **ServiceMonitor** + une alerte (ex. aucun `vote` disponible) ; dashboard Grafana | 09 |
| 10 | Déploiement **GitOps** par Argo CD (Application avec selfHeal) | 10 |
| 11 | Document `RUNBOOK.md` : déploiement, rollback, diagnostic des 3 pannes les plus probables, restauration Postgres | 09-10 |

## Démarrage

Une base fonctionnelle (sans durcissement) est fournie : `manifests/00-voting-app-base.yaml`.

```bash
kubectl create ns vote
kubectl apply -f manifests/00-voting-app-base.yaml
kubectl -n vote get pods -w
kubectl -n vote port-forward svc/vote 8080:80      # http://localhost:8080
kubectl -n vote port-forward svc/result 8081:80    # http://localhost:8081
```
Votre travail : **faire passer cette base au niveau production** selon le cahier des charges.

## Jalons proposés

| Temps | Jalon | Livrable |
|---|---|---|
| 0 h 30 | Base déployée et fonctionnelle | Votes visibles dans `result` |
| 1 h 30 | Ressources, probes, HPA, PDB, Secret/ConfigMap | Manifests mis à jour |
| 2 h 15 | Sécurité (SecurityContext, RBAC/SA, NetworkPolicy, PSA) | Application toujours fonctionnelle |
| 3 h 00 | Kustomize/Helm + Ingress + monitoring | Overlays `dev`/`prod` |
| 3 h 30 | GitOps + chaos test | Application Argo CD, test de panne |
| 4 h 00 | Soutenance 10 min | Démo + RUNBOOK |

## Tests de validation (recette)

```bash
# 1. Fonctionnel
kubectl -n vote get pods                                   # tous Ready
# 2. Résilience : suppression d'un Pod vote pendant une boucle de requêtes -> 0 erreur
kubectl -n vote delete pod -l app=vote --wait=false
# 3. Scalabilité : charge -> HPA monte
kubectl -n vote get hpa -w
# 4. Persistance : suppression du Pod postgres -> les votes sont conservés
kubectl -n vote delete pod postgres-0
# 5. Sécurité
kubectl -n vote auth can-i --list --as=system:serviceaccount:vote:vote       # minimal
kubectl -n vote get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.securityContext.runAsNonRoot}{"\n"}{end}'
# 6. Isolation réseau : vote ne doit PAS joindre postgres
kubectl -n vote exec deploy/vote -- python -c "import socket; socket.create_connection(('db',5432),3)"   # doit échouer
# 7. Rollback
kubectl -n vote rollout undo deploy/vote
# 8. Drain d'un nœud sans interruption
kubectl drain formation-worker --ignore-daemonsets --delete-emptydir-data
```
⚠ Le test 6 requiert un CNI appliquant les NetworkPolicies (Calico/Cilium).

## Grille d'évaluation (100 points)

| Critère | Points |
|---|---|
| Application fonctionnelle de bout en bout | 15 |
| Workloads corrects (types d'objets, réplicas, stratégie) | 10 |
| Config & stockage (Secret, ConfigMap, PVC, persistance prouvée) | 10 |
| Fiabilité (requests/limits, probes, HPA, PDB) | 15 |
| Sécurité (SecurityContext, RBAC, NetworkPolicy, PSA) | 20 |
| Packaging & GitOps | 10 |
| Observabilité (monitoring + alerte) | 10 |
| RUNBOOK & soutenance | 10 |

## Pistes de correction (formateur)
- `vote` et `result` supportent mal `readOnlyRootFilesystem` : monter un `emptyDir` sur `/tmp` ou accepter l'exception documentée.
- Les images d'exemple tournent en root pour certains composants : `baseline` est atteignable partout, `restricted` demande des images adaptées (ex. rebuild non-root). Valoriser les justifications documentées.
- Les images `worker` et `result` se connectent au hostname codé en dur **`db`** (Service `db` dans la base) et `redis` ; les NetworkPolicies doivent cibler `app: postgres`.
- Postgres : `PGDATA` sous `/var/lib/postgresql/data/pgdata` (sous-dossier) pour éviter l'erreur `lost+found` sur certains volumes.
- NetworkPolicy : ne pas oublier **DNS** en egress pour tous les Pods, et l'accès de l'Ingress controller (namespaceSelector `ingress-nginx`) vers `vote`/`result`.
