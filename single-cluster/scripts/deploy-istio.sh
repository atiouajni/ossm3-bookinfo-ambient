#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Istio Ambient Mode Deployment${NC}"
echo -e "${BLUE}  OpenShift Service Mesh 3${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect kubectl or oc
if command -v oc &> /dev/null; then
    KUBECTL="oc"
    echo -e "${GREEN}Using OpenShift CLI (oc)${NC}"
elif command -v kubectl &> /dev/null; then
    KUBECTL="kubectl"
    echo -e "${GREEN}Using kubectl${NC}"
else
    echo -e "${RED}Error: Neither 'oc' nor 'kubectl' found${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}=== Step 1/6: Checking Service Mesh Operator ===${NC}"
if ! $KUBECTL get csv -n openshift-operators 2>/dev/null | grep -i servicemesh | grep -q -E 'v3|3\.'; then
    echo -e "${RED}✗ Service Mesh Operator 3 is not installed!${NC}"
    echo ""
    echo "Please install manually via OpenShift Console:"
    echo "  Operators → OperatorHub → 'OpenShift Service Mesh' → Install"
    exit 1
else
    echo -e "${GREEN}✓ Service Mesh Operator 3 installed${NC}"
    OPERATOR_VERSION=$($KUBECTL get csv -n openshift-operators 2>/dev/null | grep -i servicemesh | awk '{print $1}')
    echo "  Version: $OPERATOR_VERSION"
fi

echo ""
echo -e "${YELLOW}=== Step 2/6: Creating namespaces ===${NC}"
$KUBECTL create namespace istio-system --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL create namespace istio-cni --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL create namespace ztunnel --dry-run=client -o yaml | $KUBECTL apply -f -
echo -e "${GREEN}✓ Namespaces created${NC}"

echo ""
echo -e "${YELLOW}=== Step 3/6: Checking Gateway API CRDs ===${NC}"
if $KUBECTL get crd gatewayclasses.gateway.networking.k8s.io &>/dev/null; then
    echo -e "${GREEN}✓ Gateway API CRDs already installed${NC}"
    GATEWAY_API_VERSION=$($KUBECTL get crd gatewayclasses.gateway.networking.k8s.io -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
    if [ -n "$GATEWAY_API_VERSION" ]; then
        echo "  API Version: $GATEWAY_API_VERSION"
    fi
else
    echo "Installing Gateway API CRDs v1.2.0..."
    $KUBECTL apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
    echo -e "${GREEN}✓ Gateway API CRDs installed${NC}"
fi

echo ""
echo -e "${YELLOW}=== Step 4/6: Deploying Istio CNI ===${NC}"
$KUBECTL apply -f "${PROJECT_DIR}/manifests/istio-cni.yaml"
echo -e "${GREEN}✓ Istio CNI deployed${NC}"

echo ""
echo -e "${YELLOW}=== Step 5/6: Deploying Istio Control Plane ===${NC}"
$KUBECTL apply -f "${PROJECT_DIR}/manifests/istio.yaml"
echo -e "${GREEN}✓ Istio Control Plane deployed${NC}"

echo ""
echo -e "${YELLOW}=== Step 6/6: Deploying ZTunnel ===${NC}"
$KUBECTL apply -f "${PROJECT_DIR}/manifests/ztunnel.yaml"
echo -e "${GREEN}✓ ZTunnel deployed${NC}"

echo ""
echo -e "${YELLOW}Waiting for Istio to be ready...${NC}"
$KUBECTL wait --for=condition=Ready pods -l app=istiod -n istio-system --timeout=300s
echo -e "${GREEN}✓ Istio is ready${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ Istio Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Display status
echo -e "${YELLOW}=== Deployment Status ===${NC}"
echo ""
echo "Istio components:"
$KUBECTL get pods -n istio-system
echo ""
echo "Istio CNI:"
$KUBECTL get pods -n istio-cni
echo ""
echo "ZTunnel:"
$KUBECTL get pods -n ztunnel
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Istio is ready for applications!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Deploy your application with ambient mode"
echo "  2. Or deploy the Bookinfo demo:"
echo "     ./deploy-bookinfo.sh"
echo ""
