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
