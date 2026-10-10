# Aide-mémoire kubectl

## Productivité
```bash
alias k=kubectl
export do="--dry-run=client -o yaml"
k config get-contexts ; k config use-context <ctx>
k config set-context --current --namespace=<ns>
k api-resources ; k explain pod.spec.containers --recursive
```

## Lire
```bash
k get pods -A -o wide -w
k get pods -l app=web --show-labels
k get pod X -o yaml | k neat        # ou -o jsonpath='{.status.podIP}'
k get events --sort-by=.lastTimestamp
k get all -n ns
k describe pod X
k top pods --sort-by=memory ; k top nodes
```

## Créer (générer du YAML)
```bash
k run nginx --image=nginx:1.27 $do > pod.yaml
k create deploy web --image=nginx:1.27 --replicas=3 $do
k expose deploy web --port=80 --target-port=80 --type=ClusterIP $do
k create cm cfg --from-literal=k=v --from-file=app.conf
k create secret generic s --from-literal=pw=x
k create job j --image=busybox -- echo hi
k create cronjob c --image=busybox --schedule="*/5 * * * *" -- echo hi
k create ingress web --rule="web.local/=web:80" --class=nginx
k create role r --verb=get,list --resource=pods
k create rolebinding rb --role=r --serviceaccount=ns:sa
```

## Modifier
```bash
k apply -f x.yaml ; k apply -k overlay/ ; k diff -f x.yaml
k edit deploy web ; k patch deploy web -p '{"spec":{"replicas":5}}'
k scale deploy web --replicas=5
k set image deploy/web nginx=nginx:1.27
k set resources deploy web --requests=cpu=100m,memory=64Mi --limits=memory=128Mi
k label pod X env=prod ; k annotate pod X note=hi
k rollout status|history|undo|restart deploy/web
k delete -f x.yaml ; k delete pod X --force --grace-period=0
```

## Déboguer
```bash
k logs X [-c ctr] [-f] [--previous] [--tail=50] [--since=5m] [-l app=web --prefix]
k exec -it X -- sh
k port-forward svc/web 8080:80
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh
k debug -it X --image=busybox:1.36 --target=ctr
k debug node/NODE -it --image=busybox:1.36
k auth can-i create pods --as=system:serviceaccount:ns:sa
k get endpoints svc ; k get endpointslices
```

## Nœuds
```bash
k cordon N ; k drain N --ignore-daemonsets --delete-emptydir-data ; k uncordon N
k taint nodes N key=val:NoSchedule ; k taint nodes N key=val:NoSchedule-
k label nodes N disk=ssd
```

## JSONPath / colonnes
```bash
k get pods -o custom-columns=N:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
k get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
k get secret s -o jsonpath='{.data.pw}' | base64 -d
```

## Helm
```bash
helm repo add|update ; helm search repo X ; helm show values X
helm upgrade --install rel chart -n ns --create-namespace -f values.yaml
helm template|lint ; helm list -A ; helm history rel ; helm rollback rel N ; helm uninstall rel
```

## Statuts → causes probables
| Statut | Regarder |
|---|---|
| `Pending` | `describe` : ressources, taints, PVC, nodeSelector |
| `ImagePullBackOff` | nom/tag, registre privé, réseau |
| `CrashLoopBackOff` | `logs --previous`, exit code, probes, config |
| `OOMKilled` (137) | limite mémoire |
| `CreateContainerConfigError` | ConfigMap/Secret manquant |
| `Running 0/1` | readiness probe |
| `Evicted` | pression ressources du nœud |
| `Terminating` bloqué | finalizers, volume, nœud injoignable |

## Champs YAML à connaître par cœur
`metadata.{name,namespace,labels}` · `spec.replicas` · `spec.selector.matchLabels` · `spec.template` · `containers[].{image,ports,env,envFrom,resources,volumeMounts,livenessProbe,readinessProbe,securityContext}` · `volumes[]` · `nodeSelector/affinity/tolerations` · `serviceAccountName`
