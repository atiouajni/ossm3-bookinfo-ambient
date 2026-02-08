#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Complete Cleanup${NC}"
echo -e "${BLUE}  Bookinfo + Istio${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect kubectl or oc
if command -v oc &> /dev/null; then
    KUBECTL="oc"
elif command -v kubectl &> /dev/null; then
    KUBECTL="kubectl"
else
    echo -e "${RED}Error: Neither 'oc' nor 'kubectl' found${NC}"
    exit 1
fi

echo "This will remove:"
echo "  • Bookinfo application"
echo "  • Kiali and Prometheus (observability)"
echo "  • Istio infrastructure (CNI, Control Plane, ZTunnel)"
echo "  • All related namespaces"
echo ""
echo -e "${RED}WARNING: This action cannot be undone!${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Step 1/3: Cleaning up Bookinfo...${NC}"
echo ""

echo "Deleting Bookinfo namespace..."
$KUBECTL delete namespace bookinfo --ignore-not-found=true

echo "Deleting Bookinfo Gateway and Route..."
$KUBECTL delete gateway bookinfo-gateway -n istio-system --ignore-not-found=true
$KUBECTL delete httproute bookinfo -n bookinfo --ignore-not-found=true 2>/dev/null || true

if [ "$KUBECTL" = "oc" ]; then
    oc delete route bookinfo -n istio-system --ignore-not-found=true
fi

echo -e "${GREEN}✓ Bookinfo cleanup complete${NC}"

echo ""
echo -e "${YELLOW}Step 2/3: Cleaning up observability (Kiali, Prometheus)...${NC}"
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

echo -e "${GREEN}✓ Observability cleanup complete${NC}"

echo ""
echo -e "${YELLOW}Step 3/3: Cleaning up Istio...${NC}"
echo ""

echo "Deleting Istio components..."
$KUBECTL delete ztunnel default -n ztunnel --ignore-not-found=true
$KUBECTL delete istio default -n istio-system --ignore-not-found=true
$KUBECTL delete istiocni default -n istio-cni --ignore-not-found=true

echo "Deleting namespaces..."
$KUBECTL delete namespace ztunnel --ignore-not-found=true
$KUBECTL delete namespace istio-system --ignore-not-found=true
$KUBECTL delete namespace istio-cni --ignore-not-found=true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ Complete cleanup finished!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "All components have been removed."
echo ""
