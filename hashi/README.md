# HashiCorp Consul on Kubernetes

This directory contains simplified scripts to deploy HashiCorp Consul on Kubernetes, based on the [official HashiCorp tutorial](https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-deploy).

## Prerequisites

- Kubernetes cluster (local or cloud-based)
- `kubectl` installed and configured to access your cluster
- `helm` installed (v3.x)

## Installation

You can install Consul using the provided script:

```bash
# Make the script executable
chmod +x install-consul.sh

# Run the installation script
./install-consul.sh
```

### Customization

You can customize the installation by setting environment variables:

```bash
# Change the namespace
NAMESPACE=my-consul ./install-consul.sh

# Change the release name
RELEASE_NAME=my-consul ./install-consul.sh

# Use a custom values file
VALUES_FILE=path/to/my-values.yaml ./install-consul.sh
```

## Accessing Consul

After installation, you can access the Consul UI by using port forwarding:

```bash
kubectl port-forward svc/consul-ui -n consul 8500:80
```

Then open your browser and go to http://localhost:8500

## Getting the ACL Bootstrap Token

If ACLs are enabled, you can retrieve the bootstrap token with:

```bash
kubectl get secret -n consul consul-bootstrap-acl-token -o jsonpath="{.data.token}" | base64 -d
```

## Verifying the Installation

Check that all pods are running:

```bash
kubectl get pods -n consul
```

## Uninstalling Consul

To uninstall Consul:

```bash
helm uninstall consul -n consul
```

## Reference

- [Official HashiCorp Tutorial](https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-deploy)
- [HashiCorp Consul Helm Chart](https://github.com/hashicorp/consul-helm)
