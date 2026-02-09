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
echo -e "${BLUE}  Distributed Tracing with Tempo${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check CLI tool
echo -e "${YELLOW}=== Checking CLI tools ===${NC}"
if command -v oc &> /dev/null; then
    KUBECTL="oc"
    echo -e "${GREEN}✓ OpenShift CLI (oc) found${NC}"
    OC_VERSION=$(oc version 2>/dev/null | grep "Client Version:" | awk '{print $3}')
    echo "  Version: $OC_VERSION"
elif command -v kubectl &> /dev/null; then
    KUBECTL="kubectl"
    echo -e "${GREEN}✓ kubectl found${NC}"
    KUBECTL_VERSION=$(kubectl version --client 2>/dev/null | grep -o 'v[0-9.]*' | head -1)
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

# Check Tempo Operator
echo ""
echo -e "${YELLOW}=== Checking Tempo Operator ===${NC}"
if $KUBECTL get crd tempomonolithics.tempo.grafana.com &> /dev/null; then
    echo -e "${GREEN}✓ Tempo Operator installed${NC}"

    # Check if operator pod is running
    OPERATOR_POD=$($KUBECTL get pods -n openshift-operators -l app.kubernetes.io/name=tempo-operator 2>/dev/null | grep Running | wc -l)
    if [ "$OPERATOR_POD" -gt 0 ]; then
        echo -e "${GREEN}✓ Tempo Operator pod running${NC}"
        OPERATOR_VERSION=$($KUBECTL get csv -n openshift-operators -o json 2>/dev/null | grep -o '"name":"tempo-operator[^"]*' | head -1 | cut -d'"' -f4)
        if [ -n "$OPERATOR_VERSION" ]; then
            echo "  Version: $OPERATOR_VERSION"
        fi
    else
        echo -e "${YELLOW}⚠ Tempo Operator pod not running${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${RED}✗ Tempo Operator not installed${NC}"
    echo ""
    echo "  Install via OpenShift Console:"
    echo "    Operators → OperatorHub → 'Tempo Operator' → Install"
    echo ""
    echo "  Or via CLI:"
    echo "    oc apply -f - <<EOF"
    echo "    apiVersion: operators.coreos.com/v1alpha1"
    echo "    kind: Subscription"
    echo "    metadata:"
    echo "      name: tempo-operator"
    echo "      namespace: openshift-operators"
    echo "    spec:"
    echo "      channel: stable"
    echo "      name: tempo-operator"
    echo "      source: redhat-operators"
    echo "      sourceNamespace: openshift-marketplace"
    echo "    EOF"
    echo ""
    ERRORS=$((ERRORS+1))
fi

# Check Istio
echo ""
echo -e "${YELLOW}=== Checking Istio ===${NC}"
if $KUBECTL get namespace istio-system &> /dev/null; then
    echo -e "${GREEN}✓ istio-system namespace exists${NC}"

    # Check istiod
    if $KUBECTL get deployment istiod -n istio-system &> /dev/null; then
        ISTIOD_READY=$($KUBECTL get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        ISTIOD_REPLICAS=$($KUBECTL get deployment istiod -n istio-system -o jsonpath='{.status.replicas}' 2>/dev/null)

        if [ "$ISTIOD_READY" = "$ISTIOD_REPLICAS" ] && [ "$ISTIOD_READY" -gt 0 ]; then
            echo -e "${GREEN}✓ istiod deployment ready ($ISTIOD_READY/$ISTIOD_REPLICAS)${NC}"

            # Get Istio version
            ISTIO_VERSION=$($KUBECTL get istio default -n istio-system -o jsonpath='{.spec.version}' 2>/dev/null)
            if [ -n "$ISTIO_VERSION" ]; then
                echo "  Version: $ISTIO_VERSION"
            fi
        else
            echo -e "${RED}✗ istiod not ready ($ISTIOD_READY/$ISTIOD_REPLICAS)${NC}"
            ERRORS=$((ERRORS+1))
        fi
    else
        echo -e "${RED}✗ istiod deployment not found${NC}"
        echo "  Please deploy Istio first: cd ../../scripts && ./deploy-istio.sh"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "${RED}✗ istio-system namespace not found${NC}"
    echo "  Please deploy Istio first: cd ../../scripts && ./deploy-istio.sh"
    ERRORS=$((ERRORS+1))
fi

# Check Prometheus
echo ""
echo -e "${YELLOW}=== Checking Prometheus (optional) ===${NC}"
if $KUBECTL get deployment prometheus -n istio-system &> /dev/null; then
    PROM_READY=$($KUBECTL get deployment prometheus -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    PROM_REPLICAS=$($KUBECTL get deployment prometheus -n istio-system -o jsonpath='{.status.replicas}' 2>/dev/null)

    if [ "$PROM_READY" = "$PROM_REPLICAS" ] && [ "$PROM_READY" -gt 0 ]; then
        echo -e "${GREEN}✓ Prometheus deployed and ready${NC}"
    else
        echo -e "${YELLOW}⚠ Prometheus not ready${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${YELLOW}⚠ Prometheus not deployed${NC}"
    echo "  Tempo can work without Prometheus but metrics generation will be limited"
    echo "  To deploy Prometheus: cd ../../scripts && ./deploy-kiali.sh"
    WARNINGS=$((WARNINGS+1))
fi

# Check Bookinfo (optional)
echo ""
echo -e "${YELLOW}=== Checking Bookinfo (optional) ===${NC}"
if $KUBECTL get namespace bookinfo &> /dev/null; then
    echo -e "${GREEN}✓ bookinfo namespace exists${NC}"

    # Check if pods are running
    BOOKINFO_PODS=$($KUBECTL get pods -n bookinfo --no-headers 2>/dev/null | grep -c Running)
    TOTAL_PODS=$($KUBECTL get pods -n bookinfo --no-headers 2>/dev/null | wc -l)

    if [ "$BOOKINFO_PODS" -gt 0 ]; then
        echo -e "${GREEN}✓ Bookinfo pods running ($BOOKINFO_PODS/$TOTAL_PODS)${NC}"
    else
        echo -e "${YELLOW}⚠ No Bookinfo pods running${NC}"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${YELLOW}⚠ bookinfo namespace not found${NC}"
    echo "  Bookinfo is not required but recommended for testing traces"
    echo "  To deploy Bookinfo: cd ../../scripts && ./deploy-bookinfo.sh"
    WARNINGS=$((WARNINGS+1))
fi

# Check for conflicting Tempo installations
echo ""
echo -e "${YELLOW}=== Checking for conflicts ===${NC}"
EXISTING_TEMPO=$($KUBECTL get tempomonolithic tempo -n istio-system 2>/dev/null)
if [ -n "$EXISTING_TEMPO" ]; then
    echo -e "${YELLOW}⚠ Tempo already deployed${NC}"
    TEMPO_STATUS=$($KUBECTL get tempomonolithic tempo -n istio-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    echo "  Status: $TEMPO_STATUS"
    echo "  You may want to clean it up first: cd scripts && ./cleanup-tracing.sh"
    WARNINGS=$((WARNINGS+1))
else
    echo -e "${GREEN}✓ No existing Tempo deployment${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All prerequisites met!${NC}"
    echo ""
    echo "You can proceed with the deployment:"
    echo "  cd tracing/scripts && ./deploy-tracing.sh"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Prerequisites met with $WARNINGS warning(s)${NC}"
    echo ""
    echo "You can proceed with the deployment, but some features may be limited:"
    echo "  cd tracing/scripts && ./deploy-tracing.sh"
else
    echo -e "${RED}✗ $ERRORS error(s) found${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    fi
    echo ""
    echo "Please fix the errors above before deploying."
    exit 1
fi

echo ""
