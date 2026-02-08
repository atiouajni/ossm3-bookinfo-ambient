#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Prerequisites Check${NC}"
echo -e "${BLUE}  Bookinfo Single-Cluster Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect kubectl or oc
echo -e "${YELLOW}=== Checking CLI tools ===${NC}"
if command -v oc &> /dev/null; then
    KUBECTL="oc"
    echo -e "${GREEN}✓ OpenShift CLI (oc) found${NC}"
    OC_VERSION=$(oc version 2>/dev/null | grep "Client Version:" | awk '{print $3}')
    echo "  Version: $OC_VERSION"
elif command -v kubectl &> /dev/null; then
    KUBECTL="kubectl"
    echo -e "${GREEN}✓ kubectl found${NC}"
    KUBECTL_VERSION=$(kubectl version --client 2>/dev/null | grep -o 'Client Version: v[0-9.]*' | cut -d' ' -f3)
    echo "  Version: $KUBECTL_VERSION"
else
    echo -e "${RED}✗ Neither 'oc' nor 'kubectl' found${NC}"
    echo "  Please install OpenShift CLI or kubectl"
    ERRORS=$((ERRORS+1))
fi

# Check cluster connectivity
echo ""
echo -e "${YELLOW}=== Checking cluster connectivity ===${NC}"
if $KUBECTL cluster-info &>/dev/null; then
    echo -e "${GREEN}✓ Connected to cluster${NC}"
    CLUSTER_URL=$($KUBECTL cluster-info 2>/dev/null | grep -o 'https://[^[:space:]]*' | head -1)
    echo "  Cluster: $CLUSTER_URL"
else
    echo -e "${RED}✗ Cannot connect to cluster${NC}"
    echo "  Please login to your cluster first"
    echo "  Example: oc login https://api.your-cluster.com:6443"
    ERRORS=$((ERRORS+1))
    exit 1
fi

# Check OpenShift version (if using oc)
if [ "$KUBECTL" = "oc" ]; then
    echo ""
    echo -e "${YELLOW}=== Checking OpenShift version ===${NC}"
    OCP_VERSION=$(oc version 2>/dev/null | grep "Server Version:" | awk '{print $3}')
    if [ -n "$OCP_VERSION" ]; then
        echo -e "${GREEN}✓ OpenShift version: $OCP_VERSION${NC}"
        MAJOR_VERSION=$(echo "$OCP_VERSION" | cut -d. -f1)
        MINOR_VERSION=$(echo "$OCP_VERSION" | cut -d. -f2)
        if [ -n "$MAJOR_VERSION" ] && [ -n "$MINOR_VERSION" ] && \
           [ "$MAJOR_VERSION" -ge 4 ] 2>/dev/null && [ "$MINOR_VERSION" -ge 12 ] 2>/dev/null; then
            echo "  OpenShift 4.12+ detected - compatible"
        else
            echo -e "${RED}✗ OpenShift 4.12+ required for Service Mesh 3${NC}"
            echo "  Current version: $OCP_VERSION"
            ERRORS=$((ERRORS+1))
        fi
    else
        echo -e "${YELLOW}⚠ Could not detect OpenShift version${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
fi

# Check Service Mesh Operator
echo ""
echo -e "${YELLOW}=== Checking Service Mesh Operator ===${NC}"
if $KUBECTL get csv -n openshift-operators 2>/dev/null | grep -i servicemesh | grep -q -E 'v3|3\.'; then
    echo -e "${GREEN}✓ Service Mesh Operator 3 is installed${NC}"
    OPERATOR_VERSION=$($KUBECTL get csv -n openshift-operators 2>/dev/null | grep -i servicemesh | awk '{print $1}')
    echo "  Version: $OPERATOR_VERSION"

    # Check operator status
    OPERATOR_PHASE=$($KUBECTL get csv -n openshift-operators 2>/dev/null | grep -i servicemesh | awk '{print $NF}')
    if [ "$OPERATOR_PHASE" = "Succeeded" ]; then
        echo "  Status: ${GREEN}Succeeded${NC}"
    else
        echo -e "${YELLOW}⚠ Status: $OPERATOR_PHASE${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${RED}✗ Service Mesh Operator 3 is NOT installed${NC}"
    echo ""
    echo "  Please install via OpenShift Console:"
    echo "    1. Operators → OperatorHub"
    echo "    2. Search 'OpenShift Service Mesh'"
    echo "    3. Click Install"
    echo "    4. Select version 3.x"
    echo "    5. Wait for status 'Succeeded'"
    echo ""
    ERRORS=$((ERRORS+1))
fi

# Check Kiali Operator (optional)
echo ""
echo -e "${YELLOW}=== Checking Kiali Operator (optional) ===${NC}"
if $KUBECTL get crd kialis.kiali.io &>/dev/null; then
    echo -e "${GREEN}✓ Kiali Operator is installed${NC}"

    # Try to find the Kiali CSV
    if [ "$KUBECTL" = "oc" ]; then
        KIALI_CSV=$(oc get csv -n openshift-operators 2>/dev/null | grep -i kiali | awk '{print $1}' | head -1)
        if [ -n "$KIALI_CSV" ]; then
            echo "  Version: $KIALI_CSV"
            KIALI_PHASE=$(oc get csv -n openshift-operators 2>/dev/null | grep -i kiali | awk '{print $NF}' | head -1)
            if [ "$KIALI_PHASE" = "Succeeded" ]; then
                echo "  Status: ${GREEN}Succeeded${NC}"
            else
                echo -e "  Status: ${YELLOW}$KIALI_PHASE${NC}"
                WARNINGS=$((WARNINGS+1))
            fi
        fi
    fi
else
    echo -e "${YELLOW}⚠ Kiali Operator is NOT installed (optional)${NC}"
    echo ""
    echo "  Kiali provides observability for the service mesh."
    echo "  You can install it later or skip it."
    echo ""
    echo "  To install via OpenShift Console:"
    echo "    1. Operators → OperatorHub"
    echo "    2. Search 'Kiali'"
    echo "    3. Install Kiali Operator (stable channel)"
    echo ""
    echo "  Or via CLI:"
    echo "    cat <<EOF | oc apply -f -"
    echo "    apiVersion: operators.coreos.com/v1alpha1"
    echo "    kind: Subscription"
    echo "    metadata:"
    echo "      name: kiali"
    echo "      namespace: openshift-operators"
    echo "    spec:"
    echo "      channel: stable"
    echo "      name: kiali-ossm"
    echo "      source: redhat-operators"
    echo "      sourceNamespace: openshift-marketplace"
    echo "    EOF"
    echo ""
    WARNINGS=$((WARNINGS+1))
fi

# Check Gateway API CRDs
echo ""
echo -e "${YELLOW}=== Checking Gateway API CRDs ===${NC}"
if $KUBECTL get crd gatewayclasses.gateway.networking.k8s.io &>/dev/null; then
    echo -e "${GREEN}✓ Gateway API CRDs already installed${NC}"
    GATEWAY_API_VERSION=$($KUBECTL get crd gatewayclasses.gateway.networking.k8s.io -o jsonpath='{.spec.versions[0].name}' 2>/dev/null)
    if [ -n "$GATEWAY_API_VERSION" ]; then
        echo "  API Version: $GATEWAY_API_VERSION"
    fi
else
    echo -e "${YELLOW}⚠ Gateway API CRDs not installed${NC}"
    echo "  Will be installed automatically during deployment"
    WARNINGS=$((WARNINGS+1))
fi

# Check cluster admin permissions
echo ""
echo -e "${YELLOW}=== Checking permissions ===${NC}"
if $KUBECTL auth can-i create namespace &>/dev/null; then
    echo -e "${GREEN}✓ Can create namespaces${NC}"
else
    echo -e "${RED}✗ Cannot create namespaces${NC}"
    echo "  Cluster admin permissions required"
    ERRORS=$((ERRORS+1))
fi

if [ "$KUBECTL" = "oc" ]; then
    if oc auth can-i adm policy add-scc-to-user &>/dev/null; then
        echo -e "${GREEN}✓ Can manage SCC permissions${NC}"
    else
        echo -e "${YELLOW}⚠ Cannot manage SCC permissions${NC}"
        echo "  May need manual SCC configuration"
        WARNINGS=$((WARNINGS+1))
    fi
fi

# Check for existing namespaces
echo ""
echo -e "${YELLOW}=== Checking for existing deployments ===${NC}"
EXISTING_NS=""
for ns in istio-system istio-cni ztunnel bookinfo; do
    if $KUBECTL get namespace $ns &>/dev/null; then
        EXISTING_NS="$EXISTING_NS $ns"
    fi
done

if [ -n "$EXISTING_NS" ]; then
    echo -e "${YELLOW}⚠ Found existing namespaces:${NC}"
    echo "  $EXISTING_NS"
    echo ""
    echo "  Run './cleanup.sh' before deploying to avoid conflicts"
    WARNINGS=$((WARNINGS+1))
else
    echo -e "${GREEN}✓ No conflicting namespaces found${NC}"
fi

# Check for existing Kiali/Prometheus in istio-system
if $KUBECTL get namespace istio-system &>/dev/null; then
    EXISTING_COMPONENTS=""
    if $KUBECTL get deployment kiali -n istio-system &>/dev/null; then
        EXISTING_COMPONENTS="$EXISTING_COMPONENTS kiali"
    fi
    if $KUBECTL get deployment prometheus -n istio-system &>/dev/null; then
        EXISTING_COMPONENTS="$EXISTING_COMPONENTS prometheus"
    fi

    if [ -n "$EXISTING_COMPONENTS" ]; then
        echo -e "${YELLOW}⚠ Found existing observability components in istio-system:${NC}"
        echo "  $EXISTING_COMPONENTS"
        echo ""
        echo "  Run './cleanup-kiali.sh' to clean them up if needed"
        WARNINGS=$((WARNINGS+1))
    fi
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Ready to deploy:"
    echo "  cd single-cluster/scripts"
    echo "  ./deploy-all.sh          # Complete deployment (Istio + Bookinfo + optional Kiali)"
    echo ""
    echo "Or deploy step by step:"
    echo "  ./deploy-istio.sh        # Deploy Istio infrastructure"
    echo "  ./deploy-bookinfo.sh     # Deploy Bookinfo application"
    echo "  ./deploy-kiali.sh        # Deploy Kiali (optional, requires Kiali Operator)"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    echo ""
    echo "You can proceed with deployment, but review warnings above."
    echo ""
    echo "To deploy:"
    echo "  cd single-cluster/scripts"
    echo "  ./deploy-all.sh          # Complete deployment (Istio + Bookinfo)"
    echo ""
    echo "Note: If Kiali Operator is not installed, you can skip Kiali deployment"
    echo "or install the operator first and then run ./deploy-kiali.sh"
else
    echo -e "${RED}✗ $ERRORS error(s) found${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    fi
    echo ""
    echo "Please fix errors before deploying."
    exit 1
fi

echo ""
