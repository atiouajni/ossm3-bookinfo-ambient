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
echo -e "${BLUE}  Bookinfo Application Deployment${NC}"
echo -e "${BLUE}  Ambient Mode${NC}"
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
echo -e "${YELLOW}=== Step 1/5: Checking Istio installation ===${NC}"

# Check if istio-system namespace exists
if ! $KUBECTL get namespace istio-system &>/dev/null; then
    echo -e "${RED}✗ Istio is not installed (namespace istio-system not found)${NC}"
    echo ""
    echo "Please install Istio first:"
    echo "  ./deploy-istio.sh"
    exit 1
fi

# Check if istiod is running
if ! $KUBECTL get pods -n istio-system -l app=istiod --no-headers 2>/dev/null | grep -q Running; then
    echo -e "${RED}✗ Istiod is not running${NC}"
    echo ""
    echo "Please ensure Istio is properly installed:"
    echo "  ./deploy-istio.sh"
    exit 1
fi

echo -e "${GREEN}✓ Istio is installed and running${NC}"

# Check ZTunnel
if ! $KUBECTL get pods -n ztunnel -l app=ztunnel --no-headers 2>/dev/null | grep -q .; then
    echo -e "${YELLOW}⚠ ZTunnel not found${NC}"
    echo "  Ambient mode may not work properly"
else
    echo -e "${GREEN}✓ ZTunnel is deployed${NC}"
fi

echo ""
echo -e "${YELLOW}=== Step 2/5: Deploying Bookinfo namespace ===${NC}"

# Create namespace with ambient label
$KUBECTL apply -f "${PROJECT_DIR}/bookinfo/namespace.yaml"
echo "  ✓ Namespace created with ambient label"

echo ""
echo -e "${YELLOW}=== Step 3/5: Creating service accounts ===${NC}"

# Create service accounts
$KUBECTL apply -f "${PROJECT_DIR}/bookinfo/serviceaccounts.yaml"
echo "  ✓ Service accounts created"

# Grant SCC permissions for OpenShift
if [ "$KUBECTL" = "oc" ]; then
    echo "  Granting SCC permissions..."
    oc adm policy add-scc-to-user anyuid -z bookinfo-productpage -n bookinfo 2>/dev/null || true
    oc adm policy add-scc-to-user anyuid -z bookinfo-details -n bookinfo 2>/dev/null || true
    oc adm policy add-scc-to-user anyuid -z bookinfo-reviews -n bookinfo 2>/dev/null || true
    oc adm policy add-scc-to-user anyuid -z bookinfo-ratings -n bookinfo 2>/dev/null || true
    echo "  ✓ SCC permissions granted"
fi

echo ""
echo -e "${YELLOW}=== Step 4/5: Deploying Bookinfo services ===${NC}"

# Deploy all Bookinfo services
$KUBECTL apply -f "${PROJECT_DIR}/bookinfo/bookinfo.yaml"
echo "  ✓ Bookinfo services deployed"

echo ""
echo -e "${YELLOW}Waiting for Bookinfo pods to be ready...${NC}"
$KUBECTL wait --for=condition=Ready pods --all -n bookinfo --timeout=300s
echo -e "${GREEN}✓ All Bookinfo pods are ready${NC}"

echo ""
echo -e "${YELLOW}=== Step 5/7: Deploying Waypoint Proxy (Istio L7 Infrastructure) ===${NC}"
echo ""

# Deploy Waypoint proxy using dedicated script
if [ -f "$SCRIPT_DIR/deploy-waypoint.sh" ]; then
    "$SCRIPT_DIR/deploy-waypoint.sh" bookinfo
else
    echo -e "${RED}Error: deploy-waypoint.sh not found${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}=== Step 6/7: Deploying Traffic Management (VirtualServices & DestinationRules) ===${NC}"

# Deploy DestinationRules and VirtualServices
$KUBECTL apply -f "${PROJECT_DIR}/bookinfo/traffic-management.yaml"
echo "  ✓ DestinationRules created for all services"
echo "  ✓ VirtualServices created with traffic distribution:"
echo "    - reviews v1: 33%"
echo "    - reviews v2: 33%"
echo "    - reviews v3: 34%"

echo ""
echo -e "${YELLOW}=== Step 7/7: Deploying Gateway and Route ===${NC}"

# Deploy GatewayClass
$KUBECTL apply -f "${PROJECT_DIR}/manifests/gatewayclass.yaml"
echo "  ✓ GatewayClass deployed"

# Deploy Gateway and HTTPRoute
$KUBECTL apply -f "${PROJECT_DIR}/bookinfo/gateway.yaml"
echo "  ✓ Gateway and HTTPRoute deployed"

# Create OpenShift Route
if [ "$KUBECTL" = "oc" ]; then
    echo ""
    echo "Waiting for Gateway service to be created..."
    sleep 5

    if oc get svc bookinfo-gateway-istio -n istio-system &>/dev/null; then
        oc create route edge bookinfo \
          --service=bookinfo-gateway-istio \
          --port=80 \
          -n istio-system 2>/dev/null || echo "  (Route already exists)"
        echo -e "${GREEN}✓ Route created${NC}"
    else
        echo -e "${YELLOW}⚠ Gateway service not yet created, skipping Route${NC}"
        echo "  You can create it manually later with:"
        echo "  oc create route edge bookinfo --service=bookinfo-gateway-istio --port=80 -n istio-system"
    fi
else
    echo -e "${YELLOW}⚠ Not on OpenShift, skipping Route creation${NC}"
    echo "  Access via LoadBalancer or NodePort"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ Bookinfo Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Display status
echo -e "${YELLOW}=== Deployment Status ===${NC}"
echo ""
echo "Bookinfo pods:"
$KUBECTL get pods -n bookinfo
echo ""
echo "Services:"
$KUBECTL get svc -n bookinfo
echo ""

# Display access URL
if [ "$KUBECTL" = "oc" ]; then
    ROUTE_HOST=$(oc get route bookinfo -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null)
    if [ -n "$ROUTE_HOST" ]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  Application URL${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${BLUE}https://${ROUTE_HOST}/productpage${NC}"
        echo ""
        echo "Test with:"
        echo "  curl https://${ROUTE_HOST}/productpage"
        echo ""
    fi
else
    echo "To access the application:"
    echo "  kubectl port-forward -n bookinfo svc/productpage 9080:9080"
    echo "  Then open: http://localhost:9080/productpage"
    echo ""
fi

echo -e "${YELLOW}To verify ambient mode:${NC}"
echo "  ./preuves-ambient-l4.sh"
echo ""
echo -e "${YELLOW}To clean up Bookinfo:${NC}"
echo "  kubectl delete namespace bookinfo"
echo ""
