# Module 05 — Configuration et Stockage

⏱ 3 h · 🟡 Intermédiaire

## Objectifs
- Externaliser la configuration (12-factor) : ConfigMap & Secret
- Injecter en variables d'environnement ou en fichiers
- Gérer le stockage persistant : Volume, PV, PVC, StorageClass
- Comprendre `ReadWriteOnce/Many`, `reclaimPolicy`, snapshots

## 1. Cours

### 1.1 ConfigMap et Secret
| | ConfigMap | Secret |
|---|---|---|
| Contenu | Config non sensible | Mots de passe, tokens, certificats |
| Encodage | texte | **base64 (≠ chiffrement !)** |
| Taille max | 1 MiB | 1 MiB |

Consommation :
- `env` / `envFrom` → variables (⚠ **non rechargées** sans redémarrage)
- `volume` → fichiers (mis à jour automatiquement ~1 min, sauf `subPath`)
- `immutable: true` → protège et allège l'API server

Sécurité des Secrets : activer le **chiffrement au repos d'etcd**, limiter via RBAC, préférer un gestionnaire externe (External Secrets Operator + Vault/AWS SM, Sealed Secrets, SOPS) — voir module 07.

### 1.2 Volumes
| Type | Durée de vie | Usage |
|---|---|---|
| `emptyDir` | Pod | Scratch, partage entre conteneurs |
| `hostPath` | Nœud | À éviter (agents système) |
| `configMap` / `secret` / `projected` | Pod | Config |
| `persistentVolumeClaim` | Indépendante | Données durables |

### 1.3 Stockage persistant
```
Pod ──► PVC (demande : taille, mode, classe) ──bind──► PV (volume réel) ◄── StorageClass (provisioning dynamique, CSI)
```
- **Access modes** : `ReadWriteOnce` (RWO, 1 nœud), `ReadOnlyMany`, `ReadWriteMany` (RWX, NFS/CephFS/EFS), `ReadWriteOncePod`
- **reclaimPolicy** : `Delete` (défaut dynamique) · `Retain` (production sensible)
- `volumeBindingMode: WaitForFirstConsumer` : provisionne près du Pod
- `allowVolumeExpansion: true` : agrandir un PVC à chaud
- Sauvegarde : `VolumeSnapshot` (CSI), Velero

Sur kind : StorageClass `standard` (local-path-provisioner), RWO.

### 1.4 Configuration : les principes
Le principe « 12-factor » : **la configuration est séparée du code** et fournie par l'environnement. Une même image doit pouvoir tourner en dev, recette et production avec des ConfigMaps/Secrets différents. Choix du mode de consommation :
| Mode | Avantages | Inconvénients |
|---|---|---|
| Variables d'environnement (`env`, `envFrom`) | simple, universel | figées au démarrage ; visibles via `describe`/`/proc` ; pas pour les gros contenus |
| Volume (fichiers) | mise à jour à chaud (~1 min), fichiers volumineux, certificats | l'application doit recharger (SIGHUP, watcher) |
| Arguments de ligne de commande | explicite | peu pratique pour beaucoup de valeurs |
| API Kubernetes (lecture directe) | dynamique | couple l'application à K8s (RBAC nécessaire) |

### 1.5 Créer ConfigMaps et Secrets
```bash
kubectl create configmap app --from-literal=LOG_LEVEL=info --from-file=nginx.conf --from-env-file=app.env
kubectl create secret generic db --from-literal=password='S3cr3t!' --dry-run=client -o yaml
kubectl create secret tls site --cert=tls.crt --key=tls.key
kubectl create secret docker-registry regcred --docker-server=ghcr.io --docker-username=u --docker-password=$TOKEN
```
Types de Secret : `Opaque` (défaut), `kubernetes.io/tls`, `kubernetes.io/dockerconfigjson`, `kubernetes.io/basic-auth`, `kubernetes.io/ssh-auth`, `kubernetes.io/service-account-token`.
Montage sélectif : `items:` (choisir les clés et les noms de fichier), `defaultMode: 0400` (permissions), `optional: true` (ne pas échouer si absent).
**`subPath`** : monte un seul fichier dans un répertoire existant sans le masquer, mais **désactive la mise à jour automatique** — à connaître avant de s'étonner qu'une config ne se recharge pas.
**Projected volume** : fusionne plusieurs sources (ConfigMap, Secret, token de ServiceAccount, Downward API) dans un même répertoire.

### 1.6 Les Secrets : ce qu'ils protègent vraiment
- **base64 n'est pas du chiffrement** : `echo c2VjcmV0 | base64 -d`.
- Par défaut, les Secrets sont stockés **en clair dans etcd** : activer le chiffrement au repos (`EncryptionConfiguration`, KMS provider) ; toute personne pouvant `get secrets` dans un namespace les lit.
- Un Secret monté en volume est stocké en **tmpfs** (mémoire du nœud), pas sur disque.
- Ne mettez jamais un Secret dans Git en clair. Options : **Sealed Secrets** (chiffrés avec la clé du cluster, versionnables), **SOPS** (+ age/KMS), **External Secrets Operator** (synchronise depuis Vault, AWS Secrets Manager, Azure Key Vault, GCP Secret Manager), **Secrets Store CSI Driver** (montage direct sans Secret Kubernetes).
- Rotation : prévoir le rechargement de l'application ou un redémarrage contrôlé (`rollout restart`, Reloader/Stakater).

### 1.7 Mettre à jour une configuration sans mauvaise surprise
1. **Immutabilité** : `immutable: true` + un **nouveau nom** à chaque version (`app-config-v7`, ou suffixe de hash généré par Kustomize) → le Deployment référence le nouveau nom, ce qui déclenche un rollout propre et permet le **retour arrière** (l'ancien ConfigMap existe toujours).
2. **Rechargement à chaud** : montage en volume + application qui surveille le fichier (ou sidecar qui envoie un signal).
3. **Redémarrage explicite** : `kubectl rollout restart deploy/x`.
Mettre à jour un ConfigMap « en place » sans stratégie est la source classique d'incidents : une partie des Pods voit la nouvelle valeur, l'autre l'ancienne.

### 1.8 Volumes : panorama
| Famille | Exemples | Remarque |
|---|---|---|
| Éphémères | `emptyDir` (disque ou `medium: Memory`), `ephemeral` (volume générique éphémère) | disparaissent avec le Pod ; `sizeLimit` conseillé |
| Informations | `configMap`, `secret`, `downwardAPI`, `projected` | lecture seule |
| Persistants | `persistentVolumeClaim` | cycle de vie indépendant |
| Nœud | `hostPath`, `local` | lient le Pod à un nœud : éviter |
| Réseau (in-tree legacy) | NFS, iSCSI | préférer CSI |
`emptyDir` survit aux **redémarrages de conteneur** mais pas à la suppression du Pod. Un conteneur dont le système de fichiers racine est en lecture seule (durcissement, module 07) a besoin d'`emptyDir` pour `/tmp` et les caches.

### 1.9 Stockage persistant : le modèle complet
```
              ┌─────────────── provisionnement dynamique ───────────────┐
Pod ─► PVC ─(bind)─► PV ─► volume réel (disque cloud, Ceph, NFS…)          │
        ▲              ▲                                                    │
        └ storageClassName ──► StorageClass ──► driver CSI ◄───────────────┘
```
- **PersistentVolume (PV)** : ressource du cluster représentant un volume réel (non namespacé). **PersistentVolumeClaim (PVC)** : demande d'un utilisateur (namespacée). Le *binding* PVC↔PV est 1-1.
- **StorageClass** : définit le *provisioner* (driver CSI), les paramètres (type de disque, IOPS, chiffrement), `reclaimPolicy`, `volumeBindingMode`, `allowVolumeExpansion`.
- **Cycle de vie d'un PV** : `Available` → `Bound` → `Released` (PVC supprimé) → selon la politique : supprimé (`Delete`) ou conservé (`Retain` : doit être nettoyé/réaffecté manuellement).
- **`WaitForFirstConsumer`** : indispensable avec des volumes zonaux (disque cloud limité à une zone) ; le PV est créé dans la zone où le Pod est planifié.
- **Modes d'accès** : `ReadWriteOnce` (un **nœud**), `ReadWriteOncePod` (un seul Pod), `ReadOnlyMany`, `ReadWriteMany` (plusieurs nœuds : NFS, CephFS, EFS, Azure Files). Un volume RWO attaché à un nœud empêche un nouveau Pod de démarrer ailleurs tant qu'il n'est pas détaché (cause de *Multi-Attach error* lors d'une bascule).
- **Mode de volume** : `Filesystem` (défaut) ou `Block` (périphérique brut pour bases de données).

### 1.10 Exploiter le stockage
| Besoin | Outil / pratique |
|---|---|
| Agrandir un volume | éditer `spec.resources.requests.storage` du PVC (si `allowVolumeExpansion`), parfois redémarrage du Pod |
| Réduire un volume | impossible : créer un nouveau volume et migrer |
| Sauvegarde cohérente | `VolumeSnapshot` (CSI) + **Velero** ; quiescer l'application (dump, `fsfreeze`) |
| Restaurer | PVC créé depuis un snapshot (`dataSource`) |
| Cloner | PVC avec `dataSource` = autre PVC |
| Performance | choisir la classe adaptée (SSD, IOPS provisionnés) ; mesurer avec `fio` |
| Données critiques | `Retain`, réplication, sauvegarde hors cluster **testée en restauration** |
| Nettoyage | PVC orphelins après suppression d'un StatefulSet : `kubectl get pvc -A` régulièrement |
**Bases de données** : les opérateurs (CloudNativePG, Percona, Zalando) gèrent réplication, sauvegarde PITR et bascule ; un StatefulSet seul ne suffit pas. Le stockage local (NVMe) offre de meilleures performances mais lie les données au nœud.

### 1.11 Dépannage du stockage
| Symptôme | Cause probable | Piste |
|---|---|---|
| PVC `Pending` | pas de StorageClass par défaut / provisioner absent / `WaitForFirstConsumer` sans Pod | `kubectl describe pvc`, `get sc` |
| Pod `ContainerCreating` bloqué | volume non attachable, Secret/ConfigMap manquant | événements du Pod |
| `Multi-Attach error` | volume RWO encore attaché à un autre nœud | attendre le détachement, vérifier l'ancien Pod |
| `permission denied` à l'écriture | UID du conteneur ≠ propriétaire du volume | `securityContext.fsGroup` |
| Espace plein | volume sous-dimensionné, logs non tournés | `df -h` dans le Pod, expansion |
| PV `Released` non réutilisé | `Retain` : le PV garde un `claimRef` | nettoyer le `claimRef` après avoir sauvegardé |
`fsGroup` : modifie le groupe propriétaire du volume pour les Pods non-root ; `fsGroupChangePolicy: OnRootMismatch` accélère le montage de gros volumes.

## 2. 🎬 Démo (35 min)

```bash
kubectl create ns lab-config && kubectl config set-context --current --namespace=lab-config
kubectl apply -f manifests/01-config.yaml
kubectl logs deploy/app | head                       # env + fichier
# Mise à jour de la ConfigMap : le fichier monté change, pas la variable
kubectl patch cm app-config --type merge -p '{"data":{"app.properties":"mode=prod\n"}}'
kubectl exec deploy/app -- cat /etc/app/app.properties   # ≈ 1 min
kubectl rollout restart deploy/app                       # pour les env vars

kubectl get sc
kubectl apply -f manifests/02-pvc.yaml
kubectl get pvc,pv
kubectl exec pvc-demo -- sh -c 'echo "donnée durable" > /data/f.txt'
kubectl delete pod pvc-demo && kubectl apply -f manifests/02-pvc.yaml
kubectl exec pvc-demo -- cat /data/f.txt                 # toujours là
```

## 3. 🧪 Labos

> Namespace : `lab-config`

### Lab 5.1 ⭐ — ConfigMap en variables
Créez une ConfigMap `app-config` (`APP_MODE=dev`, `LOG_LEVEL=info`) en CLI. Injectez-la avec `envFrom` dans un Pod busybox qui affiche `env | grep APP`.

<details><summary>Corrigé</summary>

```bash
kubectl create cm app-config --from-literal=APP_MODE=dev --from-literal=LOG_LEVEL=info
kubectl run envtest --image=busybox:1.36 --restart=Never --overrides='{"spec":{"containers":[{"name":"envtest","image":"busybox:1.36","command":["env"],"envFrom":[{"configMapRef":{"name":"app-config"}}]}]}}'
kubectl logs envtest | grep -E 'APP|LOG'
```
</details>

### Lab 5.2 ⭐⭐ — ConfigMap en fichier (nginx)
Fournissez une conf nginx custom (réponse `200 "bonjour config"` sur `/`) via ConfigMap montée dans `/etc/nginx/conf.d/default.conf`. Modifiez-la, observez la propagation puis `nginx -s reload`.

<details><summary>Corrigé</summary>
Voir `manifests/03-nginx-config.yaml`.

```bash
kubectl exec deploy/nginx-conf -- nginx -s reload
```
</details>

### Lab 5.3 ⭐⭐ — Secret
Créez un Secret `db-cred` (user/password), injectez le mot de passe dans un Pod en variable **et** monté en fichier (`readOnly`, `defaultMode: 0400`). Décodez-le avec `base64 -d`. Qu'en concluez-vous sur la sécurité ?

<details><summary>Corrigé</summary>

```bash
kubectl create secret generic db-cred --from-literal=user=admin --from-literal=password='S3cr3t!'
kubectl get secret db-cred -o jsonpath='{.data.password}' | base64 -d
```
N'importe qui avec `get secret` peut lire : base64 n'est qu'un encodage → RBAC strict + chiffrement etcd + gestionnaire externe.
</details>

### Lab 5.4 ⭐⭐ — Persistance
Déployez `02-pvc.yaml` : écrivez un fichier, supprimez le Pod, recréez-le et retrouvez le fichier. Où est stocké le volume sur le nœud (`/var/local-path-provisioner` dans le conteneur kind) ?

<details><summary>Corrigé</summary>

```bash
kubectl get pv -o custom-columns=NAME:.metadata.name,PATH:.spec.hostPath.path,NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]
docker exec formation-worker ls /var/local-path-provisioner
```
</details>

### Lab 5.5 ⭐⭐ — PV statique
Créez un PV `hostPath` 200Mi (`storageClassName: manuel`, `Retain`) et un PVC qui s'y lie. Supprimez le PVC : état du PV (`Released`) ? Comment le réutiliser ?

<details><summary>Corrigé</summary>
Voir `manifests/04-pv-static.yaml`. Après suppression du PVC, le PV passe en `Released` (conserve `claimRef`). Pour le réutiliser : `kubectl patch pv pv-manuel -p '{"spec":{"claimRef":null}}'`.
</details>

### Lab 5.6 ⭐⭐⭐ — Expansion et StorageClass
Créez une StorageClass `fast` basée sur `rancher.io/local-path` avec `allowVolumeExpansion: true`, `WaitForFirstConsumer`, `reclaimPolicy: Retain`. Demandez un PVC 100Mi puis tentez de passer à 200Mi. (Note : local-path ne supporte pas toujours l'expansion — lisez l'erreur et expliquez la dépendance au driver CSI.)

<details><summary>Corrigé</summary>

```bash
kubectl patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"200Mi"}}}}'
kubectl describe pvc data       # events : le provisioner doit supporter l'expansion
```
</details>

### Lab 5.7 ⭐⭐⭐ — Application complète
Déployez WordPress + MariaDB : Secret pour les identifiants, PVC pour MariaDB, ConfigMap pour les paramètres, Services, Ingress. Vérifiez la persistance après suppression des Pods.

<details><summary>Corrigé</summary>
Voir module 11 (projet final) pour une architecture complète comparable.
</details>

## 4. Quiz
1. Un Secret est-il chiffré ? → non, seulement base64 ; chiffrement etcd à activer.
2. La modification d'une ConfigMap met-elle à jour les env vars ? → non, redémarrer le Pod.
3. Différence PV / PVC ? → ressource de stockage / demande d'un utilisateur.
4. Que signifie RWO ? → montable en lecture/écriture par un seul nœud.
5. `WaitForFirstConsumer` ? → le volume est créé quand le Pod est planifié (bonne zone/nœud).

Nettoyage : `kubectl delete ns lab-config` (⚠ le PV `Retain` doit être supprimé à la main)
