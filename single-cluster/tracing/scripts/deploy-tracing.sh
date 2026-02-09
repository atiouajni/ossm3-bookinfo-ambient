#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo "=========================================="
echo "  Déploiement Distributed Tracing"
echo "  - Grafana Tempo (avec Jaeger UI)"
echo "  - OpenTelemetry Collector"
echo "=========================================="
echo

# Vérifier que Istio est déployé
echo "🔍 Vérification des prérequis..."

# Vérifier Tempo Operator
if ! oc get crd tempomonolithics.tempo.grafana.com &> /dev/null; then
    echo "❌ Erreur: Tempo Operator n'est pas installé"
    echo
    echo "Installation via console OpenShift:"
    echo "  Operators → OperatorHub → 'Tempo Operator' → Install"
    echo
    echo "Ou via CLI:"
    echo "  oc apply -f - <<EOF"
    echo "  apiVersion: operators.coreos.com/v1alpha1"
    echo "  kind: Subscription"
    echo "  metadata:"
    echo "    name: tempo-operator"
    echo "    namespace: openshift-operators"
    echo "  spec:"
    echo "    channel: stable"
    echo "    name: tempo-operator"
    echo "    source: redhat-operators"
    echo "    sourceNamespace: openshift-marketplace"
    echo "  EOF"
    echo
    exit 1
fi
echo "✅ Tempo Operator installé"

if ! oc get namespace istio-system &> /dev/null; then
    echo "❌ Erreur: Le namespace istio-system n'existe pas"
    echo "   Déployez d'abord Istio avec: cd ../../scripts && ./deploy-istio.sh"
    exit 1
fi

if ! oc get deployment istiod -n istio-system &> /dev/null; then
    echo "❌ Erreur: Istio n'est pas déployé"
    echo "   Déployez d'abord Istio avec: cd ../../scripts && ./deploy-istio.sh"
    exit 1
fi

# Vérifier que Prometheus existe
if ! oc get deployment prometheus -n istio-system &> /dev/null; then
    echo "⚠️  Avertissement: Prometheus n'est pas déployé"
    echo "   Les métriques depuis Tempo ne seront pas disponibles"
    echo "   Pour déployer Prometheus: cd ../../scripts && ./deploy-kiali.sh"
    echo
fi

echo "✅ Prérequis validés"
echo

# Étape 1: Déployer Tempo via TempoMonolithic CR (avec Jaeger UI)
echo "📦 [1/5] Déploiement de Grafana Tempo avec Jaeger UI (via TempoMonolithic)..."
oc apply -f "${MANIFESTS_DIR}/tempo.yaml"
echo "⏳ Attente du démarrage de Tempo..."
# Attendre que le StatefulSet soit créé par l'opérateur
sleep 10
oc wait --for=jsonpath='{.status.replicas}'=1 statefulset/tempo-tempo -n istio-system --timeout=120s 2>/dev/null || true
oc wait --for=condition=ready pod/tempo-tempo-0 -n istio-system --timeout=120s 2>/dev/null || true
sleep 5
echo "✅ Tempo déployé avec Jaeger UI"
echo

# Étape 2: Créer une route sans OAuth pour Jaeger UI
echo "📦 [2/5] Création d'une route sans OAuth pour Jaeger UI..."
oc apply -f "${MANIFESTS_DIR}/jaeger-route.yaml"
sleep 2
echo "✅ Route Jaeger UI créée (sans OAuth)"
echo

# Étape 3: Déployer OpenTelemetry Collector
echo "📦 [3/5] Déploiement de OpenTelemetry Collector..."
oc apply -f "${MANIFESTS_DIR}/otel-collector.yaml"
echo "⏳ Attente du démarrage de OpenTelemetry Collector..."
oc wait --for=condition=available --timeout=120s deployment/otel-collector -n istio-system || true
sleep 5
echo "✅ OpenTelemetry Collector déployé"
echo

# Étape 4: Configurer Istio pour le tracing
echo "⚙️  [4/5] Configuration d'Istio pour le tracing..."
oc apply -f "${MANIFESTS_DIR}/istio-tracing-config.yaml"
echo "⏳ Attente du redémarrage d'istiod..."
oc rollout status deployment/istiod -n istio-system --timeout=120s || true
sleep 10
echo "✅ Configuration Istio appliquée"
echo

# Étape 5: Activer le tracing via Telemetry API
echo "📡 [5/5] Activation du tracing via Telemetry API..."
oc apply -f "${MANIFESTS_DIR}/telemetry.yaml"
sleep 5
echo "✅ Tracing activé"
echo

# Vérification finale
echo "=========================================="
echo "  🎉 Déploiement terminé!"
echo "=========================================="
echo

echo "📊 État des composants:"
oc get pods -n istio-system | grep -E '(tempo|otel|NAME)' || echo "Aucun pod trouvé"
echo

echo "🔍 Telemetry resources:"
oc get telemetry -A
echo

# Récupérer l'URL de Jaeger UI (route sans OAuth)
JAEGER_ROUTE=$(oc get route jaeger-query -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -n "$JAEGER_ROUTE" ]; then
    echo "🌐 Jaeger UI est accessible (sans OAuth):"
    echo "   https://${JAEGER_ROUTE}"
    echo
    echo "📝 Note: Une route 'jaeger-query' a été créée sans authentification OAuth"
    echo "   pour un accès direct. La route par défaut de l'opérateur"
    echo "   (tempo-tempo-jaegerui) utilise OAuth et peut causer des erreurs."
    echo
else
    echo "⚠️  Route Jaeger UI non trouvée"
    echo "   Vérifier avec: oc get route jaeger-query -n istio-system"
    echo
fi

echo "📝 Prochaines étapes:"
echo
echo "1. Générer du trafic vers Bookinfo:"
echo "   cd ../../scripts && ./generate-traffic.sh"
echo
echo "2. Ouvrir Jaeger UI et explorer les traces:"
echo "   - Search → Service: productpage.bookinfo"
echo "   - Cliquer sur Find Traces"
echo "   - Interface familière pour ceux qui connaissent Jaeger"
echo
echo "3. Voir les traces directement dans Tempo API:"
echo "   oc port-forward -n istio-system svc/tempo-tempo 3200:3200"
echo "   curl http://localhost:3200/api/search/tags | jq"
echo
echo "4. Vérifier les logs pour debugger:"
echo "   oc logs -n istio-system -l app=otel-collector"
echo "   oc logs -n istio-system -l app=tempo"
echo
echo "📖 Documentation complète: tracing/README.md"
echo
