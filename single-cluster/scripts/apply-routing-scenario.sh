#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Traffic Routing Scenario Manager${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if bookinfo is deployed
if ! $KUBECTL get namespace bookinfo &>/dev/null; then
    echo -e "${RED}Error: Bookinfo namespace not found${NC}"
    echo "Please deploy Bookinfo first: ./deploy-bookinfo.sh"
    exit 1
fi

echo -e "${CYAN}Available routing scenarios:${NC}"
echo ""
echo -e "  1) ${GREEN}default${NC}        - Round-robin across all versions (33/33/34)"
echo -e "  2) ${GREEN}v1-only${NC}        - All traffic to reviews v1 (no stars)"
echo -e "  3) ${GREEN}v2-only${NC}        - All traffic to reviews v2 (black stars)"
echo -e "  4) ${GREEN}v3-only${NC}        - All traffic to reviews v3 (red stars)"
echo -e "  5) ${GREEN}canary-v3${NC}      - Canary: 90% v1, 10% v3"
echo -e "  6) ${GREEN}deny-reviews${NC}   - AuthorizationPolicy: Block all traffic to reviews"
echo ""
echo -e "  0) ${YELLOW}Show current routing${NC}"
echo ""

read -p "Select a scenario (0-6): " SCENARIO

case $SCENARIO in
    0)
        echo ""
        echo -e "${YELLOW}=== Current Routing Configuration ===${NC}"
        echo ""

        echo -e "${CYAN}VirtualService for reviews:${NC}"
        echo ""
        $KUBECTL get virtualservice reviews -n bookinfo -o yaml 2>/dev/null || echo "No VirtualService found"

        echo ""
        echo -e "${CYAN}AuthorizationPolicies (L4 Security):${NC}"
        echo ""
        AUTHZ_POLICIES=$($KUBECTL get authorizationpolicy -n bookinfo 2>/dev/null)
        if [ -z "$AUTHZ_POLICIES" ] || echo "$AUTHZ_POLICIES" | grep -q "No resources found"; then
            echo -e "${GREEN}✓ No AuthorizationPolicy found (traffic allowed)${NC}"
        else
            echo "$AUTHZ_POLICIES"
            echo ""
            echo -e "${YELLOW}⚠️  AuthorizationPolicy detected - may block traffic!${NC}"
            echo ""
            $KUBECTL get authorizationpolicy -n bookinfo -o yaml
        fi

        exit 0
        ;;
    1)
        SCENARIO_NAME="default (round-robin)"
        SCENARIO_FILE="${PROJECT_DIR}/bookinfo/traffic-management.yaml"
        ;;
    2)
        SCENARIO_NAME="v1-only (no stars)"
        SCENARIO_FILE="${PROJECT_DIR}/bookinfo/routing-scenarios/reviews-v1-only.yaml"
        ;;
    3)
        SCENARIO_NAME="v2-only (black stars)"
        SCENARIO_FILE="${PROJECT_DIR}/bookinfo/routing-scenarios/reviews-v2-only.yaml"
        ;;
    4)
        SCENARIO_NAME="v3-only (red stars)"
        SCENARIO_FILE="${PROJECT_DIR}/bookinfo/routing-scenarios/reviews-v3-only.yaml"
        ;;
    5)
        SCENARIO_NAME="canary-v3 (90% v1, 10% v3)"
        SCENARIO_FILE="${PROJECT_DIR}/bookinfo/routing-scenarios/reviews-canary-v3.yaml"
        ;;
    6)
        SCENARIO_NAME="deny-reviews (AuthorizationPolicy)"
        SCENARIO_FILE="${PROJECT_DIR}/bookinfo/routing-scenarios/authz-deny-reviews.yaml"
        ;;
    *)
        echo -e "${RED}Invalid scenario${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}Applying scenario: ${CYAN}$SCENARIO_NAME${NC}"
echo ""

if [ ! -f "$SCENARIO_FILE" ]; then
    echo -e "${RED}Error: Scenario file not found: $SCENARIO_FILE${NC}"
    exit 1
fi

$KUBECTL apply -f "$SCENARIO_FILE"

echo ""
echo -e "${GREEN}✓ Routing scenario applied successfully${NC}"
echo ""

# Get Bookinfo URL
if [ "$KUBECTL" = "oc" ]; then
    BOOKINFO_URL=$(oc get route bookinfo -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null)
    if [ -n "$BOOKINFO_URL" ]; then
        echo "Test the routing:"
        echo -e "  ${CYAN}https://$BOOKINFO_URL/productpage${NC}"
        echo ""
    fi
fi

# Show what to expect
case $SCENARIO in
    2)
        echo "Expected behavior:"
        echo "  - All requests show reviews WITHOUT stars"
        ;;
    3)
        echo "Expected behavior:"
        echo "  - All requests show reviews with BLACK stars"
        ;;
    4)
        echo "Expected behavior:"
        echo "  - All requests show reviews with RED stars"
        ;;
    5)
        echo "Expected behavior:"
        echo "  - 90% of requests show reviews WITHOUT stars (v1)"
        echo "  - 10% of requests show reviews with RED stars (v3)"
        ;;
    6)
        echo "Expected behavior:"
        echo "  - ❌ Page loads but reviews section shows ERROR or is empty"
        echo "  - ⚠️  AuthorizationPolicy blocks ALL traffic to reviews service"
        echo "  - To restore: Apply scenario 1 (default) or delete AuthorizationPolicy"
        echo ""
        echo "To remove the deny policy:"
        echo -e "  ${CYAN}kubectl delete authorizationpolicy deny-reviews -n bookinfo${NC}"
        ;;
    1)
        echo "Expected behavior:"
        echo "  - Traffic distributed evenly across v1, v2, v3"
        echo "  - Refresh to see different star ratings"
        ;;
esac

echo ""
echo "To see traffic distribution in Kiali:"
echo -e "  1. Generate traffic: ${CYAN}./generate-traffic.sh 100${NC}"
echo "  2. Open Kiali dashboard"
echo "  3. View Graph → Select namespace 'bookinfo'"
echo ""
