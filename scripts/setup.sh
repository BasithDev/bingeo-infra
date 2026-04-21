#!/bin/bash

# Bingeo - Full Environment Setup
# Sets up k3s with Envoy Gateway v1.7.2, Doppler Secrets Operator, and prerequisites

set -e

BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
CYAN='\033[36m'  
YELLOW='\033[33m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/.."

# ═══════════════════════════════════════════════════════════════════════════
# Version Configuration (Update these for new releases)
# ═══════════════════════════════════════════════════════════════════════════
ENVOY_GATEWAY_VERSION="v1.7.2"
GATEWAY_API_VERSION="v1.2.1"

# Bingeo-specific naming
HELM_RELEASE_NAME="bingeo-eg"
ENVOY_NS="bingeo-envoy-gateway"
APP_NS="bingeo-app"
OBS_NS="bingeo-obs"
DOPPLER_NS="doppler-operator-system"

echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║              Bingeo - Environment Setup                     ║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Prerequisites Check
# ═══════════════════════════════════════════════════════════════════════════

check_cmd() {
  if ! command -v "$1" &> /dev/null; then
    echo -e "${RED}❌ $1 not found. Please install $1.${RESET}"
    exit 1
  fi
  echo -e "${GREEN}✅ $1${RESET}"
}

echo -e "${CYAN}[1/5] Checking prerequisites...${RESET}"
check_cmd kubectl
check_cmd helm
check_cmd skaffold
check_cmd docker

# Check k3s cluster
if ! kubectl cluster-info &> /dev/null; then
  echo -e "${RED}❌ Kubernetes cluster not accessible. Is k3s running?${RESET}"
  exit 1
fi
echo -e "${GREEN}✅ Kubernetes cluster accessible${RESET}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Gateway API CRDs (v1.2.1)
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[2/7] Installing Gateway API CRDs (v${GATEWAY_API_VERSION})...${RESET}"
if ! kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null; then
  # Use standard CRDs (latest stable includes GRPCRoute)
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml
  echo -e "${GREEN}✅ Gateway API CRDs v${GATEWAY_API_VERSION} installed${RESET}"
else
  CURRENT_VERSION=$(kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' 2>/dev/null || echo "unknown")
  echo -e "${YELLOW}ℹ️  Gateway API CRDs already installed (version: ${CURRENT_VERSION})${RESET}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Bingeo Namespaces
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[3/7] Creating Bingeo namespaces...${RESET}"
kubectl create ns "$ENVOY_NS" 2>/dev/null || echo "  $ENVOY_NS already exists"
kubectl create ns "$APP_NS" 2>/dev/null || echo "  $APP_NS already exists"
kubectl create ns "$OBS_NS" 2>/dev/null || echo "  $OBS_NS already exists"
echo -e "${GREEN}✅ Namespaces created${RESET}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Envoy Gateway Controller v1.7.2
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[4/7] Checking Envoy Gateway Controller...${RESET}"
if kubectl get deployment/envoy-gateway -n "$ENVOY_NS" &> /dev/null && \
   kubectl get pods -n "$ENVOY_NS" | grep -q "Running"; then
  echo -e "${YELLOW}ℹ️  Envoy Gateway Controller already running${RESET}"
  # Check version and offer upgrade
  CURRENT_EG_VERSION=$(helm list -n "$ENVOY_NS" -q | grep -c "$HELM_RELEASE_NAME" && helm get metadata "$HELM_RELEASE_NAME" -n "$ENVOY_NS" 2>/dev/null | grep appVersion | awk '{print $2}' || echo "unknown")
  if [[ "$CURRENT_EG_VERSION" != "$ENVOY_GATEWAY_VERSION" ]]; then
    echo -e "${YELLOW}   Current version: ${CURRENT_EG_VERSION}, Available: ${ENVOY_GATEWAY_VERSION}${RESET}"
    read -p "   Upgrade Envoy Gateway? (y/N): " upgrade_eg
    if [[ "$upgrade_eg" =~ ^[Yy]$ ]]; then
      echo -e "${CYAN}   Upgrading Envoy Gateway to ${ENVOY_GATEWAY_VERSION}...${RESET}"
      helm upgrade "$HELM_RELEASE_NAME" oci://docker.io/envoyproxy/gateway-helm \
        --version ${ENVOY_GATEWAY_VERSION} \
        -n "$ENVOY_NS" \
        --wait --timeout 5m
    fi
  fi
else
  echo -e "${CYAN}   Installing Envoy Gateway ${ENVOY_GATEWAY_VERSION}...${RESET}"
  helm upgrade --install "$HELM_RELEASE_NAME" oci://docker.io/envoyproxy/gateway-helm \
    --version ${ENVOY_GATEWAY_VERSION} \
    -n "$ENVOY_NS" \
    --create-namespace \
    --wait --timeout 5m

  # Wait for Envoy Gateway to be ready
  echo -e "${CYAN}   Waiting for controller to be ready...${RESET}"
  kubectl wait --timeout=180s -n "$ENVOY_NS" deployment/envoy-gateway --for=condition=Available 2>/dev/null || {
    echo -e "${YELLOW}⚠️  Timeout waiting for Envoy Gateway, checking status...${RESET}"
    kubectl get pods -n "$ENVOY_NS"
  }
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# GatewayClass & Gateway
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[5/7] Creating GatewayClass & Gateway...${RESET}"
kubectl apply -f "$INFRA_DIR/k8s/manual/envoy-gateway/"
echo -e "${GREEN}✅ Gateway resources created${RESET}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Doppler Secrets Operator
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[6/7] Checking Doppler Secrets Operator...${RESET}"
if ! kubectl get deployment doppler-operator-controller-manager -n "$DOPPLER_NS" &> /dev/null; then
  echo -e "${CYAN}   Installing Doppler Kubernetes Operator...${RESET}"
  
  # Add Doppler Helm repo
  helm repo add doppler https://helm.doppler.com 2>/dev/null || true
  helm repo update
  
  # Install operator
  helm upgrade --install doppler-operator doppler/doppler-kubernetes-operator \
    -n "$DOPPLER_NS" \
    --create-namespace \
    --wait --timeout 3m
  
  echo -e "${GREEN}✅ Doppler Operator installed${RESET}"
  echo ""
  echo -e "${YELLOW}📋 Next: Configure Doppler secrets:${RESET}"
  echo -e "   1. Get Doppler Service Token from: https://dashboard.doppler.com/workplace/{workplace}/service_tokens"
  echo -e "   2. Run: make doppler-setup${RESET}"
else
  echo -e "${GREEN}✅ Doppler Operator already running${RESET}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Verify
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[7/7] Verifying installation...${RESET}"
echo ""
echo -e "${BOLD}Namespaces:${RESET}"
kubectl get ns | grep -E "bingeo|doppler" || echo "None"
echo ""
echo -e "${BOLD}Envoy Gateway Pods:${RESET}"
kubectl get pods -n "$ENVOY_NS" 2>/dev/null || echo "None"
echo ""
echo -e "${BOLD}Doppler Operator Pods:${RESET}"
kubectl get pods -n "$DOPPLER_NS" 2>/dev/null || echo "None"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Done!
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║              Setup Complete! 🚀                             ║${RESET}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${CYAN}Next steps:${RESET}"
echo ""
echo -e "${BOLD}1. Setup Doppler Secrets:${RESET}"
echo -e "   ${YELLOW}make doppler-setup${RESET}         # Interactive Doppler configuration"
echo -e "   ${YELLOW}make doppler-identity${RESET}      # Create identity-service DopplerSecret"
echo ""
echo -e "${BOLD}2. Start Services:${RESET}"
echo -e "   ${YELLOW}make identity${RESET}              # Run Identity service + base infra"
echo -e "   ${YELLOW}make full${RESET}                # Run all services"
echo -e "   ${YELLOW}make full-obs${RESET}            # Run all services + observability"
echo ""
echo -e "${BOLD}3. Access Services:${RESET}"
echo -e "   ${YELLOW}make ports${RESET}                 # Port-forward gateway + observability"
echo -e "   Gateway:    http://localhost:5000"
echo -e "   Grafana:    http://localhost:3000"
echo -e "   Prometheus: http://localhost:9090"
echo ""
echo -e "${BOLD}4. Troubleshooting:${RESET}"
echo -e "   ${YELLOW}make status${RESET}                # Check cluster status"
echo -e "   ${YELLOW}make doppler-status${RESET}        # Check Doppler sync status"
echo -e "   ${YELLOW}make logs SVC=identity-service${RESET}  # View service logs"
echo ""
