#!/bin/bash

# Bingeo - Complete Cluster Cleanup
# Removes ALL resources from k3s and Docker (including togather)
# Run this for a completely fresh start

set -e

BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
CYAN='\033[36m'
YELLOW='\033[33m'
RESET='\033[0m'

echo -e "${BOLD}${RED}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${RED}║          Bingeo - FULL Cluster Cleanup                      ║${RESET}"
echo -e "${BOLD}${RED}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${YELLOW}⚠️  This will remove ALL non-system resources from k3s!${RESET}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Stop any running processes
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[1/7] Stopping running processes...${RESET}"
pkill -f "skaffold" 2>/dev/null || true
pkill -f "kubectl port-forward" 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════
# Delete Gateways, GatewayClasses, HTTPRoutes
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[2/7] Deleting Gateway resources...${RESET}"
kubectl delete gateway --all -A --ignore-not-found 2>/dev/null || true
kubectl delete httproute --all -A --ignore-not-found 2>/dev/null || true
kubectl delete gatewayclass --all --ignore-not-found 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════
# Uninstall all Helm releases
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[3/7] Uninstalling Helm releases...${RESET}"
# Get all helm releases and uninstall them
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  for release in $(helm list -n "$ns" -q 2>/dev/null); do
    echo "  Uninstalling $release from $ns..."
    helm uninstall "$release" -n "$ns" 2>/dev/null || true
  done
done

# ═══════════════════════════════════════════════════════════════════════════
# Delete all non-system namespaces
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[4/7] Deleting non-system namespaces...${RESET}"
SYSTEM_NS="default kube-system kube-public kube-node-lease"
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  if [[ ! " $SYSTEM_NS " =~ " $ns " ]]; then
    echo "  Deleting namespace: $ns"
    kubectl delete ns "$ns" --ignore-not-found --timeout=60s 2>/dev/null || {
      echo "  Force deleting namespace: $ns"
      kubectl delete ns "$ns" --force --grace-period=0 2>/dev/null || true
    }
  fi
done

# ═══════════════════════════════════════════════════════════════════════════
# Clean up cluster-scoped resources
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[5/7] Cleaning cluster-scoped resources...${RESET}"
# Delete ClusterRoles and ClusterRoleBindings (exclude k3s system components)
# Preserve: system:*, admin, edit, view, cluster-admin, local-path-*, metrics-server*, coredns*, traefik*
kubectl get clusterrole -o name | grep -vE "(^clusterrole.rbac.authorization.k8s.io/(system|admin|edit|view|cluster-admin|local-path|metrics-server|coredns|traefik))" | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true
kubectl get clusterrolebinding -o name | grep -vE "(^clusterrolebinding.rbac.authorization.k8s.io/(system|cluster-admin|local-path|metrics-server|coredns|traefik))" | xargs -r kubectl delete --ignore-not-found 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════
# Clean Docker
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[6/7] Cleaning Docker...${RESET}"
if [[ "$1" == "--docker" || "$1" == "-d" ]]; then
  echo "  Stopping all containers..."
  docker stop $(docker ps -aq) 2>/dev/null || true
  echo "  Removing all containers..."
  docker rm $(docker ps -aq) 2>/dev/null || true
  echo "  Pruning system..."
  docker system prune -af --volumes
  echo -e "${GREEN}  ✅ Docker cleaned${RESET}"
else
  echo -e "${YELLOW}  ℹ️  Skipping Docker cleanup (use --docker or -d flag to include)${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Verify
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[7/7] Verifying cleanup...${RESET}"
echo ""
echo "Remaining namespaces:"
kubectl get ns
echo ""
echo "Helm releases:"
helm list -A 2>/dev/null || echo "None"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Done
# ═══════════════════════════════════════════════════════════════════════════

echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║              Cleanup Complete! ✅                           ║${RESET}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "Next: Run ${BOLD}make setup${RESET} to set up Bingeo environment"
echo ""
