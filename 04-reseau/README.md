# Module 04 — Réseau : Services, DNS, Ingress, NetworkPolicy

⏱ 3 h · 🟡 Intermédiaire

## Objectifs
- Comprendre le modèle réseau (Pod-à-Pod sans NAT)
- Exposer une application : ClusterIP, NodePort, LoadBalancer, Headless
- Utiliser le DNS interne ; publier en HTTP(S) via Ingress / Gateway API
- Restreindre les flux avec les NetworkPolicies

## 1. Cours

### 1.1 Modèle réseau
1. Tout Pod a sa propre IP ; tout Pod peut joindre tout Pod sans NAT.
2. Les IP de Pods sont **éphémères** → on passe par un **Service** (IP virtuelle stable + load-balancing via kube-proxy sur les `Endpoints`/`EndpointSlices`).
3. Le CNI (Calico, Cilium, Flannel…) implémente le réseau ; **les NetworkPolicies exigent un CNI qui les supporte** (Calico, Cilium ; pas kindnet par défaut → voir démo).

### 1.2 Types de Service
| Type | Accès | Usage |
|---|---|---|
| **ClusterIP** (défaut) | Interne | Communication inter-services |
| **NodePort** | `<IP nœud>:30000-32767` | Tests, on-prem simple |
| **LoadBalancer** | IP/DNS externe du cloud | Prod cloud (MetalLB on-prem) |
| **ExternalName** | CNAME DNS | Alias vers un service externe |
| **Headless** (`clusterIP: None`) | DNS retourne les IP des Pods | StatefulSet, découverte |

Le lien Service → Pods se fait par `selector` ; si aucun Pod ne matche, l'`Endpoints` est vide (erreur n°1).

### 1.3 DNS (CoreDNS)
- Service : `<svc>.<ns>.svc.cluster.local` (depuis le même ns : `<svc>`)
- Pod StatefulSet : `<pod>.<svc>.<ns>.svc.cluster.local`
- `/etc/resolv.conf` du Pod : `search <ns>.svc.cluster.local svc.cluster.local cluster.local`

### 1.4 Ingress et Gateway API
**Ingress** : règles HTTP(S) L7 (host/path → Service) exécutées par un **Ingress Controller** (ingress-nginx, Traefik, HAProxy). Terminaison TLS via Secret.
**Gateway API** (`gateway.networking.k8s.io`, GA) : successeur plus expressif (GatewayClass, Gateway, HTTPRoute) avec séparation des rôles infra / développeurs. Recommandé pour les nouveaux projets.

### 1.5 NetworkPolicy
Par défaut tout est ouvert. Dès qu'une policy **sélectionne** un Pod, seul le trafic autorisé passe (pour les directions `Ingress`/`Egress` listées). Bonne pratique : **default deny** puis autoriser explicitement (+ DNS en egress).

### 1.6 Chemin d'un paquet : de l'extérieur au conteneur
```
Client ─► LoadBalancer (IP externe) ─► Node:NodePort ─► kube-proxy (iptables/IPVS/nftables) ─► Pod (IP du réseau CNI) ─► conteneur:targetPort
                                     ▲ ClusterIP (IP virtuelle, n'existe sur aucune interface : simple règle DNAT)
```
- Un **ClusterIP** n'est *pas* une adresse que l'on peut « pinger » : c'est une règle de redirection. Elle n'est joignable que depuis le cluster.
- Les Services de type `NodePort` et `LoadBalancer` **incluent** un ClusterIP.
- `externalTrafficPolicy: Local` conserve l'IP source du client et évite un saut réseau, mais ne distribue qu'aux Pods du nœud recevant le trafic.
- `sessionAffinity: ClientIP` colle un client au même Pod (par défaut, répartition quasi aléatoire).

### 1.7 Les quatre « ports » à ne pas confondre
| Champ | Où | Signification |
|---|---|---|
| `containerPort` | Pod | port d'écoute du conteneur (indicatif, documentation) |
| `port` | Service | port exposé par le Service (celui que l'on appelle) |
| `targetPort` | Service | port du Pod vers lequel rediriger (numéro ou **nom** de port) |
| `nodePort` | Service NodePort | port ouvert sur chaque nœud (30000–32767) |
Erreur fréquente : `targetPort` différent du port réel d'écoute → « connection refused ». Utilisez des **ports nommés** (`name: http`) pour que Service et Pod restent cohérents.

### 1.8 Endpoints et EndpointSlices
Le contrôleur d'EndpointSlices maintient, pour chaque Service, la liste des IP:port des Pods **Ready** qui correspondent au `selector`. kube-proxy (ou le CNI) lit ces objets. Diagnostic n°1 d'un Service qui ne répond pas :
```bash
kubectl get endpointslices -l kubernetes.io/service-name=web
kubectl get pods --show-labels                 # les labels correspondent-ils au selector ?
kubectl describe svc web                       # Endpoints: <none> ?
```
Un Pod non Ready (readiness en échec) est retiré des endpoints : c'est le comportement voulu pour ne pas lui envoyer de trafic.

### 1.9 DNS en détail
- CoreDNS (Deployment dans `kube-system`) est configuré par le ConfigMap `coredns` (Corefile) ; les Pods reçoivent l'IP du service `kube-dns` dans `/etc/resolv.conf`.
- `ndots:5` : tout nom contenant moins de 5 points est d'abord essayé avec chaque domaine de recherche, ce qui multiplie les requêtes pour les noms externes. Utiliser un nom **complet terminé par un point** (`api.exemple.com.`) ou réduire `ndots` via `dnsConfig` dans les applications très sollicitées.
- `dnsPolicy` : `ClusterFirst` (défaut), `Default` (hérite du nœud), `None` (configuration manuelle via `dnsConfig`).
- Enregistrements SRV pour les ports nommés : `_http._tcp.web.ns.svc.cluster.local`.
- Un Service headless renvoie **toutes** les IP des Pods (enregistrements A multiples) ; avec un StatefulSet, chaque Pod a son propre enregistrement.
- Pannes DNS typiques : CoreDNS saturé, NetworkPolicy qui bloque l'egress UDP/TCP 53, boucle de résolution.

### 1.10 Ingress : fonctionnement et limites
- Un objet `Ingress` est une **déclaration** ; seul un **Ingress Controller** (ingress-nginx, Traefik, HAProxy, Contour, contrôleurs des clouds) la rend effective. Sélection par `ingressClassName`.
- Règles : `host` + `path` (`pathType: Prefix | Exact | ImplementationSpecific`) → `backend.service`.
- TLS : `spec.tls[].secretName` (Secret `kubernetes.io/tls`) ; **cert-manager** automatise l'émission et le renouvellement (Let's Encrypt).
- Les fonctions avancées (redirections, réécritures, limitation de débit, authentification) passent par des **annotations propres à chaque contrôleur** : non portables. C'est une limite majeure de l'API Ingress.
- Un Ingress est typiquement exposé via **un** Service LoadBalancer devant le contrôleur : un seul point d'entrée pour de nombreuses applications (économie d'IP et de coûts).
> Vérifiez l'état de maintenance du contrôleur choisi : l'écosystème évolue (le projet ingress-nginx de la communauté a annoncé son arrêt de maintenance), ce qui renforce l'intérêt de **Gateway API** pour les nouveaux projets.

### 1.11 Gateway API : le modèle de rôles
| Objet | Géré par | Rôle |
|---|---|---|
| `GatewayClass` | fournisseur d'infra | type d'implémentation (Envoy, Istio, Cilium…) |
| `Gateway` | équipe plateforme | points d'entrée : ports, protocoles, TLS, namespaces autorisés |
| `HTTPRoute` / `GRPCRoute` / `TCPRoute` | équipes applicatives | règles de routage vers leurs Services |
Atouts : routage par en-têtes, pondération (canary), redirections, réécritures **dans la spec** (pas d'annotations), partage d'un Gateway entre équipes avec contrôle (`allowedRoutes`), `ReferenceGrant` pour autoriser les références inter-namespaces.
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: web}
spec:
  parentRefs: [{name: public-gw}]
  hostnames: ["web.exemple.com"]
  rules:
    - matches: [{path: {type: PathPrefix, value: /api}}]
      backendRefs:
        - {name: api-v1, port: 80, weight: 90}
        - {name: api-v2, port: 80, weight: 10}      # canary 10 %
```

### 1.12 NetworkPolicy : bien les écrire
- Une policy est **additive** : l'union des règles de toutes les policies qui sélectionnent un Pod est autorisée.
- `podSelector: {}` sélectionne tous les Pods du namespace ; `policyTypes` précise `Ingress` et/ou `Egress`.
- Sélecteurs de pairs : `podSelector`, `namespaceSelector` (label `kubernetes.io/metadata.name` automatique), `ipBlock` (CIDR). **Attention** : `podSelector` et `namespaceSelector` dans le **même** élément = ET ; dans deux éléments distincts = OU.
- Ne pas oublier l'**egress DNS** (UDP/TCP 53 vers `kube-system`) dès qu'on restreint la sortie.
- Modèle de départ sûr :
```yaml
# 1. Tout interdire (entrée) dans le namespace
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata: {name: default-deny-ingress}
spec: {podSelector: {}, policyTypes: [Ingress]}
---
# 2. Autoriser front → api sur 8080
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata: {name: api-from-front}
spec:
  podSelector: {matchLabels: {app: api}}
  ingress:
    - from: [{podSelector: {matchLabels: {app: front}}}]
      ports: [{port: 8080}]
```
- Tester : `kubectl exec` + `curl`/`nc` depuis un Pod autorisé et depuis un Pod non autorisé ; outils : `cilium connectivity test`, Hubble, `netshoot`.
- Les NetworkPolicy standard sont L3/L4 : les règles L7 (méthodes HTTP, FQDN) relèvent des CRD du CNI (CiliumNetworkPolicy) ou d'un service mesh.

### 1.13 Maillage de services (service mesh) en bref
Istio, Linkerd, Cilium Service Mesh ajoutent : mTLS automatique entre services, politiques d'autorisation L7, observabilité fine (traces, métriques RED), résilience (retries, timeouts, disjoncteurs), routage avancé. Coût : complexité opérationnelle et consommation de ressources (sidecars ou mode *ambient*). À envisager quand ces besoins sont avérés, pas par défaut.

### 1.14 Dépannage réseau : méthode
1. **Le Pod est-il Ready ?** (`get pods`) 2. **Le Service a-t-il des endpoints ?** 3. **Le DNS répond-il ?** (`nslookup web` depuis un Pod) 4. **Le port est-il bon ?** (`curl pod-ip:targetPort` depuis un Pod voisin) 5. **Une NetworkPolicy bloque-t-elle ?** 6. **Ingress/Gateway** : logs du contrôleur, hôte/chemin, backend. 7. **Nœud/CNI** : pods CNI, `kubectl get nodes`, MTU.
Image de diagnostic pratique : `kubectl run net --rm -it --image=nicolaka/netshoot -- bash` (dig, curl, tcpdump, ss…).

## 2. 🎬 Démo (40 min)

Prérequis : `make ingress` (depuis la racine).

```bash
kubectl create ns lab-reseau && kubectl config set-context --current --namespace=lab-reseau
kubectl apply -f manifests/01-app-service.yaml
kubectl get svc,endpointslices
kubectl run tmp --rm -it --image=curlimages/curl --restart=Never -- curl -s web          # DNS court
kubectl run tmp --rm -it --image=curlimages/curl --restart=Never -- curl -s web.lab-reseau.svc.cluster.local
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup web
kubectl scale deploy web --replicas=0 ; kubectl get endpoints web                         # vide !
kubectl scale deploy web --replicas=3

# Ingress
kubectl apply -f manifests/02-ingress.yaml
curl -H 'Host: web.local' http://localhost/
curl -H 'Host: web.local' http://localhost/api

# NetworkPolicy (lab-netpol, voir Lab 4.7)
kubectl apply -f manifests/05-trois-tiers.yaml -f manifests/03-netpol.yaml     # crée aussi le namespace
```

## 3. 🧪 Labos

> Namespace : `lab-reseau`

### Lab 4.1 ⭐ — Exposer en ClusterIP
Déployez `web` (3 × nginx) et un Service `web` (port 80). Depuis un Pod `curl` temporaire, appelez le Service **plusieurs fois** et constatez la répartition (hostname dans la réponse via `whoami`).

<details><summary>Corrigé</summary>
`01-app-service.yaml` utilise `traefik/whoami` : chaque réponse affiche `Hostname:`.

```bash
kubectl run tmp --rm -it --image=curlimages/curl --restart=Never -- sh -c 'for i in $(seq 6); do curl -s web | grep Hostname; done'
```
</details>

### Lab 4.2 ⭐ — Service sans Endpoints
Créez un Service dont le `selector` comporte une faute de frappe. Diagnostiquez avec `kubectl get endpoints` et corrigez.

<details><summary>Corrigé</summary>
`kubectl describe svc` montre `Endpoints: <none>`. Comparez `kubectl get svc -o yaml` (selector) et `kubectl get pods --show-labels`. Corriger le selector.
</details>

### Lab 4.3 ⭐⭐ — NodePort
Exposez `web` en NodePort 30080. Sur kind, le port n'est pas mappé à l'hôte : accédez-y via `docker exec formation-worker curl -s localhost:30080`. Pourquoi ?

<details><summary>Corrigé</summary>
Les nœuds sont des conteneurs Docker : le NodePort écoute dans le conteneur-nœud, pas sur l'hôte (sauf `extraPortMappings`). Sur kubeadm/bare-metal, `curl <IP-nœud>:30080` fonctionne.
</details>

### Lab 4.4 ⭐⭐ — Ingress multi-chemins
Deux applications `web` et `api` ; Ingress `web.local` : `/` → web, `/api` → api (avec `pathType: Prefix`). Testez avec `curl -H 'Host: web.local'`.

<details><summary>Corrigé</summary>
Voir `manifests/02-ingress.yaml`. Ajoutez `127.0.0.1 web.local` à `/etc/hosts` pour tester par navigateur.
</details>

### Lab 4.5 ⭐⭐ — Ingress TLS
Générez un certificat auto-signé, créez un Secret `tls`, ajoutez la section `tls:` à l'Ingress et testez `curl -k https://web.local --resolve web.local:443:127.0.0.1`.

<details><summary>Corrigé</summary>

```bash
openssl req -x509 -nodes -newkey rsa:2048 -days 30 -keyout tls.key -out tls.crt -subj "/CN=web.local"
kubectl create secret tls web-tls --cert=tls.crt --key=tls.key
# Ajouter à l'Ingress :
#   tls: [{hosts: [web.local], secretName: web-tls}]
curl -k --resolve web.local:443:127.0.0.1 https://web.local/
```
En production : cert-manager + Let's Encrypt.
</details>

### Lab 4.6 ⭐⭐ — DNS d'un StatefulSet
Avec le Service headless `db` du module 03, résolvez `db-0.db`, puis `db` (quelles IP obtenez-vous ?).

<details><summary>Corrigé</summary>

```bash
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup db-0.db.lab-workloads.svc.cluster.local
```
`db` seul renvoie **toutes** les IP des Pods (A multiples).
</details>

### Lab 4.7 ⭐⭐⭐ — NetworkPolicy « 3 tiers »
Dans un namespace dédié `lab-netpol` (pour ne pas casser les autres labs), déployez les trois tiers avec `manifests/05-trois-tiers.yaml` (`frontend`, `backend`, `db`, label `tier`). Règles : tout interdit par défaut ; `frontend` → `backend` (8080) ; `backend` → `db` (5432) ; DNS autorisé. Prouvez par `curl`/`nc` que `frontend` ne peut pas joindre `db`.

<details><summary>Corrigé</summary>
Voir `manifests/03-netpol.yaml` (namespace `lab-netpol`). Tests :
```bash
kubectl apply -f manifests/05-trois-tiers.yaml                         # crée le namespace lab-netpol
kubectl apply -f manifests/03-netpol.yaml                               # appliquer APRÈS avoir testé l'état « tout ouvert »
kubectl -n lab-netpol exec deploy/frontend -- curl -s -m 3 backend:8080      # OK
kubectl -n lab-netpol exec deploy/frontend -- curl -s -m 3 db:5432           # timeout (bloqué)
kubectl -n lab-netpol exec deploy/backend -c client -- curl -s -m 3 db:5432           # OK
```
⚠ Avec kindnet les policies ne sont **pas appliquées** : installer Calico (`kind` avec `disableDefaultCNI: true`) ou Cilium pour valider. À défaut, relire/valider le YAML avec `kubectl apply --dry-run=server`.
</details>

### Lab 4.8 ⭐⭐⭐ — Gateway API (optionnel)
Installez les CRD Gateway API et un contrôleur (ex. Envoy Gateway / NGINX Gateway Fabric), créez `Gateway` + `HTTPRoute` équivalents à l'Ingress du Lab 4.4.

<details><summary>Corrigé</summary>
Voir `manifests/04-gateway-api.yaml` (nécessite les CRD).
</details>

## 4. Quiz
1. Pourquoi ne pas utiliser l'IP d'un Pod ? → éphémère.
2. Service ClusterIP : où est-il « réellement » implémenté ? → règles iptables/IPVS (kube-proxy) ou eBPF (Cilium).
3. Un Ingress sans Ingress Controller ? → aucun effet.
4. Une NetworkPolicy sans CNI compatible ? → silencieusement ignorée.
5. FQDN d'un Service `api` dans `prod` ? → `api.prod.svc.cluster.local`.

Nettoyage : `kubectl delete ns lab-reseau lab-netpol`
