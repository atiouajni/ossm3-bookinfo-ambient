#!/bin/bash

# OpenShift Service Mesh 3.3 - Cleanup Script
# Author: Anisse Tiouajni
# Description: Removes all OSSM3 and Bookinfo resources

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Confirm cleanup
echo -e "${RED}========================================${NC}"
echo -e "${RED}  WARNING: This will delete ALL resources${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo "This script will remove:"
echo "  - HTTPRoutes and Gateways"
echo "  - OpenShift Route"
echo "  - Bookinfo application"
echo "  - Istio Ingress Gateway"
echo "  - Waypoint Gateway"
echo "  - Ztunnel"
echo "  - Istio CNI"
echo "  - Istio Control Plane"
echo "  - Webhooks"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Cleanup cancelled."
    exit 0
fi

# Remove HTTPRoutes and routing
log_info "Removing HTTPRoutes and routing configurations..."
oc delete httproute --all -n bookinfo --ignore-not-found=true
oc delete httproute --all -n ztunnel --ignore-not-found=true
oc delete httproute --all -n istio-system --ignore-not-found=true

# Remove OpenShift Route
log_info "Removing OpenShift Route..."
oc delete route mesh-ingress -n istio-system --ignore-not-found=true

# Remove Ingress Gateway
log_info "Removing Ingress Gateway..."
oc delete gateway istio-ingress -n istio-system --ignore-not-found=true
oc delete deployment istio-ingress-istio -n istio-system --ignore-not-found=true
oc delete service istio-ingress-istio -n istio-system --ignore-not-found=true

# Remove Waypoint
log_info "Removing Waypoint Gateway..."
oc delete gateway waypoint -n bookinfo --ignore-not-found=true
oc delete deployment waypoint -n bookinfo --ignore-not-found=true
oc delete service waypoint -n bookinfo --ignore-not-found=true

# Remove Bookinfo
log_info "Removing Bookinfo application..."
oc delete all -l app -n bookinfo --ignore-not-found=true
oc delete serviceaccount -l app -n bookinfo --ignore-not-found=true
oc delete namespace bookinfo --wait=false --ignore-not-found=true

# Remove Ztunnel
log_info "Removing Ztunnel..."
oc delete daemonset ztunnel -n ztunnel --ignore-not-found=true
oc delete namespace ztunnel --wait=false --ignore-not-found=true

# Remove Istio Control Plane
log_info "Removing Istio Control Plane..."
oc delete deployment istiod -n istio-system --ignore-not-found=true
oc delete service istiod -n istio-system --ignore-not-found=true
oc delete namespace istio-system --wait=false --ignore-not-found=true

# Remove Istio CNI
log_info "Removing Istio CNI..."
oc delete daemonset istio-cni-node -n istio-cni --ignore-not-found=true
oc delete namespace istio-cni --wait=false --ignore-not-found=true

# Remove Webhooks
log_info "Removing Istio webhooks..."
oc delete validatingwebhookconfigurations istio-validator-istio-system --ignore-not-found=true
oc delete validatingwebhookconfigurations istiod-default-validator --ignore-not-found=true
oc delete mutatingwebhookconfigurations istio-sidecar-injector --ignore-not-found=true

# Wait for resources to be deleted
log_info "Waiting for resources to be deleted..."
sleep 10

# Check and report remaining namespaces
for ns in istio-system istio-cni ztunnel bookinfo; do
    if oc get namespace $ns &> /dev/null; then
        log_warn "Namespace $ns still terminating..."
    fi
done

log_info "Cleanup completed ✓"
echo ""
echo "Remaining resources (if any):"
oc get ns | grep -E "istio|ztunnel|bookinfo" || echo "  All namespaces deleted ✓"
echo ""
echo "Note: CRDs were preserved for faster redeployment."
echo "To remove CRDs: oc delete crd -l 'app.kubernetes.io/part-of=istio'"
echo ""
