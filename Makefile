CLUSTER ?= formation

.PHONY: cluster delete ingress metrics check clean-labs lint

cluster: ## Crée le cluster kind (1 CP + 2 workers)
	kind create cluster --name $(CLUSTER) --config 00-setup/kind-cluster.yaml
	kubectl cluster-info --context kind-$(CLUSTER)

delete: ## Supprime le cluster
	kind delete cluster --name $(CLUSTER)

ingress: ## Installe ingress-nginx (module 04)
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/kind/deploy.yaml
	kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=180s

metrics: ## Installe metrics-server (module 06/09)
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	kubectl -n kube-system patch deploy metrics-server --type=json \
	  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

check: ## Vérifie l'environnement
	./00-setup/scripts/check-env.sh

clean-labs: ## Supprime tous les namespaces de labs
	kubectl get ns -o name | grep 'namespace/lab-' | xargs -r kubectl delete

lint: ## Valide la syntaxe YAML de tous les manifests
	python3 -c "import sys,glob,yaml; [list(yaml.safe_load_all(open(f))) for f in glob.glob('**/manifests/*.yaml',recursive=True)+glob.glob('00-setup/*.yaml')]; print('YAML OK')"
