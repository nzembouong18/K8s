# Formation Kubernetes — du débutant au professionnel

Formation pratique, **100 % open source**, orientée *labs*. Chaque module contient : un **cours**, une **démo** (formateur), des **labos** (apprenants) avec **corrigés**, et un **quiz**.

- **Durée** : 5 jours (≈ 35 h) — ou 10 demi-journées en format distanciel
- **Public** : développeurs, admins système, DevOps/SRE, architectes
- **Niveau** : débutant → intermédiaire → avancé (préparation CKAD / CKA incluse)
- **Langue** : français (commandes et YAML en anglais, comme dans l'écosystème)

## Prérequis

| Domaine | Niveau attendu |
|---|---|
| Linux / shell | À l'aise (fichiers, processus, réseau de base) |
| Docker | Savoir lancer un conteneur et écrire un Dockerfile simple |
| YAML | Lecture / écriture |
| Matériel | 8 Go RAM, 4 vCPU, 20 Go disque, Docker installé |

## Parcours

| Jour | Module | Objectifs | Niveau |
|---|---|---|---|
| J1 | [00 — Setup](00-setup/README.md) | Cluster local kind, kubectl, alias | 🟢 |
| J1 | [01 — Fondamentaux](01-fondamentaux/README.md) | Conteneurs, architecture, API, objets | 🟢 |
| J1 | [02 — Pods](02-pods/README.md) | Pods, labels, cycle de vie, init/sidecar | 🟢 |
| J2 | [03 — Workloads](03-workloads/README.md) | Deployment, rolling update, StatefulSet, DaemonSet, Job, CronJob | 🟢🟡 |
| J2 | [04 — Réseau](04-reseau/README.md) | Services, DNS, Ingress, Gateway API, NetworkPolicy | 🟡 |
| J3 | [05 — Config & Stockage](05-config-stockage/README.md) | ConfigMap, Secret, PV/PVC, StorageClass | 🟡 |
| J3 | [06 — Ressources & Scheduling](06-ressources-scheduling/README.md) | Requests/limits, probes, affinités, taints, HPA, quotas, PDB | 🟡 |
| J4 | [07 — Sécurité](07-securite/README.md) | RBAC, ServiceAccount, SecurityContext, Pod Security, secrets | 🟡🔴 |
| J4 | [08 — Helm & Kustomize](08-helm-kustomize/README.md) | Packaging et gestion d'environnements | 🟡 |
| J5 | [09 — Observabilité](09-observabilite/README.md) | metrics-server, Prometheus/Grafana, logs, debug | 🟡🔴 |
| J5 | [10 — Production & GitOps](10-production-gitops/README.md) | Argo CD, upgrades, etcd, kubeadm, HA, FinOps | 🔴 |
| J5 | [11 — Projet final](11-projet-final/README.md) | Déploiement complet d'une application 3-tiers | 🔴 |

Documents transverses : [Guide formateur](docs/formateur.md) · [Aide-mémoire kubectl](docs/cheatsheet.md) · [Troubleshooting](docs/troubleshooting.md) · [Évaluation & certifications](docs/evaluation.md)

## Démarrage rapide

```bash
git clone <ce-depot> && cd K8s
./00-setup/scripts/install-tools.sh      # kubectl, kind, helm (Linux amd64)
make cluster                             # cluster kind 1 control-plane + 2 workers
make check                               # vérifie l'environnement
```

Chaque module se travaille ensuite depuis son dossier :

```bash
cd 03-workloads && cat README.md
kubectl apply -f manifests/<fichier>.yaml
```

Nettoyage d'un module : `kubectl delete ns <namespace-du-module>` — chaque module utilise son propre namespace (`lab-pods`, `lab-workloads`, …).

## Méthode pédagogique

1. **Comprendre** (cours, 20-30 %) — schémas et concepts, peu de slides
2. **Voir** (démo, 20 %) — le formateur exécute, les apprenants suivent
3. **Faire** (labos, 50-60 %) — énoncé + indices + corrigé repliable
4. **Vérifier** (quiz + `make check-<module>`)

Les labos sont gradués : ⭐ guidé · ⭐⭐ semi-guidé · ⭐⭐⭐ autonome (énoncé seul, corrigé en fin de module).

## Versions de référence

Kubernetes **1.31+** (testé conceptuellement jusqu'à 1.33), kind ≥ 0.24, Helm 3.x, ingress-nginx, metrics-server, kube-prometheus-stack, Argo CD 2.x. Les API utilisées sont toutes stables (`v1`, `apps/v1`, `batch/v1`, `networking.k8s.io/v1`, `autoscaling/v2`, `policy/v1`).

## Licence

Contenu libre pour usage pédagogique. Adaptez-le à votre contexte.
