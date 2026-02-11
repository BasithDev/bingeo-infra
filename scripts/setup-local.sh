#!/bin/bash

# Bingeo Local Setup Script
# Run this once to prepare your local k3s environment

set -e

BOLD='\033[1m'
GREEN='\033[32m'
CYAN='\033[36m'
RESET='\033[0m'

echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║              Bingeo Local Environment Setup                ║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# Check prerequisites
echo -e "${CYAN}Checking prerequisites...${RESET}"

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
fi
echo "✅ kubectl"

if ! command -v skaffold &> /dev/null; then
    echo "❌ skaffold not found. Installing..."
    curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
    chmod +x skaffold
    sudo mv skaffold /usr/local/bin/
fi
echo "✅ skaffold"

if ! command -v docker &> /dev/null; then
    echo "❌ docker not found. Please install docker."
    exit 1
fi
echo "✅ docker"

# Check k3s
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Kubernetes cluster not accessible. Is k3s running?"
    exit 1
fi
echo "✅ k3s cluster accessible"

# Install Envoy Gateway (if not already installed)
echo ""
echo -e "${CYAN}Checking Envoy Gateway...${RESET}"
if ! kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
    echo "Installing Gateway API CRDs..."
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml
    
    echo "Installing Envoy Gateway..."
    helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.0.0 -n envoy-gateway-system --create-namespace
    
    echo "Waiting for Envoy Gateway to be ready..."
    kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
fi
echo "✅ Envoy Gateway installed"

# Create namespaces
echo ""
echo -e "${CYAN}Creating namespaces...${RESET}"
kubectl apply -f ./k8s/base/namespaces.yaml
echo "✅ Namespaces created"

# Initialize submodules
echo ""
echo -e "${CYAN}Initializing submodules...${RESET}"
git submodule update --init --recursive || echo "⚠️  No submodules configured yet"

echo ""
echo -e "${GREEN}${BOLD}Setup complete!${RESET}"
echo ""
echo "Next steps:"
echo "  make help           # See available commands"
echo "  make identity       # Run identity service"
echo "  make full           # Run all services"
echo "  make full-obs       # Run all + observability"
