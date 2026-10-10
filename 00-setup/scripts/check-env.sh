#!/usr/bin/env bash
# Vérifie que l'environnement de formation est prêt
ok=0
check() { # description, commande
  if eval "$2" >/dev/null 2>&1; then echo "✅ $1"; else echo "❌ $1"; ok=1; fi
}
check "docker installé et démarré"      "docker info"
check "kubectl installé"                "kubectl version --client"
check "kind installé"                   "kind version"
check "helm installé"                   "helm version"
check "cluster accessible"              "kubectl get nodes"
check "3 nœuds Ready"                   "[ \$(kubectl get nodes --no-headers | grep -c ' Ready') -ge 3 ]"
check "CoreDNS opérationnel"            "kubectl -n kube-system rollout status deploy/coredns --timeout=30s"
exit $ok
