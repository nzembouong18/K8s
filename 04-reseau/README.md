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

# NetworkPolicy
kubectl apply -f manifests/03-netpol.yaml
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
Trois Deployments `frontend`, `backend`, `db` (labels `tier`). Règles : tout interdit par défaut ; `frontend` → `backend` (8080) ; `backend` → `db` (5432) ; DNS autorisé. Prouvez par `curl`/`nc` que `frontend` ne peut pas joindre `db`.

<details><summary>Corrigé</summary>
Voir `manifests/03-netpol.yaml`.
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

Nettoyage : `kubectl delete ns lab-reseau`
