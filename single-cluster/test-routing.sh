#!/usr/bin/env bash

# Test routing for Bookinfo application in Istio Ambient mode
# Tests both internal (waypoint) and external (ingress) routing

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Testing Bookinfo Ambient Routing${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if bookinfo namespace exists
if ! oc get namespace bookinfo &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Namespace 'bookinfo' not found."
    echo "Please deploy Bookinfo first: ./deploy.sh"
    exit 1
fi

# Show ambient configuration
echo -e "${GREEN}[INFO]${NC} Checking Ambient mode configuration..."
echo ""
echo "Namespace labels:"
oc get ns bookinfo --show-labels | grep -E "istio.io/dataplane-mode|istio.io/use-waypoint" || echo "  No ambient labels"

echo ""
echo "Waypoint Gateway:"
oc get gateway waypoint -n bookinfo 2>/dev/null || echo "  No waypoint found"

echo ""
echo "HTTPRoutes:"
oc get httproute -n bookinfo 2>/dev/null || echo "  No HTTPRoutes found"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Internal Routing Test (via Waypoint)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Create test pod if not exists
if ! oc get pod curl-test -n bookinfo &> /dev/null; then
    echo -e "${GREEN}[INFO]${NC} Creating test pod..."
    oc run curl-test --image=curlimages/curl -n bookinfo --restart=Never -- sleep 3600
    sleep 5
fi

echo -e "${GREEN}[INFO]${NC} Making 20 requests to http://reviews:9080/reviews/0"
echo ""

# Make 20 requests and count versions
declare -A version_count

for i in {1..20}; do
    RESPONSE=$(oc exec curl-test -n bookinfo -- \
        curl -sS http://reviews:9080/reviews/0 2>/dev/null)

    if echo "$RESPONSE" | grep -q 'reviews-v1'; then
        version="v1"
        ((version_count[v1]++)) || version_count[v1]=1
    elif echo "$RESPONSE" | grep -q 'reviews-v2'; then
        version="v2"
        ((version_count[v2]++)) || version_count[v2]=1
    elif echo "$RESPONSE" | grep -q 'reviews-v3'; then
        version="v3"
        ((version_count[v3]++)) || version_count[v3]=1
    else
        version="unknown"
    fi

    echo -e "Request $i: ${GREEN}$version${NC}"
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Traffic Distribution Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

total=20
v1=${version_count[v1]:-0}
v2=${version_count[v2]:-0}
v3=${version_count[v3]:-0}

v1_pct=$((v1 * 100 / total))
v2_pct=$((v2 * 100 / total))
v3_pct=$((v3 * 100 / total))

echo "Reviews v1 (no stars):    $v1 requests ($v1_pct%)"
echo "Reviews v2 (black stars): $v2 requests ($v2_pct%)"
echo "Reviews v3 (red stars):   $v3 requests ($v3_pct%)"
echo ""

# Determine routing scenario
if [ $v1 -eq 20 ]; then
    echo -e "${GREEN}✓ All traffic routed to v1${NC}"
elif [ $v2 -eq 20 ]; then
    echo -e "${GREEN}✓ All traffic routed to v2${NC}"
elif [ $v3 -eq 20 ]; then
    echo -e "${GREEN}✓ All traffic routed to v3${NC}"
elif [ $v1 -gt 0 ] && [ $v2 -gt 0 ] && [ $v3 -eq 0 ]; then
    echo -e "${GREEN}✓ Canary: Traffic split between v1 and v2${NC}"
elif [ $v1 -gt 0 ] && [ $v2 -gt 0 ] && [ $v3 -gt 0 ]; then
    echo -e "${YELLOW}⚠ Default: Traffic distributed across all versions${NC}"
else
    echo -e "${YELLOW}⚠ Custom routing pattern detected${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  External Access Test (via Ingress)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

INGRESS_HOST=$(oc get route mesh-ingress -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -z "$INGRESS_HOST" ]; then
    echo -e "${YELLOW}[WARN]${NC} OpenShift Route not found. Skipping external test."
else
    echo -e "${GREEN}[INFO]${NC} Testing external access via https://$INGRESS_HOST/productpage"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$INGRESS_HOST/productpage || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓ Ingress working (HTTP $HTTP_CODE)${NC}"
    else
        echo -e "${RED}✗ Ingress issue (HTTP $HTTP_CODE)${NC}"
    fi
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Ambient Architecture${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Traffic flow:"
echo "  Client → ztunnel (L4 mTLS)"
echo "    → waypoint (L7 routing via HTTPRoute)"
echo "      → ztunnel (L4 delivery)"
echo "        → reviews pod"
echo ""
echo "To change routing, apply a scenario:"
echo "  oc apply -f bookinfo/routing-scenarios/reviews-v1-only.yaml"
echo "  oc apply -f bookinfo/routing-scenarios/reviews-v2-only.yaml"
echo "  oc apply -f bookinfo/routing-scenarios/reviews-v3-only.yaml"
echo ""
