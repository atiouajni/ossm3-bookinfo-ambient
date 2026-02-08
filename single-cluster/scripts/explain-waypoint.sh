#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
echo -e "${BLUE}  Waypoint Proxy in Ambient Mode${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${CYAN}Qu'est-ce qu'un Waypoint Proxy ?${NC}"
echo ""
echo "En mode Ambient, Istio utilise deux niveaux de proxy :"
echo ""
echo "1. ${GREEN}ZTunnel (L4)${NC} :"
echo "   - Proxy au niveau Layer 4 (réseau)"
echo "   - Gère mTLS, connectivité de base"
echo "   - DaemonSet sur chaque nœud"
echo "   - Transparent, pas de configuration nécessaire"
echo ""
echo "2. ${GREEN}Waypoint Proxy (L7)${NC} :"
echo "   - Proxy au niveau Layer 7 (application)"
echo "   - Gère les fonctionnalités avancées :"
echo "     • VirtualServices (routage avancé)"
echo "     • DestinationRules (load balancing, circuit breaker)"
echo "     • Fault injection"
echo "     • Traffic splitting (canary, A/B testing)"
echo "   - Déployé uniquement quand nécessaire"
echo "   - Un pod par namespace (ou par service)"
echo ""

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Architecture Ambient avec Waypoint${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

cat <<'EOF'
Sans Waypoint (L4 uniquement) :
┌─────────────┐           ┌─────────────┐
│ productpage │           │  reviews v1 │
│    pod      │──────────▶│     pod     │
└─────────────┘           └─────────────┘
      │                         ▲
      │                         │
      └──▶ ZTunnel ──────▶ ZTunnel
         (mTLS only)

Avec Waypoint (L4 + L7) :
┌─────────────┐                           ┌─────────────┐
│ productpage │                           │  reviews v1 │
│    pod      │                           │     pod     │
└─────────────┘                           └─────────────┘
      │                                         ▲
      │                                         │
      └──▶ ZTunnel ──▶ Waypoint ──▶ ZTunnel ───┘
         (mTLS)      (L7 routing)    (mTLS)
                     VirtualService
                     DestinationRule
EOF

echo ""
echo ""
echo -e "${YELLOW}Vérification du Waypoint${NC}"
echo ""

# Check if waypoint exists
if $KUBECTL get gateway waypoint -n bookinfo &>/dev/null; then
    echo -e "${GREEN}✓ Waypoint proxy est déployé${NC}"
    echo ""

    # Show waypoint details
    echo "Détails du Gateway :"
    $KUBECTL get gateway waypoint -n bookinfo

    echo ""
    echo "Pod Waypoint :"
    $KUBECTL get pods -n bookinfo -l gateway.networking.k8s.io/gateway-name=waypoint

    echo ""
    echo "Services utilisant le waypoint :"
    $KUBECTL get services -n bookinfo -l istio.io/use-waypoint=waypoint -o custom-columns=NAME:.metadata.name,USE-WAYPOINT:.metadata.labels.istio\\.io/use-waypoint

else
    echo -e "${YELLOW}⚠ Waypoint proxy n'est pas déployé${NC}"
    echo ""
    echo "Sans waypoint, seul le trafic L4 (mTLS) est géré."
    echo "Les VirtualServices et DestinationRules ne fonctionneront PAS."
    echo ""
    echo "Pour déployer le waypoint :"
    echo -e "  ${CYAN}kubectl apply -f manifests/waypoint.yaml${NC}"
    echo ""
    echo "Puis labelliser les services :"
    echo -e "  ${CYAN}kubectl label service reviews -n bookinfo istio.io/use-waypoint=waypoint${NC}"
fi

echo ""
echo -e "${YELLOW}Quand utiliser le Waypoint ?${NC}"
echo ""
echo "✅ ${GREEN}Utilisez le waypoint si vous avez besoin de :${NC}"
echo "   • Traffic splitting (canary, A/B testing)"
echo "   • Routage basé sur les headers/URL"
echo "   • Fault injection"
echo "   • Circuit breaking"
echo "   • Request timeouts/retries"
echo ""
echo "❌ ${YELLOW}Pas besoin de waypoint si vous voulez seulement :${NC}"
echo "   • mTLS entre services"
echo "   • Métriques de base"
echo "   • Load balancing simple"
echo ""

echo -e "${BLUE}========================================${NC}"
echo ""
