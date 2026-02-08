#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Deploying Kiali for Observability${NC}"
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

# Check if Istio is installed
echo -e "${YELLOW}Step 1/5: Checking prerequisites...${NC}"
if ! $KUBECTL get namespace istio-system &>/dev/null; then
    echo -e "${RED}Error: Istio is not installed${NC}"
    echo "Please install Istio first: ./deploy-istio.sh"
    exit 1
fi

if ! $KUBECTL get istio default -n istio-system &>/dev/null; then
    echo -e "${RED}Error: Istio Control Plane not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Istio is installed${NC}"
echo ""

# Check if Kiali Operator is installed
echo -e "${YELLOW}Step 2/5: Checking Kiali Operator...${NC}"
if ! $KUBECTL get crd kialis.kiali.io &>/dev/null; then
    echo -e "${YELLOW}Warning: Kiali Operator not found${NC}"
    echo ""
    echo "Kiali Operator must be installed from OperatorHub:"
    echo "  1. OpenShift Console → Operators → OperatorHub"
    echo "  2. Search for 'Kiali'"
    echo "  3. Install the Kiali Operator"
    echo "  4. Wait for installation to complete"
    echo ""
    echo "Or install via CLI:"
    echo ""
    cat <<'EOF'
cat <<YAML | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-operators
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kiali
  namespace: openshift-operators
spec:
  channel: stable
  name: kiali-ossm
  source: redhat-operators
  sourceNamespace: openshift-marketplace
YAML
EOF
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Kiali Operator is installed${NC}"
echo ""

# Deploy Prometheus
echo -e "${YELLOW}Step 3/5: Deploying Prometheus...${NC}"
echo "Applying Prometheus manifest..."
$KUBECTL apply -f "$MANIFESTS_DIR/prometheus.yaml"

echo "Waiting for Prometheus to be ready..."
$KUBECTL wait --for=condition=available --timeout=300s deployment/prometheus -n istio-system

echo -e "${GREEN}✓ Prometheus deployed${NC}"
echo ""

# Deploy Kiali
echo -e "${YELLOW}Step 4/5: Deploying Kiali...${NC}"
echo "Applying Kiali manifest..."
$KUBECTL apply -f "$MANIFESTS_DIR/kiali.yaml"

echo "Waiting for Kiali to be ready..."
$KUBECTL wait --for=condition=Successful --timeout=300s kiali/kiali -n istio-system 2>/dev/null || true
sleep 10
$KUBECTL wait --for=condition=available --timeout=300s deployment/kiali -n istio-system

echo -e "${GREEN}✓ Kiali deployed${NC}"
echo ""

# Create Route (OpenShift) or expose service (Kubernetes)
echo -e "${YELLOW}Step 5/5: Configuring access...${NC}"

if [ "$KUBECTL" = "oc" ]; then
    # Create OpenShift Route for Kiali
    if ! oc get route kiali -n istio-system &>/dev/null; then
        oc create route edge kiali \
            --service=kiali \
            --port=20001 \
            -n istio-system
        echo -e "${GREEN}✓ Route created for Kiali${NC}"
    else
        echo -e "${GREEN}✓ Route already exists${NC}"
    fi

    KIALI_URL="https://$(oc get route kiali -n istio-system -o jsonpath='{.spec.host}')"
else
    # For vanilla Kubernetes, use port-forward
    echo "To access Kiali, use port-forward:"
    echo "  kubectl port-forward svc/kiali 20001:20001 -n istio-system"
    KIALI_URL="http://localhost:20001/kiali"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✓ Kiali deployment complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Kiali URL:"
echo -e "${BLUE}$KIALI_URL${NC}"
echo ""
echo "Services deployed in istio-system:"
$KUBECTL get pods -n istio-system | grep -E "kiali|prometheus"
echo ""
echo "Next steps:"
echo "  1. Access Kiali at: $KIALI_URL"
echo "  2. Generate traffic: ./generate-traffic.sh"
echo "  3. Explore the service graph and metrics"
echo ""
