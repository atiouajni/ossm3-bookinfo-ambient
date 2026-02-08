#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
echo -e "${BLUE}  Generating Traffic for Bookinfo${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Get Bookinfo URL
BOOKINFO_URL=""

if [ "$KUBECTL" = "oc" ]; then
    if ! oc get route bookinfo -n istio-system &>/dev/null; then
        echo -e "${YELLOW}Warning: Bookinfo route not found${NC}"
        echo "Please deploy Bookinfo first: ./deploy-bookinfo.sh"
        exit 1
    fi
    BOOKINFO_HOST=$(oc get route bookinfo -n istio-system -o jsonpath='{.spec.host}')
    BOOKINFO_URL="https://$BOOKINFO_HOST/productpage"
else
    echo "For Kubernetes, please set BOOKINFO_URL environment variable"
    exit 1
fi

echo "Target URL: $BOOKINFO_URL"
echo ""

# Default number of requests
REQUESTS=${1:-100}

echo -e "${YELLOW}Sending $REQUESTS requests to Bookinfo...${NC}"
echo ""

SUCCESS=0
FAILED=0

for i in $(seq 1 $REQUESTS); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "$BOOKINFO_URL" --max-time 5)

    if [ "$HTTP_CODE" = "200" ]; then
        SUCCESS=$((SUCCESS + 1))
        echo -ne "\rProgress: $i/$REQUESTS | Success: $SUCCESS | Failed: $FAILED"
    else
        FAILED=$((FAILED + 1))
        echo -ne "\rProgress: $i/$REQUESTS | Success: $SUCCESS | Failed: $FAILED"
    fi

    # Small delay between requests
    sleep 0.1
done

echo ""
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Traffic Generation Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Summary:"
echo "  Total requests: $REQUESTS"
echo "  Successful: $SUCCESS"
echo "  Failed: $FAILED"
echo ""
echo "Now check Kiali to visualize the traffic:"
if [ "$KUBECTL" = "oc" ]; then
    KIALI_URL="https://$(oc get route kiali -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null)"
    if [ -n "$KIALI_URL" ]; then
        echo "  Kiali: $KIALI_URL"
    fi
fi
echo ""
