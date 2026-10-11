#!/usr/bin/env bash
# Installe kubectl, kind et helm (Linux amd64) dans /usr/local/bin
set -euo pipefail

KIND_VERSION="${KIND_VERSION:-v0.24.0}"
BIN=/usr/local/bin
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

command -v docker >/dev/null || { echo "Docker est requis : https://docs.docker.com/engine/install/"; exit 1; }

if ! command -v kubectl >/dev/null; then
  KV="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KV}/bin/linux/amd64/kubectl"
  $SUDO install -m 0755 /tmp/kubectl "$BIN/kubectl"
fi

if ! command -v kind >/dev/null; then
  curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
  $SUDO install -m 0755 /tmp/kind "$BIN/kind"
fi

if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

kubectl version --client
kind version
helm version --short
