#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Deploying Waypoint Proxy (L7)${NC}"
echo -e "${BLUE}  Namespace: $NAMESPACE${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Istio is installed
if ! $KUBECTL get istio default -n istio-system &>/dev/null; then
    echo -e "${RED}Error: Istio is not installed${NC}"
    echo "Please install Istio first: ./deploy-istio.sh"
    exit 1
fi

echo -e "${GREEN}✓ Istio is installed${NC}"

# Check if namespace exists
if ! $KUBECTL get namespace $NAMESPACE &>/dev/null; then
    echo -e "${RED}Error: Namespace '$NAMESPACE' does not exist${NC}"
    echo "Please create the namespace first"
    exit 1
fi

echo -e "${GREEN}✓ Namespace '$NAMESPACE' exists${NC}"

# Check if namespace has ambient label
AMBIENT_LABEL=$($KUBECTL get namespace $NAMESPACE -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}' 2>/dev/null)
if [ "$AMBIENT_LABEL" != "ambient" ]; then
    echo -e "${YELLOW}⚠ Warning: Namespace '$NAMESPACE' does not have ambient label${NC}"
    echo "  Adding ambient label..."
    $KUBECTL label namespace $NAMESPACE istio.io/dataplane-mode=ambient --overwrite
    echo -e "${GREEN}✓ Ambient label added${NC}"
fi

echo ""
echo -e "${YELLOW}Deploying Waypoint Proxy...${NC}"

# Create temporary manifest with correct namespace
cat > /tmp/waypoint-$NAMESPACE.yaml <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: waypoint
  namespace: $NAMESPACE
  labels:
    istio.io/waypoint-for: service
spec:
  gatewayClassName: istio-waypoint
  listeners:
  - name: mesh
    port: 15008
    protocol: HBONE
EOF

$KUBECTL apply -f /tmp/waypoint-$NAMESPACE.yaml
rm /tmp/waypoint-$NAMESPACE.yaml

echo "  ✓ Waypoint Gateway created"

echo ""
echo -e "${YELLOW}Waiting for Waypoint to be ready...${NC}"
sleep 5
$KUBECTL wait --for=condition=Programmed gateway/waypoint -n $NAMESPACE --timeout=300s 2>/dev/null || true

# Check if waypoint pod is running
if $KUBECTL get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=waypoint --no-headers 2>/dev/null | grep -q Running; then
    echo -e "${GREEN}✓ Waypoint pod is running${NC}"
else
    echo -e "${YELLOW}⚠ Waypoint pod is not running yet, checking status...${NC}"
    $KUBECTL get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=waypoint
fi

echo ""
echo -e "${YELLOW}Configuring namespace to use waypoint...${NC}"
$KUBECTL label namespace $NAMESPACE istio.io/use-waypoint=waypoint --overwrite
echo -e "${GREEN}✓ Namespace labeled to use waypoint${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ Waypoint Proxy deployed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo "Waypoint details:"
$KUBECTL get gateway waypoint -n $NAMESPACE
echo ""
$KUBECTL get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=waypoint

echo ""
echo -e "${BLUE}What is the Waypoint Proxy?${NC}"
echo ""
echo "The Waypoint Proxy is the L7 component of Istio Ambient mode:"
echo "  • Handles advanced traffic management (VirtualServices, DestinationRules)"
echo "  • Enables canary deployments, A/B testing, fault injection"
echo "  • Required for L7 features, optional for L4-only (mTLS)"
echo ""
echo "To learn more:"
echo "  ./explain-waypoint.sh"
echo ""
