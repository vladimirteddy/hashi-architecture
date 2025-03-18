# Kubernetes, Consul, and Traefik Implementation Guide

This guide provides a step-by-step approach to implementing the architecture described in the README.md file, with **Consul inside Kubernetes** and **Traefik outside Kubernetes**.

## Prerequisites

- Kubernetes cluster (EKS, GKE, AKS, or self-managed)
- `kubectl` configured to access your cluster
- Helm 3.x installed
- A Linux host for Traefik (Ubuntu 22.04 recommended)
- Basic understanding of Kubernetes, service mesh, and API gateway concepts
- consul >= 1.16.0 CLI (optional but recommended)
- consul-k8s >= 1.2.0 CLI (optional but recommended)

## Step 1: Set Up Your Kubernetes Cluster

If you don't already have a Kubernetes cluster, you'll need to create one:

```bash
# For AWS EKS
eksctl create cluster --name hashi-traefik-cluster --region us-west-2 --nodes 3

# For GCP GKE
gcloud container clusters create hashi-traefik-cluster --num-nodes=3

# For Azure AKS
az aks create --resource-group myResourceGroup --name hashi-traefik-cluster --node-count 3

# For local development with kind
kind create cluster --name hashi-traefik-demo
```

Verify your cluster is running:

```bash
kubectl get nodes
```

## Step 2: Install Consul on Kubernetes

### Option 1: Install Consul using Helm (Recommended for Production)

Create a dedicated namespace for Consul:

```bash
kubectl create namespace consul
```

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
  image: "hashicorp/consul:1.16.0"  # Specify the latest stable version
  acls:
    manageSystemACLs: true
    tokenReplication: true
  tls:
    enabled: true
    enableAutoEncrypt: true
  metrics:
    enabled: true
    enableAgentMetrics: true
  transparentProxy:
    defaultEnabled: true

server:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 100Mi
    limits:
      cpu: 200m
      memory: 200Mi

client:
  enabled: true
  grpc: true
  resources:
    requests:
      cpu: 100m
      memory: 100Mi
    limits:
      cpu: 200m
      memory: 200Mi

connectInject:
  enabled: true
  metrics:
    defaultEnabled: true
  transparentProxy:
    defaultEnabled: true

controller:
  enabled: true

ui:
  enabled: true
  service:
    type: LoadBalancer
  metrics:
    enabled: true
    provider: "prometheus"

syncCatalog:
  enabled: true
  default: true  # Register services automatically
  toConsul: true
  toK8S: true
EOF

# Install Consul
helm install consul hashicorp/consul \
  --namespace consul \
  --values consul-values.yaml
```

### Option 2: Install Consul using the Consul K8s CLI (Simpler Experience)

If you have the `consul-k8s` CLI installed, you can use it for a more streamlined installation:

```bash
# Create a default configuration and install Consul
consul-k8s install -auto-approve -set global.name=consul -namespace consul
```

### Verify Consul Installation

Wait for all Consul pods to become ready:

```bash
kubectl wait --for=condition=Ready pod --all -n consul --timeout=300s
```

Verify Consul is running:

```bash
kubectl get pods -n consul
kubectl get svc -n consul
```

Set up environment variables for Consul access:

```bash
# Get the Consul UI address
export CONSUL_HTTP_ADDR=$(kubectl get service consul-ui -n consul -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$CONSUL_HTTP_ADDR" ]; then
  # If LoadBalancer has no external IP, use port forwarding
  echo "No external IP found, you'll need to use port forwarding to access the Consul UI:"
  echo "kubectl port-forward svc/consul-ui -n consul 8500:80 --address 0.0.0.0"
  export CONSUL_HTTP_ADDR="localhost:8500"
fi

# Get bootstrap token for authentication
export CONSUL_HTTP_TOKEN=$(kubectl get secrets consul-bootstrap-acl-token -n consul -o jsonpath='{.data.token}' | base64 -d)
echo "Consul UI is available at: http://${CONSUL_HTTP_ADDR}"
echo "Bootstrap ACL Token: ${CONSUL_HTTP_TOKEN}"

# Configure local Consul CLI to communicate with the Consul server
export CONSUL_HTTP_SSL=true
export CONSUL_TLS_SERVER_NAME="server.dc1.consul"
export CONSUL_CACERT=$(kubectl get secret consul-ca-cert -n consul -o jsonpath="{.data['tls\.crt']}" | base64 -d)
```

## Step 3: Install Traefik Outside Kubernetes

This step deploys Traefik as an external API Gateway on a separate host machine.

### 3.1 Set Up External Traefik

On your Linux host (not within Kubernetes), run:

```bash
# Make the script executable
chmod +x setup-external-traefik.sh

# Run the script with sudo
sudo ./setup-external-traefik.sh
```

The script will:

- Install Traefik binary
- Create necessary directories and configuration files
- Set up Traefik as a systemd service
- Configure basic routing for microservices

For detailed implementation steps and the setup script, see [traefik-external-setup.md](traefik-external-setup.md).

### 3.2 Configure Traefik for Consul Integration

Update Traefik's configuration to leverage Consul's service discovery:

```bash
# Create or update Traefik's static configuration
sudo tee /etc/traefik/traefik.yaml <<EOF
# Traefik static configuration file
global:
  checkNewVersion: true
  sendAnonymousUsage: false

# Enable API and Dashboard
api:
  dashboard: true
  insecure: true  # For production, set to false and use HTTPS

# Entry points configuration
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
  traefik:
    address: ":8080"  # Dashboard port

# Configure providers
providers:
  file:
    directory: "/etc/traefik/dynamic"
    watch: true
  consulCatalog:
    prefix: "traefik"
    exposedByDefault: false
    endpoint:
      address: "http://${CONSUL_HTTP_ADDR}"
      token: "${CONSUL_HTTP_TOKEN}"
    connectAware: true
    connectByDefault: false

# Access logs
accessLog:
  filePath: "/var/log/traefik/access.log"

# Configure let's encrypt
certificatesResolvers:
  letsencrypt:
    acme:
      email: "admin@example.com"  # Change to your email
      storage: "/etc/traefik/acme.json"
      httpChallenge:
        entryPoint: web
EOF

# Restart Traefik to apply changes
sudo systemctl restart traefik
```

### 3.3 Register Traefik in Consul Service Catalog

Register Traefik as an external service in Consul:

```bash
# Create a configuration file for Traefik to be registered in Consul
cat <<EOF | kubectl apply -f -
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceDefaults
metadata:
  name: external-traefik
  namespace: consul
spec:
  protocol: http
EOF

# External service registration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: external-traefik
  namespace: consul
  annotations:
    consul.hashicorp.com/service-name: "external-traefik"
    consul.hashicorp.com/service-sync: "true"
    consul.hashicorp.com/external-source: "Static"
spec:
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector: {} # No selector for external services
  type: ExternalName
  externalName: your-traefik-host.example.com # Replace with your Traefik host
EOF
```

## Step 4: Deploy and Configure Microservices

Create a namespace for your microservices:

```bash
kubectl create namespace microservices
```

Deploy sample microservices with Consul integration and NodePort service for Traefik access:

```bash
# Create a sample microservice deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-a
  namespace: microservices
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
        consul.hashicorp.com/transparent-proxy: "true"
        prometheus.io/scrape: "true"
        prometheus.io/port: "9102"
    spec:
      containers:
      - name: service-a
        image: nginx:latest
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: service-a
  namespace: microservices
spec:
  selector:
    app: service-a
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
  type: NodePort
EOF

# Deploy a second service that communicates with service-a
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-b
  namespace: microservices
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
        consul.hashicorp.com/transparent-proxy: "true"
    spec:
      containers:
      - name: service-b
        image: curlimages/curl
        command: ["/bin/sh", "-c", "while true; do curl -s service-a.microservices.svc.cluster.local; sleep 5; done"]
EOF
```

Configure service defaults in Consul:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceDefaults
metadata:
  name: service-a
  namespace: microservices
spec:
  protocol: http
---
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceDefaults
metadata:
  name: service-b
  namespace: microservices
spec:
  protocol: http
EOF
```

## Step 5: Configure External Traefik for Kubernetes Services

After deploying services, update your external Traefik to route to the Kubernetes services:

```bash
# Get your Kubernetes node IPs
NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
echo "Kubernetes Node IPs: $NODE_IPS"

# Update Traefik dynamic configuration
sudo tee /etc/traefik/dynamic/service-a.yaml <<EOF
http:
  routers:
    service-a:
      entryPoints:
        - "web"
      rule: "Path(\`/service-a\`)"
      service: service-a
      middlewares:
        - strip-prefix

  middlewares:
    strip-prefix:
      stripPrefix:
        prefixes:
          - "/service-a"

  services:
    service-a:
      loadBalancer:
        servers:
          - url: "http://NODE_IP:30080"
EOF

# Replace NODE_IP with your actual Kubernetes node IP
sed -i "s/NODE_IP/$(echo $NODE_IPS | cut -d' ' -f1)/" /etc/traefik/dynamic/service-a.yaml

# Restart Traefik to apply changes
sudo systemctl restart traefik
```

Configure Consul intentions for service communication:

```bash
# Allow traffic from service-b to service-a
cat <<EOF | kubectl apply -f -
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: service-a
  namespace: microservices
spec:
  destination:
    name: service-a
  sources:
    - name: service-b
      action: allow
    - name: external-traefik
      action: allow
EOF
```

## Step 6: Implement Advanced Features

### Traffic Splitting (Canary Releases)

Deploy a new version of service-a:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-a-v2
  namespace: microservices
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
        consul.hashicorp.com/transparent-proxy: "true"
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
  namespace: microservices
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
  namespace: microservices
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
  namespace: microservices
spec:
  splits:
    - weight: 90
      service: service-a
    - weight: 10
      service: service-a-v2
EOF
```

### Rate Limiting with Traefik

Add rate limiting to your API:

```bash
# Configure rate limiting in Traefik
sudo tee /etc/traefik/dynamic/rate-limit.yaml <<EOF
http:
  middlewares:
    rate-limit:
      rateLimit:
        average: 100
        burst: 50
EOF

# Update the service-a route to include rate limiting
sudo sed -i '/service: service-a/a\        middlewares:\n        - strip-prefix\n        - rate-limit' /etc/traefik/dynamic/service-a.yaml

# Restart Traefik to apply changes
sudo systemctl restart traefik
```

### Monitoring and Observability

Install Prometheus and Grafana for monitoring:

```bash
# Create monitoring namespace
kubectl create namespace monitoring

# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus and Grafana
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false
```

Configure Consul metrics collection:

```bash
# Create a ServiceMonitor for Consul
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: consul-metrics
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: consul
  namespaceSelector:
    matchNames:
      - consul
  endpoints:
  - port: http
    path: /v1/agent/metrics
    interval: 15s
    bearerTokenSecret:
      name: consul-bootstrap-acl-token
      key: token
EOF
```

Configure Traefik metrics:

```bash
# Update Traefik configuration to expose metrics
sudo tee -a /etc/traefik/traefik.yaml <<EOF
# Metrics configuration
metrics:
  prometheus:
    entryPoint: traefik
    addServicesLabels: true
    addEntryPointsLabels: true
    buckets:
      - 0.1
      - 0.3
      - 1.2
      - 5.0
EOF

# Restart Traefik to apply changes
sudo systemctl restart traefik
```

## Verification and Testing

Verify Consul services:

```bash
# Use Consul CLI to check services
consul catalog services -token="${CONSUL_HTTP_TOKEN}"

# Check service mesh status
kubectl get pods -n microservices
```

Test external access through Traefik:

```bash
# Test with curl
curl http://your-traefik-host/service-a
```

Verify service mesh communication inside the cluster:

```bash
# Check if service-b can access service-a
kubectl exec -it $(kubectl get pod -l app=service-b -n microservices -o jsonpath='{.items[0].metadata.name}') -n microservices -- curl service-a.microservices.svc.cluster.local
```

Check Consul UI to verify service registration and intentions:

```bash
echo "Consul UI available at: http://${CONSUL_HTTP_ADDR}"
echo "Use token: ${CONSUL_HTTP_TOKEN}"
```

Visit the Traefik dashboard:

```bash
echo "Traefik dashboard available at: http://your-traefik-host:8080/dashboard/"
```

## Security Considerations

### Secure ACL System

Consul's ACL system should be properly configured in production:

```bash
# Create a policy for specific service access
cat <<EOF | kubectl apply -f -
apiVersion: consul.hashicorp.com/v1alpha1
kind: ACLPolicy
metadata:
  name: service-a-policy
  namespace: consul
spec:
  rules: |
    service "service-a" {
      policy = "write"
    }
    service "service-a-sidecar-proxy" {
      policy = "write"
    }
EOF

# Create a token bound to this policy
cat <<EOF | kubectl apply -f -
apiVersion: consul.hashicorp.com/v1alpha1
kind: ACLToken
metadata:
  name: service-a-token
  namespace: consul
spec:
  policies:
    - name: service-a-policy
      namespace: consul
EOF
```

### TLS Configuration

For production environments, configure proper TLS:

```bash
# Update Traefik to use TLS
sudo tee /etc/traefik/dynamic/tls.yaml <<EOF
tls:
  certificates:
    - certFile: /path/to/domain.crt
      keyFile: /path/to/domain.key
EOF
```

## Next Steps

1. **Automate Deployment**: Create CI/CD pipelines for your infrastructure
2. **Infrastructure as Code**: Convert these steps into Terraform modules
3. **Disaster Recovery**: Implement backup and restore procedures
4. **Production Readiness**: Review and enhance security, scaling, and monitoring
5. **Multi-Datacenter**: Configure Consul for multiple datacenters
