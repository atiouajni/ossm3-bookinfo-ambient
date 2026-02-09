#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo "=========================================="
echo "  Déploiement Distributed Tracing"
echo "  - Grafana Tempo"
echo "  - OpenTelemetry Collector"
echo "  - Grafana"
echo "=========================================="
echo

# Vérifier que Istio est déployé
echo "🔍 Vérification des prérequis..."
if ! kubectl get namespace istio-system &> /dev/null; then
    echo "❌ Erreur: Le namespace istio-system n'existe pas"
    echo "   Déployez d'abord Istio avec: cd ../scripts && ./deploy-istio.sh"
    exit 1
fi

if ! kubectl get deployment istiod -n istio-system &> /dev/null; then
    echo "❌ Erreur: Istio n'est pas déployé"
    echo "   Déployez d'abord Istio avec: cd ../scripts && ./deploy-istio.sh"
    exit 1
fi

# Vérifier que Prometheus existe
if ! kubectl get deployment prometheus -n istio-system &> /dev/null; then
    echo "⚠️  Avertissement: Prometheus n'est pas déployé"
    echo "   Les métriques depuis Tempo ne seront pas disponibles"
    echo "   Pour déployer Prometheus: cd ../scripts && ./deploy-kiali.sh"
    echo
fi

echo "✅ Prérequis validés"
echo

# Étape 1: Déployer Tempo
echo "📦 [1/5] Déploiement de Grafana Tempo..."
kubectl apply -f "${MANIFESTS_DIR}/tempo.yaml"
echo "⏳ Attente du démarrage de Tempo..."
kubectl wait --for=condition=available --timeout=120s deployment/tempo -n istio-system || true
sleep 5
echo "✅ Tempo déployé"
echo

# Étape 2: Déployer OpenTelemetry Collector
echo "📦 [2/5] Déploiement de OpenTelemetry Collector..."
kubectl apply -f "${MANIFESTS_DIR}/otel-collector.yaml"
echo "⏳ Attente du démarrage de OpenTelemetry Collector..."
kubectl wait --for=condition=available --timeout=120s deployment/otel-collector -n istio-system || true
sleep 5
echo "✅ OpenTelemetry Collector déployé"
echo

# Étape 3: Déployer Grafana
echo "📦 [3/5] Déploiement de Grafana..."
kubectl apply -f "${MANIFESTS_DIR}/grafana.yaml"
echo "⏳ Attente du démarrage de Grafana..."
kubectl wait --for=condition=available --timeout=120s deployment/grafana -n istio-system || true
sleep 5
echo "✅ Grafana déployé"
echo

# Étape 4: Configurer Istio pour le tracing
echo "⚙️  [4/5] Configuration d'Istio pour le tracing..."
kubectl apply -f "${MANIFESTS_DIR}/istio-tracing-config.yaml"
echo "⏳ Attente du redémarrage d'istiod..."
kubectl rollout status deployment/istiod -n istio-system --timeout=120s || true
sleep 10
echo "✅ Configuration Istio appliquée"
echo

# Étape 5: Activer le tracing via Telemetry API
echo "📡 [5/5] Activation du tracing via Telemetry API..."
kubectl apply -f "${MANIFESTS_DIR}/telemetry.yaml"
sleep 5
echo "✅ Tracing activé"
echo

# Vérification finale
echo "=========================================="
echo "  🎉 Déploiement terminé!"
echo "=========================================="
echo

echo "📊 État des composants:"
kubectl get pods -n istio-system | grep -E '(tempo|otel|grafana|NAME)' || echo "Aucun pod trouvé"
echo

echo "🔍 Telemetry resources:"
kubectl get telemetry -A
echo

# Récupérer l'URL de Grafana
GRAFANA_ROUTE=$(kubectl get route grafana -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -n "$GRAFANA_ROUTE" ]; then
    echo "🌐 Grafana est accessible à:"
    echo "   https://${GRAFANA_ROUTE}"
    echo
else
    echo "⚠️  Route Grafana non trouvée"
    echo "   Créer manuellement ou attendre quelques secondes"
    echo
fi

echo "📝 Prochaines étapes:"
echo
echo "1. Générer du trafic vers Bookinfo:"
echo "   cd ../../scripts && ./generate-traffic.sh"
echo
echo "2. Ouvrir Grafana et explorer les traces:"
echo "   - Explore → Tempo"
echo "   - Service Name: productpage.bookinfo"
echo "   - Run Query"
echo
echo "3. Voir les traces directement dans Tempo API:"
echo "   kubectl port-forward -n istio-system svc/tempo 3200:3200"
echo "   curl http://localhost:3200/api/search/tags | jq"
echo
echo "4. Vérifier les logs pour debugger:"
echo "   kubectl logs -n istio-system -l app=otel-collector"
echo "   kubectl logs -n istio-system -l app=tempo"
echo
echo "📖 Documentation complète: tracing/README.md"
echo
