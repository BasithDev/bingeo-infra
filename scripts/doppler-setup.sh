#!/bin/bash

# Doppler Secrets Setup for Bingeo
# Interactive script to configure Doppler Kubernetes integration

set -e

BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
CYAN='\033[36m'  
YELLOW='\033[33m'
RESET='\033[0m'

DOPPLER_NS="doppler-operator-system"

echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║         Doppler Secrets Manager Setup                      ║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""

# Check if Doppler operator is installed
if ! kubectl get deployment doppler-operator-controller-manager -n "$DOPPLER_NS" &> /dev/null; then
  echo -e "${RED}❌ Doppler Operator not found. Run 'make setup' first.${RESET}"
  exit 1
fi

# Menu
echo -e "${CYAN}What would you like to do?${RESET}"
echo ""
echo "  1) Setup Doppler Service Token (one-time)"
echo "  2) Create DopplerSecret for a service"
echo "  3) Check Doppler sync status"
echo "  4) Troubleshoot Doppler issues"
echo "  5) Exit"
echo ""
read -p "Enter choice (1-5): " choice

case $choice in
  1)
    echo ""
    echo -e "${CYAN}=== Doppler Service Token Setup ===${RESET}"
    echo ""
    echo -e "${YELLOW}Instructions:${RESET}"
    echo "  1. Go to: https://dashboard.doppler.com/workplace/{your-workplace}/service_tokens"
    echo "  2. Create a Service Token with access to all projects"
    echo "  3. Copy the token (starts with 'dp.st.dev.' or 'dp.st.prd.')"
    echo ""
    read -sp "Enter Doppler Service Token: " service_token
    echo ""
    
    if [ -z "$service_token" ]; then
      echo -e "${RED}❌ Token cannot be empty${RESET}"
      exit 1
    fi
    
    # Create the token secret
    kubectl create secret generic doppler-token-secret \
      -n "$DOPPLER_NS" \
      --from-literal=serviceToken="$service_token" \
      --dry-run=client -o yaml | kubectl apply -f -
    
    echo -e "${GREEN}✅ Doppler token secret created${RESET}"
    echo ""
    echo -e "${YELLOW}Next: Create DopplerSecrets for your services${RESET}"
    echo -e "   Run: ${BOLD}make doppler-setup${RESET} and select option 2"
    ;;
    
  2)
    echo ""
    echo -e "${CYAN}=== Create DopplerSecret ===${RESET}"
    echo ""
    
    # Check if token secret exists
    if ! kubectl get secret doppler-token-secret -n "$DOPPLER_NS" &> /dev/null; then
      echo -e "${RED}❌ Doppler token secret not found. Run option 1 first.${RESET}"
      exit 1
    fi
    
    echo "Available services:"
    echo "  1) identity-service"
    echo "  2) payment-service"
    echo "  3) content-service"
    echo "  4) streaming-service"
    echo "  5) Custom service"
    echo ""
    read -p "Select service (1-5): " service_choice
    
    case $service_choice in
      1) SERVICE_NAME="identity-service"; DOPPLER_PROJECT="bingeo-identity" ;;
      2) SERVICE_NAME="payment-service"; DOPPLER_PROJECT="bingeo-payment" ;;
      3) SERVICE_NAME="content-service"; DOPPLER_PROJECT="bingeo-content" ;;
      4) SERVICE_NAME="streaming-service"; DOPPLER_PROJECT="bingeo-streaming" ;;
      5) 
        read -p "Enter Kubernetes service name: " SERVICE_NAME
        read -p "Enter Doppler project name: " DOPPLER_PROJECT
        ;;
      *)
        echo -e "${RED}❌ Invalid choice${RESET}"
        exit 1
        ;;
    esac
    
    echo ""
    read -p "Enter Doppler config [dev]: " DOPPLER_CONFIG
    DOPPLER_CONFIG=${DOPPLER_CONFIG:-dev}
    
    # Create DopplerSecret YAML
    cat <<EOF | kubectl apply -f -
apiVersion: secrets.doppler.com/v1alpha1
kind: DopplerSecret
metadata:
  name: ${SERVICE_NAME}-doppler-secret
  namespace: ${DOPPLER_NS}
spec:
  tokenSecret:
    name: doppler-token-secret
  project: ${DOPPLER_PROJECT}
  config: ${DOPPLER_CONFIG}
  managedSecret:
    name: ${SERVICE_NAME}-secrets
    namespace: bingeo-app
EOF
    
    echo ""
    echo -e "${GREEN}✅ DopplerSecret created for ${SERVICE_NAME}${RESET}"
    echo ""
    echo -e "${YELLOW}Secrets will sync to: bingeo-app/${SERVICE_NAME}-secrets${RESET}"
    echo ""
    echo -e "${CYAN}Checking sync status...${RESET}"
    sleep 2
    kubectl get dopplersecrets ${SERVICE_NAME}-doppler-secret -n "$DOPPLER_NS" -o yaml | grep -A 10 "status:"
    ;;
    
  3)
    echo ""
    echo -e "${CYAN}=== Doppler Sync Status ===${RESET}"
    echo ""
    
    echo -e "${BOLD}DopplerSecrets:${RESET}"
    kubectl get dopplersecrets -n "$DOPPLER_NS" 2>/dev/null || echo "  No DopplerSecrets found"
    echo ""
    
    echo -e "${BOLD}Managed Secrets (synced from Doppler):${RESET}"
    kubectl get secrets -n bingeo-app | grep -E "doppler|secrets" || echo "  No managed secrets found"
    echo ""
    
    echo -e "${BOLD}Doppler Operator Logs:${RESET}"
    kubectl logs -n "$DOPPLER_NS" deployment/doppler-operator-controller-manager --tail=20 2>/dev/null || echo "  Could not fetch logs"
    ;;
    
  4)
    echo ""
    echo -e "${CYAN}=== Doppler Troubleshooting ===${RESET}"
    echo ""
    
    echo -e "${BOLD}1. Checking Doppler Operator:${RESET}"
    kubectl get pods -n "$DOPPLER_NS"
    echo ""
    
    echo -e "${BOLD}2. Checking Doppler Token Secret:${RESET}"
    if kubectl get secret doppler-token-secret -n "$DOPPLER_NS" &> /dev/null; then
      echo -e "${GREEN}   ✅ Token secret exists${RESET}"
    else
      echo -e "${RED}   ❌ Token secret not found. Run option 1.${RESET}"
    fi
    echo ""
    
    echo -e "${BOLD}3. Checking DopplerSecret resources:${RESET}"
    kubectl get dopplersecrets -n "$DOPPLER_NS" -o yaml 2>/dev/null | grep -E "name:|conditions:" || echo "  No DopplerSecrets configured"
    echo ""
    
    echo -e "${BOLD}4. Operator logs (errors):${RESET}"
    kubectl logs -n "$DOPPLER_NS" deployment/doppler-operator-controller-manager --tail=50 2>/dev/null | grep -i "error\|fail" || echo "  No errors found"
    ;;
    
  5)
    echo -e "${CYAN}Exiting...${RESET}"
    exit 0
    ;;
    
  *)
    echo -e "${RED}❌ Invalid choice${RESET}"
    exit 1
    ;;
esac
