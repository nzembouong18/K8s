# Guide de dépannage

## Arbre de décision

```
Application inaccessible ?
├─ Pod OK (Running, Ready) ?
│   ├─ NON → voir « Pod en erreur »
│   └─ OUI → Service
│        ├─ `k get endpoints <svc>` vide ? → selector ≠ labels, ou Pods non Ready
│        ├─ targetPort faux ? (`k describe svc`, port réel du conteneur)
│        ├─ DNS ? `k run t --rm -it --image=busybox:1.36 -- nslookup <svc>`
│        ├─ NetworkPolicy ? `k get netpol -n <ns>`
│        └─ Ingress ? host/path, ingressClassName, logs du contrôleur, service/port backend
└─ Nœud ? `k get nodes` (NotReady) → `journalctl -u kubelet`, runtime, disque, CNI
```

## Pod en erreur

| Symptôme | Commandes | Causes fréquentes |
|---|---|---|
| **Pending** | `k describe pod` | `Insufficient cpu/memory` · `untolerated taint` · `didn't match node selector/affinity` · `unbound PVC` · quota dépassé |
| **ContainerCreating** long | `k describe pod` | PVC non attaché, Secret/ConfigMap monté absent, CNI en échec |
| **ErrImagePull / ImagePullBackOff** | `k describe pod` | tag inexistant, registre privé sans `imagePullSecrets`, rate-limit Docker Hub, proxy |
| **CreateContainerConfigError** | `k describe pod` | Secret/ConfigMap/clé introuvable |
| **CrashLoopBackOff** | `k logs --previous`, `k describe` | erreur applicative, mauvaise commande, config absente, liveness trop agressive, **OOMKilled** |
| **OOMKilled (137)** | `k describe` → Last State | limite mémoire trop basse / fuite |
| **Running 0/1** | `k describe`, `k get endpoints` | readiness échoue |
| **Evicted** | `k describe` | pression mémoire/disque du nœud, BestEffort |
| **Terminating** bloqué | `k get pod -o yaml` (finalizers) | finalizer, volume, nœud perdu ; en dernier recours `--force --grace-period=0` |

## Réseau — tests rapides
```bash
# Pod de diagnostic
k run netshoot --rm -it --image=nicolaka/netshoot --restart=Never -- bash
  curl -sv http://<svc>.<ns>.svc.cluster.local
  dig +short <svc>.<ns>.svc.cluster.local
  nc -zv <svc> <port>
# Côté service
k get svc,endpointslices -n <ns>
k -n kube-system logs -l k8s-app=kube-dns
```

## Stockage
```bash
k get pvc,pv,sc
k describe pvc X          # Events : provisioner, WaitForFirstConsumer, capacité
```
`Pending` + `WaitForFirstConsumer` est **normal** tant qu'aucun Pod ne consomme le PVC.

## Nœud
```bash
k describe node N         # Conditions: MemoryPressure, DiskPressure, PIDPressure, Ready
k get node N -o jsonpath='{.status.allocatable}'
# kind :
docker exec N journalctl -u kubelet --no-pager | tail -50
docker exec N crictl ps -a
```

## Plan de contrôle
```bash
k get --raw='/readyz?verbose'
k -n kube-system get pods
k -n kube-system logs kube-apiserver-<cp>  # kind: etcd, scheduler, controller-manager idem
k get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -20
```

## Réflexes à retenir
1. **Lire l'erreur** en entier (`describe` → Events).
2. **Un changement à la fois**, vérifier, noter.
3. Comparer **ce qui est demandé** (`spec`) et **ce qui est observé** (`status`).
4. Reproduire dans un Pod jetable (`k run --rm -it`).
5. Documenter la cause racine dans un runbook.
