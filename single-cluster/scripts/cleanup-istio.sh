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

echo -e "${YELLOW}=== Cleaning up Istio infrastructure ===${NC}"
echo ""

# Warning
echo -e "${RED}WARNING: This will remove Istio from the cluster!${NC}"
echo "All applications using Istio will be affected."
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

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
echo -e "${GREEN}✓ Istio cleanup complete${NC}"
echo ""
