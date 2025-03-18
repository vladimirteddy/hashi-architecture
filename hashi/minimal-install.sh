#!/bin/bash
set -e

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE=${NAMESPACE:-consul}
RELEASE_NAME=${RELEASE_NAME:-consul}

# Cleanup previous installation
echo "Cleaning up previous installation..."
helm uninstall $RELEASE_NAME -n $NAMESPACE 2>/dev/null || true
kubectl delete namespace $NAMESPACE 2>/dev/null || true

# Create namespace
echo "Creating namespace $NAMESPACE..."
kubectl create namespace $NAMESPACE

# Add HashiCorp helm repo
echo "Adding HashiCorp Helm repository..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install with minimal values
echo "Installing Consul with minimal values..."
helm install $RELEASE_NAME hashicorp/consul \
  --namespace $NAMESPACE \
  --set global.name=consul \
  --set server.replicas=1 \
  --set server.storage.enabled=false \
  --set server.affinity=null \
  --set client.enabled=true \
  --set ui.enabled=true \
  --set connectInject.enabled=false \
  --set controller.enabled=false \
  --set syncCatalog.enabled=false \
  --set dns.enabled=true

echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod --all -n $NAMESPACE --timeout=300s || true

echo ""
echo "Consul pods:"
kubectl get pods -n $NAMESPACE

echo ""
echo "To access the Consul UI, run:"
echo "  kubectl port-forward svc/$RELEASE_NAME-ui -n $NAMESPACE 8500:80"
echo "Then open http://localhost:8500 in your browser" 