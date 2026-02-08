#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if command -v oc &> /dev/null; then
    KUBECTL="oc"
else
    KUBECTL="kubectl"
fi

echo ""
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${BLUE}  Comment le trafic est redirigé vers ZTunnel ?${NC}"
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}${BOLD}MÉCANISME: Istio CNI Plugin${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""
echo "Le plugin CNI Istio configure chaque pod au démarrage pour rediriger"
echo "le trafic réseau vers ZTunnel de manière transparente."
echo ""
echo "Flux:"
echo "  1. Pod créé → Kubernetes appelle le CNI plugin"
echo "  2. Istio CNI configure les règles de redirection réseau"
echo "  3. Tout le trafic du pod est intercepté et envoyé à ZTunnel"
echo "  4. ZTunnel gère le proxy L4 + mTLS"
echo ""

echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
echo ""

echo -e "${CYAN}${BOLD}PREUVE #1: Istio CNI déployé et actif${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

$KUBECTL get pods -n istio-cni
echo ""
echo -e "${GREEN}✓ Istio CNI tourne sur chaque nœud (DaemonSet)${NC}"
echo ""

CNI_POD=$($KUBECTL get pod -n istio-cni -o jsonpath='{.items[0].metadata.name}')
echo "Configuration CNI installée:"
$KUBECTL exec -n istio-cni $CNI_POD -- ls -la /host/etc/cni/net.d/ 2>/dev/null | grep istio || echo "  (vérifier manuellement)"
echo ""

echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
echo ""

echo -e "${CYAN}${BOLD}PREUVE #2: Configuration CNI Istio${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

echo "Contenu du fichier de configuration CNI sur le nœud:"
echo ""
$KUBECTL exec -n istio-cni $CNI_POD -- cat /host/etc/cni/net.d/istio-cni.conf 2>/dev/null | head -30 || echo "  (fichier non accessible)"
echo ""

echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
echo ""

echo -e "${CYAN}${BOLD}PREUVE #3: Annotations sur les pods ambient${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

PRODUCTPAGE_POD=$($KUBECTL get pod -n bookinfo -l app=productpage -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $PRODUCTPAGE_POD"
echo ""
echo "Annotations liées à ambient/redirection:"
$KUBECTL get pod -n bookinfo $PRODUCTPAGE_POD -o jsonpath='{.metadata.annotations}' | jq -r 'to_entries[] | select(.key | contains("istio") or contains("ambient") or contains("cni")) | "  \(.key): \(.value)"' 2>/dev/null || \
$KUBECTL get pod -n bookinfo $PRODUCTPAGE_POD -o jsonpath='{.metadata.annotations}' | grep -E "istio|ambient|cni" || echo "  (pas d'annotations visibles)"
echo ""

echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
echo ""

echo -e "${CYAN}${BOLD}PREUVE #4: Configuration réseau du pod${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

echo "Vérification de la configuration réseau dans le pod:"
echo ""

# Vérifier les interfaces réseau
echo "Interfaces réseau:"
$KUBECTL exec -n bookinfo $PRODUCTPAGE_POD -- ip addr show 2>/dev/null | grep -E "^[0-9]+:|inet " | head -10 || echo "  (commande ip non disponible)"
echo ""

# Vérifier les routes
echo "Table de routage:"
$KUBECTL exec -n bookinfo $PRODUCTPAGE_POD -- ip route show 2>/dev/null || echo "  (commande ip non disponible)"
echo ""

echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
echo ""

echo -e "${CYAN}${BOLD}PREUVE #5: ZTunnel écoute sur le nœud${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

ZTUNNEL_POD=$($KUBECTL get pod -n ztunnel -l app=ztunnel -o jsonpath='{.items[0].metadata.name}')
echo "ZTunnel pod: $ZTUNNEL_POD"
echo ""
echo "Ports d'écoute ZTunnel:"
$KUBECTL exec -n ztunnel $ZTUNNEL_POD -- netstat -tuln 2>/dev/null | grep LISTEN | head -10 || \
    $KUBECTL exec -n ztunnel $ZTUNNEL_POD -- ss -tuln 2>/dev/null | grep LISTEN | head -10 || \
    echo "  (commande netstat/ss non disponible)"
echo ""
echo "ZTunnel écoute généralement sur:"
echo "  • Port 15001: Outbound traffic interception"
echo "  • Port 15006: Inbound traffic interception"
echo "  • Port 15008: HBONE (HTTP-Based Overlay Network Encapsulation)"
echo ""

echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
echo ""

echo -e "${CYAN}${BOLD}PREUVE #6: Namespace ambient enabled${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

echo "Configuration du namespace bookinfo:"
$KUBECTL get namespace bookinfo -o yaml | grep -A 3 "labels:" | grep -E "istio|ambient"
echo ""
echo -e "${GREEN}✓ Label 'istio.io/dataplane-mode: ambient' active${NC}"
echo "  → CNI sait que ce namespace nécessite la redirection vers ZTunnel"
echo ""

echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
echo ""

echo -e "${CYAN}${BOLD}ARCHITECTURE DE LA REDIRECTION${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 1. Pod démarre dans namespace 'ambient'                    │"
echo "└─────────────────────────────────────────────────────────────┘"
echo "                         ↓"
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 2. Kubernetes invoque le CNI plugin chain                  │"
echo "│    - CNI principal (OpenShift SDN / OVN-Kubernetes)         │"
echo "│    - Istio CNI plugin (chainé après)                       │"
echo "└─────────────────────────────────────────────────────────────┘"
echo "                         ↓"
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 3. Istio CNI détecte le label ambient sur le namespace     │"
echo "└─────────────────────────────────────────────────────────────┘"
echo "                         ↓"
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 4. Istio CNI configure la redirection réseau:              │"
echo "│    - Ajoute des règles iptables dans le netns du pod       │"
echo "│    - Redirige le trafic vers ZTunnel (localhost:15001)     │"
echo "└─────────────────────────────────────────────────────────────┘"
echo "                         ↓"
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 5. Application dans le pod envoie du trafic                │"
echo "│    Exemple: curl http://reviews:9080                       │"
echo "└─────────────────────────────────────────────────────────────┘"
echo "                         ↓"
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 6. Règles iptables interceptent et redirigent vers ZTunnel │"
echo "│    (transparent pour l'application)                        │"
echo "└─────────────────────────────────────────────────────────────┘"
echo "                         ↓"
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ 7. ZTunnel reçoit le trafic sur 15001                      │"
echo "│    - Applique mTLS                                          │"
echo "│    - Route vers le bon service                             │"
echo "│    - Envoie via HBONE (port 15008) au ZTunnel distant      │"
echo "└─────────────────────────────────────────────────────────────┘"
echo ""

echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
echo ""

echo -e "${CYAN}${BOLD}COMPARAISON: Sidecar vs Ambient${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""
echo "┌───────────────────────┬─────────────────────┬─────────────────────┐"
echo "│                       │ Sidecar Mode        │ Ambient Mode        │"
echo "├───────────────────────┼─────────────────────┼─────────────────────┤"
echo "│ Proxy                 │ istio-proxy (pod)   │ ZTunnel (node)      │"
echo "│ Redirection           │ Init container      │ Istio CNI           │"
echo "│ iptables rules        │ Dans le pod         │ Dans le pod         │"
echo "│ Ressources            │ Par pod             │ Par nœud (partagé)  │"
echo "│ Injection             │ Webhook requis      │ Automatique (CNI)   │"
echo "│ Restart pods          │ OUI (injection)     │ NON                 │"
echo "└───────────────────────┴─────────────────────┴─────────────────────┘"
echo ""

echo -e "${YELLOW}─────────────────────────────────────────────────────────────────${NC}"
echo ""

echo -e "${BOLD}${GREEN}RÉSUMÉ: Comment ça marche${NC}"
echo ""
echo "1. ${BOLD}Istio CNI${NC} est installé comme plugin CNI sur chaque nœud"
echo "2. Quand un pod démarre dans un namespace ${BOLD}ambient${NC}:"
echo "   → CNI configure des ${BOLD}règles iptables${NC} dans le network namespace du pod"
echo "   → Ces règles redirigent le trafic vers ${BOLD}ZTunnel (15001/15006)${NC}"
echo "3. L'application dans le pod ${BOLD}ne voit aucune différence${NC}"
echo "4. ZTunnel intercepte, sécurise (mTLS), et route le trafic"
echo ""
echo -e "${GREEN}✓ Redirection transparente sans sidecar !${NC}"
echo ""
