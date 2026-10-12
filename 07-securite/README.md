# Module 07 — Sécurité

⏱ 3 h 30 · 🟡🔴 Intermédiaire → Avancé

## Objectifs
- Comprendre la chaîne **authentification → autorisation → admission**
- Écrire des Roles / ClusterRoles / Bindings (RBAC) au moindre privilège
- Utiliser les ServiceAccounts, durcir les Pods (SecurityContext, Pod Security Standards)
- Appliquer des garde-fous (NetworkPolicy, admission, scan d'images, gestion des secrets)

## 1. Cours

### 1.1 Les 4C de la sécurité cloud-native
**Cloud → Cluster → Container → Code.** Chaque couche protège la suivante.

### 1.2 Accès à l'API
1. **AuthN** : certificats clients, tokens (ServiceAccount), OIDC (SSO)… *Kubernetes n'a pas d'objet « User »*.
2. **AuthZ** : **RBAC** (défaut), Node, Webhook.
3. **Admission** : mutating + validating (Pod Security Admission, ValidatingAdmissionPolicy, Kyverno / OPA Gatekeeper).

### 1.3 RBAC
- `Role` / `ClusterRole` : **verbes** (`get, list, watch, create, update, patch, delete`) sur des **ressources**. Purement additif (pas de « deny »).
- `RoleBinding` / `ClusterRoleBinding` : lie un *subject* (User, Group, ServiceAccount) à un rôle.
- Test : `kubectl auth can-i list pods --as=system:serviceaccount:ns:sa -n ns`.
- Pièges : `cluster-admin` partout, wildcard `*`, droit `create pods` (= escalade), `get secrets`.

### 1.4 ServiceAccounts
Identité des Pods vis-à-vis de l'API. Depuis 1.24 : tokens **liés, temporaires** (projected volume). Bonnes pratiques : un SA par application, `automountServiceAccountToken: false` si inutile, pas de droits sur le SA `default`.

### 1.5 Durcissement des Pods
```yaml
securityContext:               # niveau Pod
  runAsNonRoot: true
  runAsUser: 10001
  seccompProfile: {type: RuntimeDefault}
containers:
  - securityContext:           # niveau conteneur
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: {drop: [ALL]}
```
**Pod Security Standards** (via Pod Security Admission, labels de namespace) : `privileged` · `baseline` · `restricted`, modes `enforce` / `audit` / `warn`.

### 1.6 Supply chain & secrets
- Images : registre de confiance, tags immuables / digests (`@sha256:`), scan (Trivy), signature (cosign), SBOM
- Secrets : chiffrement etcd, External Secrets / Vault / Sealed Secrets / SOPS
- Cluster : audit logs, mises à jour régulières, CIS Benchmark (kube-bench), Falco (runtime)

### 1.7 Modèle de menace : où un attaquant entre-t-il ?
| Vecteur | Exemple | Mesures |
|---|---|---|
| Application vulnérable | RCE dans une dépendance | scan d'images, mises à jour, WAF, durcissement du conteneur |
| Image malveillante | image publique piégée | registre de confiance, digests, signature, admission policy |
| Pod compromis → API | token de ServiceAccount volé | `automountServiceAccountToken: false`, RBAC minimal |
| Pod compromis → autres Pods | mouvement latéral | NetworkPolicy, mTLS |
| Pod compromis → nœud | conteneur privilégié, `hostPath`, `hostPID` | Pod Security `restricted`, seccomp, AppArmor |
| Credentials d'admin volés | kubeconfig `cluster-admin` | SSO/OIDC, accès temporaires, audit |
| Composant exposé | API server ou kubelet ouverts sur Internet | réseau privé, `--anonymous-auth=false`, pare-feu |
| Chaîne CI/CD | pipeline compromis | secrets éphémères, signature, GitOps en tirage (*pull*) |
| Secrets exposés | `get secrets` trop large, etcd non chiffré | chiffrement, External Secrets, RBAC |

### 1.8 RBAC en pratique
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: pod-reader, namespace: app}
rules:
  - apiGroups: [""]            # "" = groupe core
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
---
kind: RoleBinding
metadata: {name: lire-pods, namespace: app}
subjects:
  - {kind: ServiceAccount, name: ci, namespace: app}
  - {kind: Group, name: dev-team, apiGroup: rbac.authorization.k8s.io}
roleRef: {kind: Role, name: pod-reader, apiGroup: rbac.authorization.k8s.io}
```
- **Portée** : `Role` + `RoleBinding` = un namespace ; `ClusterRole` + `RoleBinding` = rôle réutilisable *limité* à un namespace ; `ClusterRole` + `ClusterRoleBinding` = tout le cluster. Les ressources non namespacées (nœuds, PV) exigent un ClusterRole.
- **Rôles prédéfinis** : `view`, `edit`, `admin` (par namespace), `cluster-admin`. `ClusterRole` **agrégés** (`aggregationRule`) : les CRD ajoutent leurs droits à `view/edit/admin`.
- **Droits dangereux** (équivalents à des privilèges élevés) : `create pods` (monter un hostPath, exécuter un Pod privilégié), `get/list secrets`, `create pods/exec`, `impersonate`, `escalate`/`bind` sur les rôles, `patch nodes`, `create tokens` pour des ServiceAccounts, wildcard `*`.
- **Revue** : `kubectl auth can-i --list --as=…`, `kubectl who-can` (plugin), `rakkess`, `rbac-tool`, Kubescape, `kubectl get clusterrolebindings -o json | jq` pour repérer les liaisons à `cluster-admin`.
- **Humains** : pas d'objet User ; les identités viennent de l'IdP via **OIDC** (groupes dans le jeton) ; les certificats clients de longue durée sont à éviter hors usage d'urgence.

### 1.9 Admission : faire respecter les règles
| Mécanisme | Nature | Quand l'utiliser |
|---|---|---|
| **Pod Security Admission** (intégré) | 3 profils prédéfinis par namespace | socle de sécurité des Pods |
| **ValidatingAdmissionPolicy** (CEL, intégré, GA 1.30) | règles en expression CEL, sans webhook | politiques simples et rapides |
| **Kyverno** | politiques en YAML : valider, **muter**, **générer**, vérifier les signatures | équipes qui préfèrent le YAML |
| **OPA Gatekeeper** | Rego | si OPA est déjà un standard (module Terraform 16 en commun) |
Exemples de règles : interdire `latest`, imposer des `requests/limits`, des labels de propriétaire, un registre autorisé, `runAsNonRoot`, interdire `hostNetwork`. Déployer d'abord en mode **audit/warn**, puis `enforce`.

### 1.10 Pod Security Standards en détail
| Profil | Objectif | Interdit notamment |
|---|---|---|
| `privileged` | aucune restriction | — (réservé aux composants système) |
| `baseline` | empêcher les escalades connues | `privileged`, `hostNetwork/PID/IPC`, `hostPath`, capabilities dangereuses, ports hôte |
| `restricted` | bonnes pratiques de durcissement | root, escalade de privilèges, capabilities autres que `NET_BIND_SERVICE`, seccomp non défini, volumes hors liste |
```bash
kubectl label ns app pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted
```
`PodSecurityPolicy` a été **supprimé en 1.25**. Pour un Pod `restricted` : `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault`, `capabilities.drop: [ALL]`.

### 1.11 Isolation du noyau : seccomp, AppArmor, runtimes
- **seccomp** filtre les appels système ; le profil `RuntimeDefault` bloque plusieurs dizaines d'appels dangereux et doit être activé partout.
- **AppArmor / SELinux** : contrôle d'accès obligatoire par processus.
- **Capabilities Linux** : fractions des pouvoirs de root ; on retire tout (`drop: ALL`) et on ajoute au strict nécessaire.
- **User namespaces** : root dans le conteneur ≠ root sur l'hôte (fonction récente, à activer selon la version).
- **Runtimes isolés** (gVisor, Kata Containers) via `RuntimeClass` : isolation renforcée pour du code non fiable (multi-tenant).

### 1.12 Sécuriser la chaîne d'approvisionnement
1. **Construire** : images minimales (distroless, Alpine), multi-stage, utilisateur non-root, pas de secrets dans les couches.
2. **Scanner** : Trivy, Grype (CVE, mauvaises configurations) en CI **et** dans le registre.
3. **Signer** : cosign (Sigstore) ; **vérifier** la signature à l'admission (Kyverno `verifyImages`, policy-controller).
4. **Tracer** : SBOM (Syft), attestations de provenance (SLSA).
5. **Référencer par digest** (`image@sha256:…`) pour l'immuabilité.
6. **Registre** : privé, accès limité, nettoyage régulier.

### 1.13 Détection et réponse
- **Audit logs** de l'API server (politique d'audit) : qui a fait quoi, quand.
- **Falco**/**Tetragon** : détection comportementale au runtime (shell dans un conteneur, lecture de `/etc/shadow`, connexion sortante inhabituelle).
- **kube-bench** (CIS Benchmark), **kubescape**, **Polaris** : conformité de la configuration.
- Réponse : isoler le Pod (label qui le retire du Service + NetworkPolicy « quarantaine »), conserver les preuves (copie du disque/mémoire), rotation des secrets, analyse, post-mortem.

### 1.14 Check-list de durcissement d'une application
- [ ] Image minimale, scannée, signée, tag immuable
- [ ] `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: ALL`, `seccomp: RuntimeDefault`
- [ ] ServiceAccount dédié, token non monté si inutile, RBAC minimal
- [ ] NetworkPolicy : default deny + autorisations explicites (DNS inclus)
- [ ] requests/limits, PDB, probes
- [ ] Secrets via un gestionnaire externe, jamais dans l'image ni dans Git
- [ ] Namespace en Pod Security `restricted`
- [ ] Journaux et métriques collectés, alertes configurées

## 2. 🎬 Démo (45 min)

```bash
kubectl create ns lab-secu && kubectl config set-context --current --namespace=lab-secu

# RBAC : un SA "lecteur" qui ne peut que lister les pods
kubectl apply -f manifests/01-rbac.yaml
kubectl auth can-i list pods   --as=system:serviceaccount:lab-secu:lecteur     # yes
kubectl auth can-i delete pods --as=system:serviceaccount:lab-secu:lecteur     # no
kubectl auth can-i list secrets --as=system:serviceaccount:lab-secu:lecteur    # no
kubectl apply -f manifests/02-pod-sa.yaml && kubectl logs api-client

# Pod Security Admission
kubectl label ns lab-secu pod-security.kubernetes.io/enforce=restricted
kubectl run root --image=nginx:1.27                          # REFUSÉ : violations listées
kubectl apply -f manifests/03-pod-securise.yaml              # accepté

# Secret en clair vs RBAC
kubectl create secret generic s --from-literal=pw=topsecret
kubectl get secret s -o jsonpath='{.data.pw}' | base64 -d
```

## 3. 🧪 Labos

> Namespace : `lab-secu`

### Lab 7.1 ⭐ — Moindre privilège
Créez un ServiceAccount `dev` et un Role `pod-reader` (get/list/watch sur `pods`) lié via un RoleBinding. Vérifiez avec `auth can-i` : lister les pods (oui), supprimer (non), lister dans un **autre** namespace (non).

<details><summary>Corrigé</summary>

```bash
kubectl create sa dev
kubectl create role pod-reader --verb=get,list,watch --resource=pods
kubectl create rolebinding dev-reader --role=pod-reader --serviceaccount=lab-secu:dev
kubectl auth can-i list pods --as=system:serviceaccount:lab-secu:dev            # yes
kubectl auth can-i list pods -n default --as=system:serviceaccount:lab-secu:dev # no
```
</details>

### Lab 7.2 ⭐⭐ — Appeler l'API depuis un Pod
Lancez un Pod utilisant le SA `lecteur` qui appelle `https://kubernetes.default.svc/api/v1/namespaces/lab-secu/pods` avec son token. Constatez 200 ; puis sur `/secrets` → 403.

<details><summary>Corrigé</summary>
Voir `02-pod-sa.yaml` (token monté dans `/var/run/secrets/kubernetes.io/serviceaccount/token`).
</details>

### Lab 7.3 ⭐⭐ — Utilisateur humain via certificat
Créez un utilisateur `alice` : clé privée, CSR, signature par l'API (`CertificateSigningRequest`), entrée dans un kubeconfig dédié, puis droits en lecture sur le namespace via RoleBinding.

<details><summary>Corrigé</summary>

```bash
openssl genrsa -out alice.key 2048
openssl req -new -key alice.key -out alice.csr -subj "/CN=alice/O=devs"
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata: {name: alice}
spec:
  request: $(base64 -w0 < alice.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: [client auth]
EOF
kubectl certificate approve alice
kubectl get csr alice -o jsonpath='{.status.certificate}' | base64 -d > alice.crt
kubectl config set-credentials alice --client-certificate=alice.crt --client-key=alice.key --embed-certs
kubectl config set-context alice --cluster=kind-formation --user=alice --namespace=lab-secu
kubectl create rolebinding alice-view --clusterrole=view --user=alice
kubectl --context alice get pods
```
</details>

### Lab 7.4 ⭐⭐ — Pod Security Admission
Appliquez `enforce=restricted` au namespace. Corrigez un Pod nginx pour qu'il soit accepté (runAsNonRoot, drop ALL, seccomp, pas d'escalade). Indice : utilisez `nginxinc/nginx-unprivileged:1.27` (port 8080).

<details><summary>Corrigé</summary>
Voir `03-pod-securise.yaml`. Astuce : `kubectl label --dry-run=server --overwrite ns lab-secu pod-security.kubernetes.io/enforce=restricted` liste les Pods existants non conformes avant d'activer.
</details>

### Lab 7.5 ⭐⭐ — Filesystem en lecture seule
Ajoutez `readOnlyRootFilesystem: true` à un conteneur qui écrit dans `/tmp`. L'erreur ? Corrigez avec un `emptyDir` monté sur `/tmp`.

<details><summary>Corrigé</summary>
Voir `03-pod-securise.yaml` (volumes `tmp` et `cache` pour nginx-unprivileged).
</details>

### Lab 7.6 ⭐⭐⭐ — Audit RBAC
Trouvez qui peut `create pods` dans le cluster (`kubectl auth can-i --list`, `kubectl get clusterrolebindings -o wide`, `who-can` si disponible). Identifiez les `cluster-admin` : tous légitimes ?

<details><summary>Corrigé</summary>

```bash
kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .metadata.name + " -> " + ([.subjects[]?|.kind+"/"+.name]|join(","))'
kubectl auth can-i --list --as=system:serviceaccount:lab-secu:default
```
</details>

### Lab 7.7 ⭐⭐⭐ — Politique Kyverno / ValidatingAdmissionPolicy
Interdisez le tag `:latest` et exigez des `resources.limits`. Utilisez la **ValidatingAdmissionPolicy** native (GA depuis 1.30).

<details><summary>Corrigé</summary>
Voir `04-admission-policy.yaml` : `kubectl run x --image=nginx:latest` est refusé.
</details>

### Lab 7.8 ⭐⭐⭐ — Scan d'image
Scannez `nginx:1.21` avec Trivy (`docker run aquasec/trivy image nginx:1.21`). Combien de CVE HIGH/CRITICAL ? Comparez avec `nginx:1.27-alpine`. Quelle politique de mise à jour en déduire ?

<details><summary>Corrigé</summary>
Les images anciennes cumulent des dizaines de CVE ; préférer des bases minimales (alpine, distroless), épingler par digest et rescanner en CI **et** en continu.
</details>

## 4. Quiz
1. Kubernetes gère-t-il les utilisateurs humains ? → non ; délégués à un IdP/certificats/OIDC.
2. Role vs ClusterRole ? → namespaced vs cluster (ou réutilisable via RoleBinding).
3. Pourquoi le droit `create pods` est-il sensible ? → un Pod peut monter des secrets/hostPath → escalade.
4. Les 3 niveaux de Pod Security Standards ? → privileged, baseline, restricted.
5. base64 protège-t-il un Secret ? → non.

Nettoyage : `kubectl delete ns lab-secu` · `kubectl config delete-context alice`
