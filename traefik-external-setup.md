# External Traefik Deployment Guide

This document explains how to deploy Traefik as an external API Gateway (outside of Kubernetes) as part of the architecture described in the README.md file.

## Architecture Overview

In this setup:

1. **Traefik API Gateway** runs outside Kubernetes on the host machine
2. **Microservices** (like go-authentication) run inside Kubernetes, exposed via NodePort
3. **Consul** provides service mesh capabilities inside Kubernetes

This approach follows the architecture diagram where Traefik API Gateway is positioned outside the Kubernetes cluster and connects to services inside the cluster.

## Prerequisites

1. A Linux host to run Traefik (Ubuntu 22.04 recommended)
2. Running Kubernetes cluster with Consul installed
3. `kubectl` configured to access your cluster
4. Sudo/root access on the host machine to install Traefik

## Deployment Steps

### Step 1: Set Up External Traefik

Run the provided setup script:

```bash
# Make the script executable
chmod +x architecture/setup-external-traefik.sh

# Run the script with sudo
sudo ./architecture/setup-external-traefik.sh
```

This script will:

- Install Traefik binary
- Create necessary directories and configuration files
- Set up Traefik as a systemd service
- Configure basic routing for microservices

### Step 2: Deploy Services to Kubernetes

When deploying services to Kubernetes, make sure they are exposed with NodePort:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: your-service
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080 # Choose an available port in range 30000-32767
```

### Step 3: Connect External Traefik to Kubernetes Services

After deploying a service, you'll need to update the Traefik configuration to route to it:

1. Create or edit a dynamic configuration file for your service:

```bash
sudo nano /etc/traefik/dynamic/your-service.yaml
```

2. Configure the routing:

```yaml
http:
  routers:
    your-service:
      entryPoints:
        - "web"
      rule: "Path(`/your-service`)"
      service: your-service
      middlewares:
        - strip-prefix

  middlewares:
    strip-prefix:
      stripPrefix:
        prefixes:
          - "/your-service"

  services:
    your-service:
      loadBalancer:
        servers:
          - url: "http://KUBERNETES_NODE_IP:NODEPORT"
```

3. Replace `KUBERNETES_NODE_IP` with one of your Kubernetes node IPs and `NODEPORT` with the nodePort you specified.

4. Restart Traefik to apply the changes:

```bash
sudo systemctl restart traefik
```

## Example: Go-Authentication Service

For the go-authentication service specifically:

1. Deploy the service with NodePort:

   ```bash
   cd go-authentication/k8s
   ./build-and-deploy.sh your-docker-registry
   ```

2. The build script will show you the NodePort and Node IPs to use in your Traefik configuration.

3. Update the go-authentication Traefik configuration file that was created during setup.

## Verifying the Setup

### Check Traefik Status

```bash
sudo systemctl status traefik
```

### Access Traefik Dashboard

Open a browser and navigate to:

```
http://YOUR_HOST_IP:8080/dashboard/
```

### Test a Service

Try accessing an exposed service:

```bash
curl http://YOUR_HOST_IP/service-path
```

## Configuration Options

### TLS/HTTPS

To enable HTTPS:

1. Edit the Traefik configuration:

```bash
sudo nano /etc/traefik/traefik.yaml
```

2. Update the certificatesResolvers section with your email.

3. Update your service's dynamic configuration:

```yaml
routers:
  your-service:
    entryPoints:
      - "websecure"
    rule: "Path(`/your-service`)"
    service: your-service
    middlewares:
      - strip-prefix
    tls:
      certResolver: letsencrypt
```

### High Availability

For high availability:

1. Deploy Traefik on multiple hosts
2. Use a load balancer in front of your Traefik instances
3. Configure Kubernetes with multiple nodes
4. Update Traefik configuration to include all node IPs

## Troubleshooting

### Traefik Can't Connect to Kubernetes Service

1. Verify the NodePort service is running:

   ```bash
   kubectl get svc your-service -n your-namespace
   ```

2. Check if the NodePort is accessible:

   ```bash
   curl http://NODE_IP:NODEPORT/health
   ```

3. Check Traefik logs:
   ```bash
   sudo journalctl -u traefik
   ```

### Dashboard or Routes Not Working

1. Check if Traefik is running:

   ```bash
   sudo systemctl status traefik
   ```

2. Verify your configuration files:

   ```bash
   sudo traefik --configfile=/etc/traefik/traefik.yaml --check
   ```

3. Check for errors in the logs:
   ```bash
   sudo cat /var/log/traefik/access.log
   ```
