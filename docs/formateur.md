# Guide du formateur

**Formateur** : NZEMBOUONG Patrick — Ingénieur DevOps & Intégrateur – Kubernetes

## 1. Planning type — 5 jours (7 h/jour)

| Jour | Matin (9h-12h30) | Après-midi (13h30-17h) |
|---|---|---|
| **J1** | Accueil, tour de table, **00 Setup** (45 min), **01 Fondamentaux** (cours + démo) | 01 labos, **02 Pods** (cours, démo, labos 2.1-2.4) |
| **J2** | 02 fin (2.5-2.6) + **03 Workloads** (cours, démo, labos 3.1-3.4) | 03 fin (3.5-3.8), **04 Réseau** (cours, démo, labos 4.1-4.3) |
| **J3** | 04 fin (Ingress, NetPol), **05 Config & Stockage** | **06 Ressources & Scheduling** (6.1-6.5) |
| **J4** | 06 fin (HPA, quota, PDB), **07 Sécurité** (cours + RBAC) | 07 fin (PSA, admission), **08 Helm & Kustomize** |
| **J5** | **09 Observabilité** (démo Prometheus, 9.3 pannes) | **10 Prod & GitOps** (démos A-C) + **11 Projet** (version courte 2 h) |

Variantes :
- **Express 2 jours (CKAD-lite)** : 00, 01, 02, 03, 04 (4.1-4.4), 05 (5.1-5.4), 06 (6.1-6.3), 08 (Helm de base).
- **Admin / SRE 3 jours** : 01, 04 (NetPol), 06, 07, 09, 10 + projet.
- **Distanciel** : 10 demi-journées de 3 h 30 ; démos en live-coding, labos en salles de travail (binômes).

## 2. Répartition conseillée
Cours 25 % · Démo 20 % · Labos 50 % · Quiz/rétro 5 %. Ne jamais dépasser 20 min de cours sans manipulation.

## 3. Préparation (J-7 → J-1)
- [ ] Vérifier que chaque poste lance `make cluster` et `make check` (8 Go RAM, Docker)
- [ ] **Pré-télécharger les images** (réseau de salle souvent saturé) : `docker pull` de `nginx:1.26`, `nginx:1.27`, `busybox:1.36`, `curlimages/curl`, `traefik/whoami:v1.10`, `polinux/stress`, `registry.k8s.io/hpa-example`, `perl:5.40`, `dockersamples/examplevotingapp_*`, puis `kind load docker-image` si besoin
- [ ] Miroir local de registre si possible ; vérifier proxy / pare-feu (GitHub, charts Bitnami, quay.io, registry.k8s.io)
- [ ] Préparer un cluster « formateur » de secours et un dépôt Git GitOps pré-créé pour le module 10
- [ ] Tester toutes les démos sur la version Kubernetes retenue (voir §6)
- [ ] Imprimer l'[aide-mémoire](cheatsheet.md)

## 4. Conseils d'animation
- **Faire prédire avant d'exécuter** : « que va-t-il se passer si je supprime ce Pod ? »
- **Casser volontairement** (modules 02, 06, 09) : le dépannage est la compétence n°1 en production.
- Imposer le **YAML écrit à la main** au moins une fois par objet, puis autoriser `--dry-run=client -o yaml`.
- Montrer systématiquement `describe` → section **Events**.
- Le **binôme** accélère l'entraide ; alterner pilote / copilote toutes les 30 min.
- Fil rouge : l'application `web` évolue de module en module (Pod → Deployment → Service → Ingress → ConfigMap → probes → HPA → sécurité).
- Niveaux hétérogènes : les labos ⭐⭐⭐ servent de défis aux rapides ; ne jamais les rendre obligatoires.

## 5. Pièges fréquents (et réponses)
| Piège | Remède |
|---|---|
| Ports 80/443 déjà utilisés sur le poste | Modifier `extraPortMappings` dans `kind-cluster.yaml` (ex. 8080/8443) |
| `ImagePullBackOff` en salle | Pré-pull + `kind load docker-image` |
| NetworkPolicies sans effet (kindnet) | Cluster kind avec `disableDefaultCNI: true` + Calico, ou démonstration formateur sur cluster dédié |
| `kubectl top` → `metrics not available` | `make metrics` (flag `--kubelet-insecure-tls` pour kind) |
| HPA `<unknown>` | Requests CPU manquantes ou metrics-server non prêt (attendre 1-2 min) |
| Quota qui bloque d'autres labs | Namespace dédié `lab-quota` |
| Ressources insuffisantes (prometheus) | Désactiver Alertmanager/Grafana si < 8 Go, ou cluster formateur partagé |
| Port-forward qui se coupe | Relancer ; utiliser Ingress pour les démos longues |

Cluster kind avec Calico (pour le Lab 4.7) :
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: 192.168.0.0/16
nodes: [{role: control-plane}, {role: worker}, {role: worker}]
```
puis `kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/calico.yaml`.

## 6. Versions et maintenance du contenu
Revoir à chaque nouvelle mineure Kubernetes (3 releases/an) : API dépréciées (`kubectl convert`, `kubent`), versions des charts/outils, liens d'installation (Argo CD, CNPG, ingress-nginx — noter que le projet ingress-nginx est en fin de vie annoncée : privilégier **Gateway API** dans les évolutions du module 04).

## 7. Évaluation
Voir [evaluation.md](evaluation.md) : quiz par module, QCM final, grille du projet, préparation CKAD/CKA.
