#!/bin/bash

set -e

echo "=========================================="
echo "  Vérification du Distributed Tracing"
echo "=========================================="
echo

# Couleurs pour output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_pod() {
    local app=$1
    local namespace=${2:-istio-system}

    echo -n "📦 Checking $app pod in $namespace... "

    # Pour Tempo, vérifier le StatefulSet pod
    if [ "$app" = "tempo" ]; then
        if oc get pod tempo-tempo-0 -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; then
            echo -e "${GREEN}✅ Running${NC}"
            return 0
        else
            echo -e "${RED}❌ Not Running${NC}"
            return 1
        fi
    else
        if oc get pods -n "$namespace" -l "app=$app" -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
            echo -e "${GREEN}✅ Running${NC}"
            return 0
        else
            echo -e "${RED}❌ Not Running${NC}"
            return 1
        fi
    fi
}

check_service() {
    local name=$1
    local namespace=${2:-istio-system}

    echo -n "🔌 Checking service $name in $namespace... "

    # Pour Tempo, vérifier le service créé par l'opérateur
    if [ "$name" = "tempo" ]; then
        if oc get svc tempo-tempo -n "$namespace" &> /dev/null; then
            echo -e "${GREEN}✅ Exists (tempo-tempo)${NC}"
            return 0
        else
            echo -e "${RED}❌ Not Found${NC}"
            return 1
        fi
    else
        if oc get svc "$name" -n "$namespace" &> /dev/null; then
            echo -e "${GREEN}✅ Exists${NC}"
            return 0
        else
            echo -e "${RED}❌ Not Found${NC}"
            return 1
        fi
    fi
}

check_telemetry() {
    local name=$1
    local namespace=$2

    echo -n "📡 Checking Telemetry $name in $namespace... "
    if oc get telemetry "$name" -n "$namespace" &> /dev/null; then
        echo -e "${GREEN}✅ Configured${NC}"
        return 0
    else
        echo -e "${RED}❌ Not Found${NC}"
        return 1
    fi
}

echo "🔍 [1/5] Vérification de la CR TempoMonolithic..."
echo
echo -n "📡 Checking TempoMonolithic CR... "
if oc get tempomonolithic tempo -n istio-system &> /dev/null; then
    STATUS=$(oc get tempomonolithic tempo -n istio-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$STATUS" = "True" ]; then
        echo -e "${GREEN}✅ Ready${NC}"
    else
        echo -e "${YELLOW}⚠️  Status: $STATUS${NC}"
    fi
else
    echo -e "${RED}❌ Not Found${NC}"
fi
echo

echo "🔍 [2/5] Vérification des pods..."
echo
check_pod "tempo"
check_pod "otel-collector"
echo

echo "🔍 [3/5] Vérification des services..."
echo
check_service "tempo"
check_service "otel-collector"
echo

echo "🔍 [4/5] Vérification de la configuration Telemetry..."
echo
check_telemetry "mesh-tracing" "istio-system"
check_telemetry "bookinfo-tracing" "bookinfo" || echo -e "   ${YELLOW}⚠️  Optionnel - seulement si bookinfo est déployé${NC}"
echo

echo "🔍 [5/5] Vérification de la configuration Istio..."
echo
echo -n "⚙️  Checking Istio tracing configuration... "
if oc get istio default -n istio-system -o yaml | grep -q "enableTracing: true"; then
    echo -e "${GREEN}✅ Enabled${NC}"
else
    echo -e "${RED}❌ Not Enabled${NC}"
    echo -e "   ${YELLOW}Appliquer: oc apply -f tracing/manifests/istio-tracing-config.yaml${NC}"
fi
echo

# Test de connectivité
echo "=========================================="
echo "  🧪 Tests de connectivité"
echo "=========================================="
echo

echo "🔌 Test OTLP endpoint (OpenTelemetry Collector)..."
if oc run test-otel --image=curlimages/curl --rm -i --restart=Never --timeout=10s -- \
    curl -s -o /dev/null -w "%{http_code}" http://otel-collector.istio-system.svc.cluster.local:4318/v1/traces 2>/dev/null | grep -q "405\|200"; then
    echo -e "${GREEN}✅ OpenTelemetry Collector reachable${NC}"
else
    echo -e "${RED}❌ OpenTelemetry Collector not reachable${NC}"
fi
echo

echo "🔌 Test Tempo API endpoint..."
if oc run test-tempo --image=curlimages/curl --rm -i --restart=Never --timeout=10s -- \
    curl -s http://tempo-tempo.istio-system.svc.cluster.local:3200/ready 2>/dev/null | grep -q "ready"; then
    echo -e "${GREEN}✅ Tempo API ready${NC}"
else
    echo -e "${YELLOW}⚠️  Tempo API not ready (may need more time)${NC}"
fi
echo

echo "🔌 Test Jaeger UI route (sans OAuth)..."
JAEGER_ROUTE=$(oc get route jaeger-query -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -n "$JAEGER_ROUTE" ]; then
    echo -e "${GREEN}✅ Jaeger UI route exists (sans OAuth)${NC}"
    echo "   URL: https://${JAEGER_ROUTE}"
else
    echo -e "${YELLOW}⚠️  Route jaeger-query non trouvée${NC}"
    echo "   Vérifier: oc get route jaeger-query -n istio-system"
fi
echo

# Vérifier les traces
echo "=========================================="
echo "  🔎 Recherche de traces"
echo "=========================================="
echo

echo "⏳ Recherche de traces dans Tempo..."
echo "   (Assurez-vous d'avoir généré du trafic d'abord)"
echo

# Port-forward temporaire pour tester
oc port-forward -n istio-system svc/tempo-tempo 3200:3200 > /dev/null 2>&1 &
PF_PID=$!
sleep 3

# Vérifier si des services ont envoyé des traces
SERVICES=$(curl -s http://localhost:3200/api/search/tags 2>/dev/null | grep -o '"service.name"' || echo "")

kill $PF_PID 2>/dev/null || true

if [ -n "$SERVICES" ]; then
    echo -e "${GREEN}✅ Traces trouvées dans Tempo${NC}"
    echo
    echo "   Pour voir les détails:"
    echo "   oc port-forward -n istio-system svc/tempo-tempo 3200:3200"
    echo "   curl http://localhost:3200/api/search/tags | jq"
else
    echo -e "${YELLOW}⚠️  Aucune trace trouvée${NC}"
    echo
    echo "   Générer du trafic pour créer des traces:"
    echo "   cd ../../scripts && ./generate-traffic.sh"
fi
echo

# URLs d'accès
echo "=========================================="
echo "  🌐 URLs d'accès"
echo "=========================================="
echo

JAEGER_ROUTE=$(oc get route jaeger-query -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -n "$JAEGER_ROUTE" ]; then
    echo "Jaeger UI (sans OAuth):"
    echo "  https://${JAEGER_ROUTE}"
    echo
    echo "Pour explorer les traces:"
    echo "  1. Ouvrir Jaeger UI dans le navigateur (pas d'authentification requise)"
    echo "  2. Search → Service: productpage.bookinfo"
    echo "  3. Cliquer sur Find Traces"
    echo "  4. Cliquer sur une trace pour voir les détails"
else
    echo -e "${YELLOW}⚠️  Route Jaeger UI non trouvée${NC}"
    echo "  Vérifier: oc get route jaeger-query -n istio-system"
    echo "  Redéployer: cd tracing/scripts && ./deploy-tracing.sh"
fi
echo

# Résumé
echo "=========================================="
echo "  📋 Résumé"
echo "=========================================="
echo

ALL_OK=true

if ! oc get pod tempo-tempo-0 -n istio-system -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; then
    ALL_OK=false
fi
if ! oc get pods -n istio-system -l app=otel-collector -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
    ALL_OK=false
fi

if [ "$ALL_OK" = true ]; then
    echo -e "${GREEN}✅ Tous les composants sont opérationnels${NC}"
    echo
    echo "📝 Prochaines étapes:"
    echo "   1. Générer du trafic: cd ../../scripts && ./generate-traffic.sh"
    echo "   2. Ouvrir Grafana et explorer les traces"
    echo "   3. Analyser les spans et la latence"
else
    echo -e "${RED}❌ Certains composants ne sont pas opérationnels${NC}"
    echo
    echo "📝 Actions recommandées:"
    echo "   1. Vérifier les logs: oc logs -n istio-system -l app=tempo"
    echo "   2. Vérifier les logs: oc logs -n istio-system -l app=otel-collector"
    echo "   3. Redéployer si nécessaire: ./deploy-tracing.sh"
fi
echo
