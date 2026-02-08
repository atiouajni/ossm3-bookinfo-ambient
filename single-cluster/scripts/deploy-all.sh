#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Complete Deployment${NC}"
echo -e "${BLUE}  Istio + Bookinfo (Ambient Mode)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if scripts exist
if [ ! -f "$SCRIPT_DIR/deploy-istio.sh" ]; then
    echo -e "${RED}Error: deploy-istio.sh not found${NC}"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/deploy-bookinfo.sh" ]; then
    echo -e "${RED}Error: deploy-bookinfo.sh not found${NC}"
    exit 1
fi

# Step 1: Deploy Istio
echo -e "${YELLOW}╔════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  PHASE 1: Deploying Istio          ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════╝${NC}"
echo ""

"$SCRIPT_DIR/deploy-istio.sh"

echo ""
echo -e "${GREEN}✓ Istio deployment completed${NC}"
echo ""
echo "Press Enter to continue with Bookinfo deployment..."
read -r

# Step 2: Deploy Bookinfo
echo ""
echo -e "${YELLOW}╔════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  PHASE 2: Deploying Bookinfo       ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════╝${NC}"
echo ""

"$SCRIPT_DIR/deploy-bookinfo.sh"

echo ""
echo -e "${GREEN}✓ Bookinfo deployment completed${NC}"
echo ""

# Optional Step 3: Deploy Kiali
echo ""
echo -e "${YELLOW}╔════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  OPTIONAL: Deploy Kiali?           ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════╝${NC}"
echo ""
echo "Kiali provides observability for your service mesh:"
echo "  • Service topology visualization"
echo "  • Traffic flow and metrics"
echo "  • Configuration validation"
echo ""
read -p "Do you want to deploy Kiali for observability? (y/n): " DEPLOY_KIALI

if [[ "$DEPLOY_KIALI" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  PHASE 3: Deploying Kiali          ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════╝${NC}"
    echo ""

    if [ -f "$SCRIPT_DIR/deploy-kiali.sh" ]; then
        "$SCRIPT_DIR/deploy-kiali.sh"
        echo ""
        echo -e "${GREEN}✓ Kiali deployment completed${NC}"
    else
        echo -e "${RED}Error: deploy-kiali.sh not found${NC}"
    fi
else
    echo "Skipping Kiali deployment."
    echo "You can deploy it later with: ./deploy-kiali.sh"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ Complete Deployment Finished!   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo ""
echo "All components have been successfully deployed!"
echo ""
