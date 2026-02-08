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

echo -e "${YELLOW}=== Cleaning up Bookinfo application ===${NC}"
echo ""

echo "Deleting Bookinfo namespace..."
$KUBECTL delete namespace bookinfo --ignore-not-found=true

echo "Deleting Bookinfo Gateway and Route..."
$KUBECTL delete gateway bookinfo-gateway -n istio-system --ignore-not-found=true
$KUBECTL delete httproute bookinfo -n bookinfo --ignore-not-found=true

if [ "$KUBECTL" = "oc" ]; then
    oc delete route bookinfo -n istio-system --ignore-not-found=true
fi

echo ""
echo -e "${GREEN}✓ Bookinfo cleanup complete${NC}"
echo ""
echo "Istio infrastructure is still running."
echo "To remove Istio, run: ./cleanup-istio.sh"
echo ""
