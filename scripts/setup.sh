#!/bin/bash

# Bingeo - Full Environment Setup
# Sets up k3s with Envoy Gateway, namespaces, and prerequisites
# Pattern: Same as togather-infra

set -e

BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
CYAN='\033[36m'  
YELLOW='\033[33m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/.."

# Bingeo-specific naming
HELM_RELEASE_NAME="bingeo-eg"
ENVOY_NS="bingeo-envoy-gateway"
APP_NS="bingeo-app"
OBS_NS="bingeo-obs"

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

echo -e "${CYAN}[1/6] Checking prerequisites...${RESET}"
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
# Gateway API CRDs
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[2/6] Installing Gateway API CRDs...${RESET}"
if ! kubectl get crd grpcroutes.gateway.networking.k8s.io &> /dev/null; then
  # Use experimental CRDs (includes GRPCRoute needed by Envoy Gateway)
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/experimental-install.yaml
  echo -e "${GREEN}✅ Gateway API CRDs installed${RESET}"
else
  echo -e "${YELLOW}ℹ️  Gateway API CRDs already installed${RESET}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Bingeo Namespaces
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[3/6] Creating Bingeo namespaces...${RESET}"
kubectl create ns "$ENVOY_NS" 2>/dev/null || echo "  $ENVOY_NS already exists"
kubectl create ns "$APP_NS" 2>/dev/null || echo "  $APP_NS already exists"
kubectl create ns "$OBS_NS" 2>/dev/null || echo "  $OBS_NS already exists"
echo -e "${GREEN}✅ Namespaces created${RESET}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Envoy Gateway Controller (in bingeo-envoy-gateway namespace)
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[4/6] Installing Envoy Gateway Controller...${RESET}"
if ! helm list -n "$ENVOY_NS" 2>/dev/null | grep -q "$HELM_RELEASE_NAME"; then
  helm install "$HELM_RELEASE_NAME" oci://docker.io/envoyproxy/gateway-helm \
    --version v1.0.0 \
    -n "$ENVOY_NS" \
    --wait --timeout 5m
  echo -e "${GREEN}✅ Envoy Gateway Controller installed${RESET}"
else
  echo -e "${YELLOW}ℹ️  Envoy Gateway already installed${RESET}"
fi

# Wait for Envoy Gateway to be ready
echo -e "${CYAN}   Waiting for controller to be ready...${RESET}"
kubectl wait --timeout=180s -n "$ENVOY_NS" deployment/envoy-gateway --for=condition=Available 2>/dev/null || {
  echo -e "${YELLOW}⚠️  Timeout waiting for Envoy Gateway, checking status...${RESET}"
  kubectl get pods -n "$ENVOY_NS"
}
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# GatewayClass & Gateway
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[5/6] Creating GatewayClass & Gateway...${RESET}"
kubectl apply -f "$INFRA_DIR/k8s/manual/envoy-gateway/"
echo -e "${GREEN}✅ Gateway resources created${RESET}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Verify
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[6/6] Verifying setup...${RESET}"
echo ""
echo -e "${BOLD}Namespaces:${RESET}"
kubectl get ns | grep bingeo || echo "None"
echo ""
echo -e "${BOLD}Envoy Gateway Pods:${RESET}"
kubectl get pods -n "$ENVOY_NS" 2>/dev/null || echo "None"
echo ""
echo -e "${BOLD}GatewayClass:${RESET}"
kubectl get gatewayclass 2>/dev/null || echo "None"
echo ""
echo -e "${BOLD}Gateway:${RESET}"
kubectl get gateway -A 2>/dev/null || echo "None"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Done!
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║              Setup Complete! 🚀                             ║${RESET}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "Next steps:"
echo -e "  ${BOLD}make identity${RESET}     - Run identity service only"
echo -e "  ${BOLD}make full${RESET}         - Run all services"
echo -e "  ${BOLD}make full-obs${RESET}     - Run all + observability (Prometheus, Loki, Tempo, Grafana)"
echo ""
