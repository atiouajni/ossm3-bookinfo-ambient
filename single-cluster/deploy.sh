#!/bin/bash

# OpenShift Service Mesh 3.3 - Bookinfo Ambient Mode Deployment Script
# Author: Anisse Tiouajni
# Description: Automated deployment script for OSSM3 with Bookinfo application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}

    log_info "Waiting for deployment $deployment in namespace $namespace..."
    oc wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n $namespace
}

wait_for_daemonset() {
    local namespace=$1
    local daemonset=$2
    local timeout=${3:-300}

    log_info "Waiting for daemonset $daemonset in namespace $namespace..."
    oc rollout status daemonset/$daemonset -n $namespace --timeout=${timeout}s
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v oc &> /dev/null; then
        log_error "oc CLI not found. Please install OpenShift CLI."
        exit 1
    fi

    if ! oc whoami &> /dev/null; then
        log_error "Not logged into OpenShift cluster. Please run 'oc login' first."
        exit 1
    fi

    log_info "Prerequisites check passed ✓"
}

# Deploy Istio CNI
deploy_cni() {
    log_info "Deploying Istio CNI..."
    oc create namespace istio-cni --dry-run=client -o yaml | oc apply -f -
    oc apply -f manifests/istio-cni.yaml
    sleep 10
    wait_for_daemonset istio-cni istio-cni-node 300
    log_info "Istio CNI deployed ✓"
}

# Deploy Istio Control Plane
deploy_control_plane() {
    log_info "Deploying Istio Control Plane..."
    oc create namespace istio-system --dry-run=client -o yaml | oc apply -f -
    oc apply -f manifests/istio.yaml
    sleep 10
    wait_for_deployment istio-system istiod 300
    log_info "Istio Control Plane deployed ✓"
}

# Deploy Ztunnel
deploy_ztunnel() {
    log_info "Deploying Ztunnel..."
    oc create namespace ztunnel --dry-run=client -o yaml | oc apply -f -
    oc apply -f manifests/ztunnel.yaml
    sleep 10
    wait_for_daemonset ztunnel ztunnel 300
    log_info "Ztunnel deployed ✓"
}

# Deploy Bookinfo Application
deploy_bookinfo() {
    log_info "Deploying Bookinfo Application..."

    oc create namespace bookinfo --dry-run=client -o yaml | oc apply -f -

    log_info "Configuring service accounts for OpenShift SCC..."
    oc adm policy add-scc-to-user anyuid -z bookinfo-productpage -n bookinfo
    oc adm policy add-scc-to-user anyuid -z bookinfo-details -n bookinfo
    oc adm policy add-scc-to-user anyuid -z bookinfo-ratings -n bookinfo
    oc adm policy add-scc-to-user anyuid -z bookinfo-reviews -n bookinfo

    oc apply -f bookinfo/bookinfo.yaml -n bookinfo
    oc apply -f bookinfo/bookinfo-versions.yaml -n bookinfo

    wait_for_deployment bookinfo productpage-v1 300
    wait_for_deployment bookinfo details-v1 300
    wait_for_deployment bookinfo ratings-v1 300
    wait_for_deployment bookinfo reviews-v1 300
    wait_for_deployment bookinfo reviews-v2 300
    wait_for_deployment bookinfo reviews-v3 300

    log_info "Bookinfo Application deployed ✓"
}

# Enroll Bookinfo in Ambient Mesh
enroll_ambient() {
    log_info "Enrolling Bookinfo in Ambient Mesh..."
    oc label namespace bookinfo istio.io/dataplane-mode=ambient --overwrite
    oc label namespace bookinfo istio.io/use-waypoint=waypoint --overwrite
    log_info "Bookinfo enrolled in Ambient Mesh ✓"
}

# Deploy Waypoint
deploy_waypoint() {
    log_info "Deploying Waypoint Gateway..."
    oc apply -f manifests/waypoint.yaml
    sleep 5
    oc wait --for=condition=Programmed gateway/waypoint -n bookinfo --timeout=120s
    wait_for_deployment bookinfo waypoint 300
    log_info "Waypoint Gateway deployed ✓"
}

# Deploy Ingress Gateway
deploy_ingress() {
    log_info "Deploying Ingress Gateway..."
    oc apply -f manifests/istio-ingress.yaml

    log_info "Configuring ingress service type..."
    oc annotate gateway istio-ingress -n istio-system \
      networking.istio.io/service-type=ClusterIP --overwrite

    sleep 10
    wait_for_deployment istio-system istio-ingress-istio 300
    log_info "Ingress Gateway deployed ✓"
}

# Create OpenShift Route
create_ingress_route() {
    log_info "Creating OpenShift Route with edge termination..."
    oc delete route mesh-ingress -n istio-system --ignore-not-found=true
    oc create route edge mesh-ingress \
      --service=istio-ingress-istio \
      --port=http \
      --insecure-policy=Redirect \
      -n istio-system
    log_info "OpenShift Route created ✓"
}

# Apply Traffic Routing
apply_routing() {
    log_info "Applying ingress routing..."
    oc apply -f manifests/ingress-routing.yaml
    log_info "Ingress routing configured ✓"
}

# Apply Network Policies
apply_network_policies() {
    if [ -f manifests/network-policy-lockdown.yaml ]; then
        log_info "Applying Zero-Trust Network Policies..."
        oc apply -f manifests/network-policy-lockdown.yaml
        log_info "Network policies applied ✓"
    fi
}

# Get access information
get_access_info() {
    log_info "Getting access information..."
    INGRESS_HOST=$(oc get route mesh-ingress -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null || echo "Route not found")

    echo ""
    echo "=========================================="
    echo "  Bookinfo Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Access URL: https://${INGRESS_HOST}/productpage"
    echo ""
    echo "Routing scenarios:"
    echo "  oc apply -f bookinfo/routing-scenarios/reviews-v1-only.yaml"
    echo "  oc apply -f bookinfo/routing-scenarios/reviews-v2-only.yaml"
    echo "  oc apply -f bookinfo/routing-scenarios/reviews-v3-only.yaml"
    echo ""
}

# Main deployment flow
main() {
    log_info "Starting OpenShift Service Mesh 3.3 (Ambient Mode) deployment..."

    check_prerequisites
    deploy_cni
    deploy_control_plane
    deploy_ztunnel
    deploy_bookinfo
    enroll_ambient
    deploy_waypoint
    deploy_ingress
    create_ingress_route
    apply_routing
    apply_network_policies

    get_access_info

    log_info "Deployment completed successfully! 🎉"
}

# Run main function
main
