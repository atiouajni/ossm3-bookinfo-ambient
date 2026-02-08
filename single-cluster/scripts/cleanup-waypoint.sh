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

# Get namespace from parameter or default to bookinfo
NAMESPACE=${1:-bookinfo}

echo -e "${YELLOW}=== Cleaning up Waypoint Proxy ===${NC}"
echo -e "${YELLOW}Namespace: $NAMESPACE${NC}"
echo ""

# Remove waypoint label from namespace
echo "Removing waypoint label from namespace..."
$KUBECTL label namespace $NAMESPACE istio.io/use-waypoint- --ignore-not-found=true 2>/dev/null || true

# Delete waypoint gateway
echo "Deleting Waypoint Gateway..."
$KUBECTL delete gateway waypoint -n $NAMESPACE --ignore-not-found=true

echo ""
echo -e "${GREEN}✓ Waypoint cleanup complete${NC}"
echo ""
echo "Note: This only removes the L7 waypoint proxy."
echo "L4 traffic (mTLS via ZTunnel) continues to work."
echo "VirtualServices and DestinationRules will be ignored without waypoint."
echo ""
