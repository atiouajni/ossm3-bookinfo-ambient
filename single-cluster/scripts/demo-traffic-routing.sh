#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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
echo -e "${BLUE}  Traffic Routing Demo${NC}"
echo -e "${BLUE}  Istio VirtualServices in Action${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if bookinfo is deployed
if ! $KUBECTL get namespace bookinfo &>/dev/null; then
    echo -e "${RED}Error: Bookinfo namespace not found${NC}"
    echo "Please deploy Bookinfo first: ./deploy-bookinfo.sh"
    exit 1
fi

# Get Bookinfo URL
if [ "$KUBECTL" = "oc" ]; then
    BOOKINFO_URL=$(oc get route bookinfo -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null)
    if [ -z "$BOOKINFO_URL" ]; then
        echo -e "${RED}Error: Cannot find Bookinfo route${NC}"
        exit 1
    fi
fi

echo -e "${CYAN}This demo will show you how to control traffic routing with Istio VirtualServices.${NC}"
echo ""
echo "We will demonstrate different routing scenarios:"
echo "  1. All traffic to one version"
echo "  2. Canary deployment (gradual rollout)"
echo "  3. Security policy (L4 deny with AuthorizationPolicy)"
echo ""
read -p "Press Enter to start the demo..."

# Demo 1: All traffic to v1
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Demo 1: Route all traffic to v1${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Applying VirtualService to route 100% traffic to reviews v1 (no stars)..."
"$SCRIPT_DIR/apply-routing-scenario.sh" <<< "2" > /dev/null

echo ""
echo -e "${GREEN}✓ VirtualService applied${NC}"
echo ""
echo "Open your browser and refresh several times:"
echo -e "  ${CYAN}https://$BOOKINFO_URL/productpage${NC}"
echo ""
echo "You should see:"
echo "  - Book reviews WITHOUT stars (always v1)"
echo ""
read -p "Press Enter when you've verified this behavior..."

# Demo 2: All traffic to v3
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Demo 2: Route all traffic to v3${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Applying VirtualService to route 100% traffic to reviews v3 (red stars)..."
"$SCRIPT_DIR/apply-routing-scenario.sh" <<< "4" > /dev/null

echo ""
echo -e "${GREEN}✓ VirtualService applied${NC}"
echo ""
echo "Refresh your browser several times:"
echo -e "  ${CYAN}https://$BOOKINFO_URL/productpage${NC}"
echo ""
echo "You should see:"
echo "  - Book reviews with RED stars (always v3)"
echo ""
read -p "Press Enter when you've verified this behavior..."

# Demo 3: Canary deployment
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Demo 3: Canary Deployment${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Simulating a canary deployment: 90% to v1, 10% to v3..."
echo "This is how you would gradually roll out a new version."
echo ""
"$SCRIPT_DIR/apply-routing-scenario.sh" <<< "5" > /dev/null

echo ""
echo -e "${GREEN}✓ VirtualService applied${NC}"
echo ""
echo "Refresh your browser multiple times (at least 10 times):"
echo -e "  ${CYAN}https://$BOOKINFO_URL/productpage${NC}"
echo ""
echo "You should see:"
echo "  - ~90% of requests: NO stars (v1)"
echo "  - ~10% of requests: RED stars (v3)"
echo ""
read -p "Press Enter when you've verified this behavior..."

# Demo 4: AuthorizationPolicy deny-all (L4 Security)
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Demo 4: Security Policy (L4 Deny)${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Applying AuthorizationPolicy to BLOCK all traffic to reviews..."
echo "This demonstrates L4 security enforcement by ZTunnel."
echo ""
echo -e "${CYAN}⚠️  This will make the reviews section fail!${NC}"
echo ""
"$SCRIPT_DIR/apply-routing-scenario.sh" <<< "6" > /dev/null

echo ""
echo -e "${GREEN}✓ AuthorizationPolicy applied${NC}"
echo ""
echo "Refresh your browser:"
echo -e "  ${CYAN}https://$BOOKINFO_URL/productpage${NC}"
echo ""
echo "You should see:"
echo "  - Page loads successfully"
echo "  - ❌ Reviews section shows ERROR or is empty"
echo "  - Details and ratings still work"
echo ""
echo "This is because ZTunnel (L4 proxy) is blocking ALL TCP connections"
echo "to the reviews service BEFORE they reach the Waypoint (L7 proxy)."
echo ""
echo "The deny happens at the network level, not application level!"
echo ""
read -p "Press Enter to restore normal traffic..."

# Demo 5: Back to default (round-robin)
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Demo 5: Round-robin distribution${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Removing AuthorizationPolicy and restoring default behavior..."
$KUBECTL delete authorizationpolicy deny-reviews -n bookinfo 2>/dev/null || true
"$SCRIPT_DIR/apply-routing-scenario.sh" <<< "1" > /dev/null

echo ""
echo -e "${GREEN}✓ VirtualService applied${NC}"
echo ""
echo "Refresh your browser multiple times:"
echo -e "  ${CYAN}https://$BOOKINFO_URL/productpage${NC}"
echo ""
echo "You should see all three versions randomly:"
echo "  - NO stars (v1) - ~33%"
echo "  - BLACK stars (v2) - ~33%"
echo "  - RED stars (v3) - ~34%"
echo ""

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Demo Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "What you've learned:"
echo "  ✅ Control traffic distribution with VirtualServices (L7)"
echo "  ✅ Implement canary deployments"
echo "  ✅ Apply security policies at L4 with AuthorizationPolicy"
echo "  ✅ Understand ZTunnel (L4) vs Waypoint (L7) enforcement"
echo "  ✅ All without restarting pods (Ambient mode!)"
echo ""
echo "To visualize traffic in Kiali:"
echo -e "  1. Generate traffic: ${CYAN}./generate-traffic.sh 100${NC}"
echo "  2. Open Kiali and view the Graph"
echo ""
echo "To apply other scenarios manually:"
echo -e "  ${CYAN}./apply-routing-scenario.sh${NC}"
echo ""
