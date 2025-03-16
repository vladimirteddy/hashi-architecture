# Kubernetes, Consul, and Kong Implementation Guide

This guide provides a step-by-step approach to implementing the architecture described in the README.md file. It's designed for DevOps engineers who need to deploy and manage this infrastructure.

## Prerequisites

- Kubernetes cluster (EKS, GKE, AKS, or self-managed)
- `kubectl` configured to access your cluster
- Helm 3.x installed
- Basic understanding of Kubernetes, service mesh, and API gateway concepts

## Step 1: Set Up Your Kubernetes Cluster

If you don't already have a Kubernetes cluster, you'll need to create one:

```bash
# For AWS EKS
eksctl create cluster --name hashi-kong-cluster --region us-west-2 --nodes 3

# For GCP GKE
gcloud container clusters create hashi-kong-cluster --num-nodes=3

# For Azure AKS
az aks create --resource-group myResourceGroup --name hashi-kong-cluster --node-count 3

# For local development with kind
kind create cluster --name hashi-kong-demo
```

Verify your cluster is running:

```bash
kubectl get nodes
```

## Step 2: Install Consul on Kubernetes

Deploy Consul using Helm:

```bash
# Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Create values file for Consul
cat <<EOF > consul-values.yaml
global:
  name: consul
  datacenter: kubernetes
  acls:
    manageSystemACLs: true

server:
  replicas: 1

client:
  enabled: true

connectInject:
  enabled: true

ui:
  enabled: true
  service:
    type: LoadBalancer

controller:
  enabled: true
EOF

# Install Consul
helm install consul hashicorp/consul --values consul-values.yaml
```

Verify Consul is running:

```bash
kubectl get pods -l app=consul
kubectl get svc consul-ui
```

Set up environment variables for Consul access:

```bash
export CONSUL_HTTP_ADDR=$(kubectl get service consul-ui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export CONSUL_HTTP_TOKEN=$(kubectl get secrets consul-bootstrap-acl-token -o jsonpath='{.data.token}' | base64 -d)
```

## Step 3: Install Kong Ingress Controller

Deploy Kong using Helm with Consul integration:

```bash
# Add Kong Helm repository
helm repo add kong https://charts.konghq.com
helm repo update

# Set Kong release name
export KONG_RELEASE=kong

# Create values file for Kong with Consul integration
cat <<EOF > kong-values.yaml
ingressController:
  serviceAccount:
    name: \${KONG_RELEASE}-kong-proxy

podAnnotations:
  consul.hashicorp.com/connect-inject: "true"
  consul.hashicorp.com/transparent-proxy-exclude-inbound-ports: "8000,8443"
EOF

# Install Kong
helm install ${KONG_RELEASE} kong/kong --values kong-values.yaml
```

Configure Kong service in Consul:

```bash
# Set HTTP protocol for Kong in Consul
cat <<EOF | kubectl apply -f -
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceDefaults
metadata:
  name: ${KONG_RELEASE}-kong-proxy
spec:
  protocol: http
EOF
```

Verify Kong is running:

```bash
kubectl get pods -l app.kubernetes.io/name=kong
kubectl get svc -l app.kubernetes.io/name=kong
```

## Step 4: Deploy and Configure Microservices

Deploy sample microservices with Consul integration:

```bash
# Create a sample microservice deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-a
spec:
  replicas: 2
  selector:
    matchLabels:
      app: service-a
  template:
    metadata:
      labels:
        app: service-a
      annotations:
        consul.hashicorp.com/connect-inject: "true"
    spec:
      containers:
      - name: service-a
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: service-a
spec:
  selector:
    app: service-a
  ports:
  - port: 80
    targetPort: 80
EOF

# Deploy a second service that communicates with service-a
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-b
spec:
  replicas: 2
  selector:
    matchLabels:
      app: service-b
  template:
    metadata:
      labels:
        app: service-b
      annotations:
        consul.hashicorp.com/connect-inject: "true"
    spec:
      containers:
      - name: service-b
        image: curlimages/curl
        command: ["/bin/sh", "-c", "while true; do curl -s service-a; sleep 5; done"]
EOF
```

Create Kong Ingress for external access:

```bash
# Create an Ingress resource for Kong
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: service-a-ingress
  annotations:
    konghq.com/strip-path: "true"
spec:
  ingressClassName: kong
  rules:
  - http:
      paths:
      - path: /service-a
        pathType: Prefix
        backend:
          service:
            name: service-a
            port:
              number: 80
EOF
```

Configure Consul intentions for service communication:

```bash
# Allow traffic from Kong to service-a
cat <<EOF | kubectl apply -f -
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: service-a-intentions
spec:
  destination:
    name: service-a
  sources:
    - name: ${KONG_RELEASE}-kong-proxy
      action: allow
EOF

# Allow traffic from service-b to service-a
cat <<EOF | kubectl apply -f -
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: service-a-from-b-intentions
spec:
  destination:
    name: service-a
  sources:
    - name: service-b
      action: allow
EOF
```

## Step 5: Implement Advanced Features

### Traffic Splitting (Canary Releases)

Deploy a new version of service-a:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-a-v2
spec:
  replicas: 2
  selector:
    matchLabels:
      app: service-a
      version: v2
  template:
    metadata:
      labels:
        app: service-a
        version: v2
      annotations:
        consul.hashicorp.com/connect-inject: "true"
    spec:
      containers:
      - name: service-a
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: config-volume
        mountPath: /usr/share/nginx/html
      volumes:
      - name: config-volume
        configMap:
          name: nginx-v2-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-v2-config
data:
  index.html: |
    <html>
    <body>
      <h1>Service A - Version 2</h1>
    </body>
    </html>
---
apiVersion: v1
kind: Service
metadata:
  name: service-a-v2
spec:
  selector:
    app: service-a
    version: v2
  ports:
  - port: 80
    targetPort: 80
EOF
```

Configure traffic splitting with Consul:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceSplitter
metadata:
  name: service-a
spec:
  splits:
    - weight: 90
      service: service-a
    - weight: 10
      service: service-a-v2
EOF
```

### Rate Limiting with Kong

Add rate limiting to your API:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: rate-limiting
config:
  minute: 5
  policy: local
plugin: rate-limiting
EOF

# Apply the plugin to your Ingress
kubectl patch ingress service-a-ingress -p '{"metadata":{"annotations":{"konghq.com/plugins":"rate-limiting"}}}'
```

### Monitoring and Observability

Install Prometheus and Grafana:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack
```

Configure Kong to expose metrics:

```bash
# Update Kong values to enable Prometheus plugin
cat <<EOF > kong-prometheus-values.yaml
ingressController:
  serviceAccount:
    name: \${KONG_RELEASE}-kong-proxy

podAnnotations:
  consul.hashicorp.com/connect-inject: "true"
  consul.hashicorp.com/transparent-proxy-exclude-inbound-ports: "8000,8443"
  prometheus.io/scrape: "true"
  prometheus.io/port: "8100"

env:
  nginx_http_metrics: "prometheus"
EOF

# Upgrade Kong installation
helm upgrade ${KONG_RELEASE} kong/kong --values kong-prometheus-values.yaml
```

## Verification and Testing

Test external access through Kong:

```bash
# Get Kong proxy endpoint
export KONG_ENDPOINT=$(kubectl get svc ${KONG_RELEASE}-kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test the API
curl http://${KONG_ENDPOINT}/service-a
```

Verify service mesh communication:

```bash
# Check if service-b can access service-a
kubectl exec -it $(kubectl get pod -l app=service-b -o jsonpath='{.items[0].metadata.name}') -- curl service-a
```

Check Consul UI to verify service registration and intentions:

```bash
echo "Consul UI available at: http://${CONSUL_HTTP_ADDR}:8500"
echo "Use token: ${CONSUL_HTTP_TOKEN}"
```

## Next Steps

1. **Automate Deployment**: Create CI/CD pipelines for your infrastructure
2. **Infrastructure as Code**: Convert these steps into Terraform modules
3. **Disaster Recovery**: Implement backup and restore procedures
4. **Security Hardening**: Review and enhance security configurations
5. **Scaling**: Plan for scaling your services and infrastructure components
