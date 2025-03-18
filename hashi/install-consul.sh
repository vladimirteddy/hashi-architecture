#!/bin/bash
set -e

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE=${NAMESPACE:-consul}
RELEASE_NAME=${RELEASE_NAME:-consul}
VALUES_FILE=${VALUES_FILE:-""}

# Print header
echo "==============================================="
echo "HashiCorp Consul Kubernetes Installation Script"
echo "==============================================="
echo ""

# Check kubectl
if ! command -v kubectl &> /dev/null; then
  echo "Error: kubectl command not found. Please install kubectl first."
  exit 1
fi

# Check helm
if ! command -v helm &> /dev/null; then
  echo "Error: helm command not found. Please install helm first."
  exit 1
fi

# Create namespace if it doesn't exist
echo "Creating namespace $NAMESPACE..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Add HashiCorp helm repo if not already added
echo "Adding HashiCorp Helm repository..."
if ! helm repo list | grep -q "https://helm.releases.hashicorp.com"; then
  helm repo add hashicorp https://helm.releases.hashicorp.com
  helm repo update
fi

# Using values.yaml file for configuration
if [[ -f "$SCRIPT_DIR/consul-helm/values.yaml" ]]; then
  echo "Using values.yaml file for configuration"
  helm upgrade --install $RELEASE_NAME hashicorp/consul --namespace $NAMESPACE -f "$SCRIPT_DIR/consul-helm/values.yaml"
else
  echo "Error: values.yaml file not found in $SCRIPT_DIR/consul-helm/"
  exit 1
fi

echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pod --all -n $NAMESPACE --timeout=300s || true

echo ""
echo "Consul installation completed!"
echo ""
echo "Consul server status:"
kubectl get pods -l app=consul,component=server -n $NAMESPACE
  
echo ""
echo "Consul UI service:"
kubectl get svc -l app=consul,component=ui -n $NAMESPACE
  
echo ""
echo "To access Consul UI, run:"
echo "  kubectl port-forward svc/$RELEASE_NAME-ui -n $NAMESPACE 8500:80"
echo "Then open http://localhost:8500 in your browser"
  
if kubectl get secret -n $NAMESPACE $RELEASE_NAME-bootstrap-acl-token &> /dev/null; then
  echo ""
  echo "To get the ACL bootstrap token:"
  echo "  kubectl get secret -n $NAMESPACE $RELEASE_NAME-bootstrap-acl-token -o jsonpath='{.data.token}' | base64 -d"
fi

echo ""
echo "==========================="
echo "Installation complete"
echo "===========================" 