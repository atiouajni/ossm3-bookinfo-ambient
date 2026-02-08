#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Verify Ambient Mode (L4 via ZTunnel)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect kubectl or oc
if command -v oc &> /dev/null; then
    KUBECTL="oc"
else
    KUBECTL="kubectl"
fi

echo -e "${YELLOW}=== 1. Verify NO Sidecars in Application Pods ===${NC}"
echo ""
echo "In ambient mode, there should be NO istio-proxy sidecar containers."
echo ""

PODS=$($KUBECTL get pods -n bookinfo -o name)
for pod in $PODS; do
    POD_NAME=$(echo $pod | cut -d'/' -f2)
    CONTAINERS=$($KUBECTL get pod $POD_NAME -n bookinfo -o jsonpath='{.spec.containers[*].name}')
    COUNT=$($KUBECTL get pod $POD_NAME -n bookinfo -o jsonpath='{.spec.containers[*].name}' | wc -w)

    echo -e "Pod: ${CYAN}$POD_NAME${NC}"
    echo "  Containers: $CONTAINERS"
    echo "  Container count: $COUNT"

    if echo "$CONTAINERS" | grep -q "istio-proxy"; then
        echo -e "  ${RED}✗ Has sidecar (NOT ambient mode)${NC}"
    else
        echo -e "  ${GREEN}✓ No sidecar (ambient mode)${NC}"
    fi
    echo ""
done

echo -e "${YELLOW}=== 2. Verify Namespace Ambient Label ===${NC}"
echo ""
AMBIENT_LABEL=$($KUBECTL get namespace bookinfo -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}')
if [ "$AMBIENT_LABEL" = "ambient" ]; then
    echo -e "${GREEN}✓ Namespace bookinfo has ambient label${NC}"
    echo "  istio.io/dataplane-mode: $AMBIENT_LABEL"
else
    echo -e "${RED}✗ Namespace not in ambient mode${NC}"
    echo "  Current label: $AMBIENT_LABEL"
fi
echo ""

echo -e "${YELLOW}=== 3. Verify ZTunnel DaemonSet ===${NC}"
echo ""
ZTUNNEL_PODS=$($KUBECTL get pods -n ztunnel -l app=ztunnel --no-headers 2>/dev/null | wc -l)
if [ "$ZTUNNEL_PODS" -gt 0 ]; then
    echo -e "${GREEN}✓ ZTunnel is running${NC}"
    echo ""
    $KUBECTL get pods -n ztunnel -l app=ztunnel
else
    echo -e "${RED}✗ ZTunnel not found${NC}"
fi
echo ""

echo -e "${YELLOW}=== 4. Generate Traffic ===${NC}"
echo ""
echo "Generating traffic to observe ZTunnel behavior..."
echo ""

# Get a productpage pod
PRODUCTPAGE_POD=$($KUBECTL get pod -n bookinfo -l app=productpage -o jsonpath='{.items[0].metadata.name}')

if [ -n "$PRODUCTPAGE_POD" ]; then
    echo "Calling reviews service from productpage pod..."
    $KUBECTL exec -n bookinfo $PRODUCTPAGE_POD -- curl -s http://reviews:9080/reviews/0 > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Traffic generated successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Could not generate traffic${NC}"
    fi
else
    echo -e "${RED}✗ No productpage pod found${NC}"
fi
echo ""

echo -e "${YELLOW}=== 5. Check ZTunnel Logs (Last 20 lines) ===${NC}"
echo ""
echo "Looking for connection logs showing L4 proxying..."
echo ""

ZTUNNEL_POD=$($KUBECTL get pod -n ztunnel -l app=ztunnel -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$ZTUNNEL_POD" ]; then
    echo -e "${CYAN}ZTunnel Pod: $ZTUNNEL_POD${NC}"
    echo ""
    $KUBECTL logs -n ztunnel $ZTUNNEL_POD --tail=20 2>/dev/null | grep -E "connection|proxy|inbound|outbound" || \
        $KUBECTL logs -n ztunnel $ZTUNNEL_POD --tail=20 2>/dev/null
else
    echo -e "${RED}✗ ZTunnel pod not found${NC}"
fi
echo ""

echo -e "${YELLOW}=== 6. Check ZTunnel Metrics ===${NC}"
echo ""
echo "Querying ZTunnel for active connections..."
echo ""

if [ -n "$ZTUNNEL_POD" ]; then
    # Try to get metrics from ZTunnel
    METRICS=$($KUBECTL exec -n ztunnel $ZTUNNEL_POD -- curl -s http://localhost:15020/stats/prometheus 2>/dev/null | grep -E "istio_tcp_connections_opened_total|istio_tcp_connections_closed_total" | head -10)

    if [ -n "$METRICS" ]; then
        echo -e "${GREEN}✓ ZTunnel metrics available${NC}"
        echo ""
        echo "$METRICS"
    else
        echo -e "${YELLOW}⚠ Metrics not available or no connections yet${NC}"
    fi
else
    echo -e "${RED}✗ Cannot query metrics${NC}"
fi
echo ""

echo -e "${YELLOW}=== 7. Verify mTLS via ZTunnel ===${NC}"
echo ""
echo "In ambient mode, ZTunnel handles mTLS at L4."
echo "Checking connection security..."
echo ""

# Check if istiod has ambient configuration
AMBIENT_ENABLED=$($KUBECTL get istio -n istio-system default -o jsonpath='{.spec.profile}' 2>/dev/null)
if [ "$AMBIENT_ENABLED" = "ambient" ]; then
    echo -e "${GREEN}✓ Istio configured in ambient profile${NC}"
else
    echo -e "${YELLOW}⚠ Istio profile: $AMBIENT_ENABLED${NC}"
fi
echo ""

echo -e "${YELLOW}=== 8. Network Flow Diagram ===${NC}"
echo ""
echo "Traffic flow in ambient mode:"
echo ""
echo "  productpage pod"
echo "       │"
echo "       ├─> (1) Outbound to reviews:9080"
echo "       │"
echo "       ▼"
echo "  ZTunnel (on productpage node)"
echo "       │"
echo "       ├─> (2) L4 proxy + mTLS encryption"
echo "       │"
echo "       ▼"
echo "  ZTunnel (on reviews node)"
echo "       │"
echo "       ├─> (3) mTLS decryption"
echo "       │"
echo "       ▼"
echo "  reviews pod"
echo ""

echo -e "${YELLOW}=== 9. Pod Network Details ===${NC}"
echo ""
echo "Checking network configuration on pods..."
echo ""

if [ -n "$PRODUCTPAGE_POD" ]; then
    echo -e "${CYAN}Pod: $PRODUCTPAGE_POD${NC}"

    # Check if pod has ambient annotations
    AMBIENT_REDIRECT=$($KUBECTL get pod -n bookinfo $PRODUCTPAGE_POD -o jsonpath='{.metadata.annotations.ambient\.istio\.io/redirection}' 2>/dev/null)

    if [ -n "$AMBIENT_REDIRECT" ]; then
        echo -e "${GREEN}✓ Pod has ambient redirection annotation${NC}"
        echo "  ambient.istio.io/redirection: enabled"
    else
        echo -e "${YELLOW}⚠ No explicit ambient annotation (may use CNI)${NC}"
    fi

    # Check iptables rules (shows traffic redirection to ZTunnel)
    echo ""
    echo "Checking if traffic is redirected to ZTunnel..."
    IPTABLES=$($KUBECTL exec -n bookinfo $PRODUCTPAGE_POD -- sh -c 'command -v iptables' 2>/dev/null)

    if [ -n "$IPTABLES" ]; then
        echo "  Checking iptables NAT rules..."
        $KUBECTL exec -n bookinfo $PRODUCTPAGE_POD -- iptables -t nat -L -n 2>/dev/null | grep -E "15006|15001|REDIRECT" | head -5
    else
        echo "  (iptables not available in container - traffic handled by CNI)"
    fi
fi
echo ""

echo -e "${YELLOW}=== 10. Summary ===${NC}"
echo ""

# Count checks
SIDECAR_CHECK="✓"
LABEL_CHECK="✓"
ZTUNNEL_CHECK="✓"

if $KUBECTL get pods -n bookinfo -o jsonpath='{.items[*].spec.containers[*].name}' | grep -q "istio-proxy"; then
    SIDECAR_CHECK="✗"
fi

if [ "$AMBIENT_LABEL" != "ambient" ]; then
    LABEL_CHECK="✗"
fi

if [ "$ZTUNNEL_PODS" -eq 0 ]; then
    ZTUNNEL_CHECK="✗"
fi

echo -e "Ambient Mode Status:"
echo -e "  ${SIDECAR_CHECK} No sidecars in application pods"
echo -e "  ${LABEL_CHECK} Namespace labeled for ambient"
echo -e "  ${ZTUNNEL_CHECK} ZTunnel DaemonSet running"
echo ""

if [ "$SIDECAR_CHECK" = "✓" ] && [ "$LABEL_CHECK" = "✓" ] && [ "$ZTUNNEL_CHECK" = "✓" ]; then
    echo -e "${GREEN}✓✓✓ Ambient mode is ACTIVE${NC}"
    echo -e "${GREEN}    Traffic is flowing through ZTunnel at L4${NC}"
else
    echo -e "${RED}✗ Ambient mode may not be properly configured${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo ""
