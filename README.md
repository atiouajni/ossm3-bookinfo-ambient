# OpenShift Service Mesh 3.3 - Bookinfo Ambient Mode

Automated deployment of Bookinfo application on OpenShift Service Mesh 3.3 using Istio Ambient mode.

## Blog Post Reference
Based on: **"Integrating Your Applications Into the Istio Service Mesh"**  
Author: Anisse Tiouajni | Publication Date: June 6, 2026

## Architecture Overview

Ambient mode eliminates sidecars with a two-layer data plane:

```
Internet (HTTPS) → OpenShift Router (edge TLS)
  → Route → Istio Ingress Gateway
    → HTTPRoute (Gateway API)
      → Ztunnel (L4: mTLS, identity)
        → Waypoint (L7: routing, policies)
          → Application Pods
```

**Components:**
- **Ztunnel**: Node-level DaemonSet for L4 (mTLS, traffic capture via eBPF)
- **Waypoint**: Optional L7 proxy for advanced routing (HTTPRoute, VirtualService)
- **Gateway API**: Kubernetes-native traffic management (HTTPRoute, Gateway)

## Quick Start

### Automated Deployment

```bash
cd single-cluster
./deploy.sh
```

**Deploys in correct order:**
1. Istio CNI
2. Istio Control Plane (istiod)
3. Ztunnel (L4 proxy)
4. Bookinfo Application
5. Ambient mode enrollment
6. Waypoint Gateway (L7 proxy)
7. Istio Ingress Gateway
8. OpenShift Route (edge TLS with HTTP→HTTPS redirect)
9. HTTPRoute (ingress routing)
10. Network Policies

**Access URL**: `https://mesh-ingress-{namespace}.apps.{cluster-domain}/productpage`

### Testing

```bash
# Test routing distribution
./test-routing.sh

# Verify ambient mode
oc get ns bookinfo --show-labels | grep ambient
oc get gateway waypoint -n bookinfo
oc get httproute -n bookinfo
```

### Apply Routing Scenarios

```bash
# Route all traffic to v1 (no stars)
oc apply -f bookinfo/routing-scenarios/reviews-v1-only.yaml

# Route to v2 (black stars)
oc apply -f bookinfo/routing-scenarios/reviews-v2-only.yaml

# Route to v3 (red stars)
oc apply -f bookinfo/routing-scenarios/reviews-v3-only.yaml
```

### Cleanup

```bash
./cleanup.sh
```

## Manual Deployment

### Prerequisites
- OpenShift 4.x cluster
- OpenShift Service Mesh 3.3 Operator installed
- `oc` CLI configured

### Steps

```bash
# 1. Deploy Istio CNI (must be first)
oc create namespace istio-cni
oc apply -f manifests/istio-cni.yaml

# 2. Deploy Control Plane
oc create namespace istio-system
oc apply -f manifests/istio.yaml

# 3. Deploy Ztunnel (L4 proxy)
oc create namespace ztunnel
oc apply -f manifests/ztunnel.yaml

# 4. Deploy Bookinfo
oc create namespace bookinfo
oc apply -f bookinfo/bookinfo.yaml -n bookinfo
oc apply -f bookinfo/bookinfo-versions.yaml -n bookinfo

# 5. Enable Ambient mode
oc label namespace bookinfo istio.io/dataplane-mode=ambient
oc label namespace bookinfo istio.io/use-waypoint=waypoint

# 6. Deploy Waypoint (L7 proxy)
oc apply -f manifests/waypoint.yaml

# 7. Deploy Ingress Gateway
oc apply -f manifests/istio-ingress.yaml
oc annotate gateway istio-ingress -n istio-system \
  networking.istio.io/service-type=ClusterIP --overwrite

# 8. Create OpenShift Route (edge TLS)
oc create route edge mesh-ingress \
  --service=istio-ingress-istio \
  --port=http \
  --insecure-policy=Redirect \
  -n istio-system

# 9. Configure Ingress Routing
oc apply -f manifests/ingress-routing.yaml

# 10. Apply Network Policies
oc apply -f manifests/network-policy-lockdown.yaml
```

## Key Features

### HTTPRoute for L7 Routing
Uses Kubernetes Gateway API instead of Istio VirtualService:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: reviews
  namespace: bookinfo
spec:
  parentRefs:
  - kind: Service
    name: reviews
    port: 9080
  rules:
  - backendRefs:
    - name: reviews-v1
      port: 9080
      weight: 90
    - name: reviews-v2
      port: 9080
      weight: 10
```

### Ambient-Compatible Network Policy
Allows traffic from ztunnel, waypoint, and within namespace:

```yaml
ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ztunnel
  - from:
    - podSelector:
        matchLabels:
          gateway.networking.k8s.io/gateway-name: waypoint
```

### OpenShift Route with Edge TLS
Terminates TLS at router, redirects HTTP→HTTPS:

```bash
oc create route edge mesh-ingress \
  --service=istio-ingress-istio \
  --port=http \
  --insecure-policy=Redirect \
  -n istio-system
```

## Troubleshooting

```bash
# Check all components
oc get pods -n istio-cni
oc get pods -n istio-system
oc get daemonset -n ztunnel
oc get pods -n bookinfo

# Check routing
oc get gateway -A
oc get httproute -A
oc describe httproute bookinfo-ingress -n bookinfo

# Test connectivity
curl -I https://mesh-ingress-istio-system.apps.{cluster}/productpage
```
