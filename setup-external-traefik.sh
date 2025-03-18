#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up Traefik as an external API Gateway${NC}"

# Create directories
echo -e "${GREEN}Creating Traefik directories...${NC}"
sudo mkdir -p /etc/traefik
sudo mkdir -p /etc/traefik/dynamic
sudo mkdir -p /var/log/traefik

# Install Traefik
echo -e "${GREEN}Installing Traefik...${NC}"
TRAEFIK_VERSION="v2.10.4"  # Update with the latest version as needed
wget https://github.com/traefik/traefik/releases/download/${TRAEFIK_VERSION}/traefik_${TRAEFIK_VERSION}_linux_amd64.tar.gz
tar -zxvf traefik_${TRAEFIK_VERSION}_linux_amd64.tar.gz
sudo mv traefik /usr/local/bin/
rm traefik_${TRAEFIK_VERSION}_linux_amd64.tar.gz

# Create Traefik user
echo -e "${GREEN}Creating Traefik user...${NC}"
sudo useradd -r -s /bin/false traefik || echo "User traefik already exists"

# Set ownership
sudo chown -R traefik:traefik /etc/traefik
sudo chown -R traefik:traefik /var/log/traefik

# Create static configuration file
echo -e "${GREEN}Creating Traefik configuration...${NC}"
cat <<EOF | sudo tee /etc/traefik/traefik.yaml
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
  kubernetes:
    endpoint: "https://kubernetes.default.svc"
    token: "/var/run/secrets/kubernetes.io/serviceaccount/token"
    namespaces:
      - "auth-system"  # Namespace for go-authentication
    labelSelector: "app=go-authentication"
  consulCatalog:
    prefix: "traefik"
    exposedByDefault: false
    endpoint:
      address: "http://localhost:8500"  # Consul address - adjust as needed
      token: ""  # Consul token if ACLs are enabled

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

# Create dynamic configuration for go-authentication service
echo -e "${GREEN}Creating dynamic configuration for go-authentication...${NC}"
cat <<EOF | sudo tee /etc/traefik/dynamic/go-authentication.yaml
http:
  routers:
    go-authentication:
      entryPoints:
        - "web"
      rule: "Path(\`/auth\`)"
      service: go-authentication
      middlewares:
        - auth-strip-prefix
        - auth-rate-limit

  middlewares:
    auth-strip-prefix:
      stripPrefix:
        prefixes:
          - "/auth"
    auth-rate-limit:
      rateLimit:
        average: 100
        burst: 50

  services:
    go-authentication:
      loadBalancer:
        servers:
          - url: "http://KUBERNETES_NODE_IP:NODEPORT_OR_PORT"  # This will be configured later
EOF

# Create systemd service file
echo -e "${GREEN}Creating systemd service...${NC}"
cat <<EOF | sudo tee /etc/systemd/system/traefik.service
[Unit]
Description=Traefik API Gateway
Documentation=https://doc.traefik.io/traefik/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=traefik
Group=traefik
ExecStart=/usr/local/bin/traefik --configfile=/etc/traefik/traefik.yaml
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Traefik
echo -e "${GREEN}Starting Traefik service...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable traefik
sudo systemctl start traefik

# Display status and next steps
echo -e "${GREEN}Traefik external API Gateway installed successfully!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Expose your go-authentication service with NodePort or LoadBalancer type"
echo "2. Update the dynamic configuration at /etc/traefik/dynamic/go-authentication.yaml with the correct service URL"
echo "3. Restart Traefik with: sudo systemctl restart traefik"
echo ""
echo "Traefik dashboard available at: http://localhost:8080/dashboard/"
echo "Access go-authentication at: http://localhost/auth (after configuration)" 