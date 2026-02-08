#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Detect kubectl or oc
if command -v oc &> /dev/null; then
    KUBECTL="oc"
elif command -v kubectl &> /dev/null; then
    KUBECTL="kubectl"
else
    echo -e "${RED}Error: Neither 'oc' nor 'kubectl' found${NC}"
    exit 1
fi

echo -e "${YELLOW}=== Cleaning up Kiali and Prometheus ===${NC}"
echo ""

echo "Deleting Kiali..."
$KUBECTL delete kiali kiali -n istio-system --ignore-not-found=true

echo "Deleting Kiali Route..."
if [ "$KUBECTL" = "oc" ]; then
    oc delete route kiali -n istio-system --ignore-not-found=true
fi

echo "Deleting Prometheus..."
$KUBECTL delete deployment prometheus -n istio-system --ignore-not-found=true
$KUBECTL delete service prometheus -n istio-system --ignore-not-found=true
$KUBECTL delete serviceaccount prometheus -n istio-system --ignore-not-found=true
$KUBECTL delete configmap prometheus -n istio-system --ignore-not-found=true
$KUBECTL delete clusterrole prometheus --ignore-not-found=true
$KUBECTL delete clusterrolebinding prometheus --ignore-not-found=true

echo ""
echo -e "${GREEN}✓ Kiali and Prometheus cleanup complete${NC}"
echo ""
echo "Istio infrastructure is still running."
echo "To remove Istio, run: ./cleanup-istio.sh"
echo ""
