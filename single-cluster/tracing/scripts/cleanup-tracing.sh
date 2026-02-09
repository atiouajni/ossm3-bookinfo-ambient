#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../manifests"

echo "=========================================="
echo "  Nettoyage Distributed Tracing"
echo "=========================================="
echo

echo "⚠️  Cette action va supprimer:"
echo "   - Grafana Tempo (avec Jaeger UI) et ses données"
echo "   - OpenTelemetry Collector"
echo "   - Configuration de tracing Istio"
echo "   - Ressources Telemetry"
echo
echo "❌ Cette action ne supprime PAS:"
echo "   - Istio infrastructure"
echo "   - Bookinfo application"
echo "   - Prometheus"
echo "   - Kiali"
echo

read -p "Continuer? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Annulé"
    exit 0
fi

echo

# Supprimer les ressources Telemetry
echo "🗑️  [1/5] Suppression des ressources Telemetry..."
oc delete telemetry mesh-tracing -n istio-system --ignore-not-found=true
oc delete telemetry bookinfo-tracing -n bookinfo --ignore-not-found=true
echo "✅ Telemetry supprimé"
echo

# Restaurer la configuration Istio sans tracing
echo "⚙️  [2/5] Restauration de la configuration Istio..."
cat <<EOF | oc apply -f -
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: default
spec:
  version: v1.27.3
  namespace: istio-system
  profile: ambient
  values:
    global:
      meshID: mesh1
    pilot:
      trustedZtunnelNamespace: ztunnel
EOF

echo "⏳ Attente du redémarrage d'istiod..."
oc rollout status deployment/istiod -n istio-system --timeout=120s || true
sleep 10
echo "✅ Configuration Istio restaurée"
echo

# Supprimer OpenTelemetry Collector
echo "🗑️  [3/5] Suppression de OpenTelemetry Collector..."
oc delete -f "${MANIFESTS_DIR}/otel-collector.yaml" --ignore-not-found=true
echo "✅ OpenTelemetry Collector supprimé"
echo

# Supprimer la route Jaeger sans OAuth
echo "🗑️  [4/5] Suppression de la route Jaeger UI..."
oc delete route jaeger-query -n istio-system --ignore-not-found=true
echo "✅ Route Jaeger supprimée"
echo

# Supprimer Tempo (TempoMonolithic CR avec Jaeger UI)
echo "🗑️  [5/5] Suppression de Grafana Tempo (avec Jaeger UI)..."
oc delete tempomonolithic tempo -n istio-system --ignore-not-found=true
# Attendre que l'opérateur nettoie les ressources (y compris Jaeger UI route)
sleep 5
echo "✅ Tempo et Jaeger UI supprimés"
echo

# Vérification finale
echo "=========================================="
echo "  🎉 Nettoyage terminé!"
echo "=========================================="
echo

echo "📊 Vérification des ressources restantes:"
echo
echo "Pods dans istio-system:"
oc get pods -n istio-system | grep -E '(tempo|otel)' && echo "⚠️  Certains pods existent encore (en cours de suppression)" || echo "✅ Aucun pod de tracing trouvé"
echo

echo "Services dans istio-system:"
oc get svc -n istio-system | grep -E '(tempo|otel)' && echo "⚠️  Certains services existent encore" || echo "✅ Aucun service de tracing trouvé"
echo

echo "Routes dans istio-system:"
oc get route -n istio-system | grep -E '(tempo|jaeger)' && echo "⚠️  Certaines routes existent encore" || echo "✅ Aucune route de tracing trouvée"
echo

echo "Telemetry resources:"
oc get telemetry -A 2>/dev/null | grep -E '(mesh-tracing|bookinfo-tracing)' && echo "⚠️  Certaines ressources Telemetry existent encore" || echo "✅ Aucune ressource Telemetry trouvée"
echo

echo "📝 État du système:"
echo
echo "✅ Conservés:"
echo "   - Istio (istiod, ztunnel, CNI)"
echo "   - Bookinfo application"
echo "   - Prometheus (si déployé)"
echo "   - Kiali (si déployé)"
echo
echo "❌ Supprimés:"
echo "   - Tempo (traces perdues)"
echo "   - OpenTelemetry Collector"
echo "   - Grafana tracing"
echo "   - Configuration tracing Istio"
echo

echo "💡 Pour redéployer le tracing:"
echo "   cd tracing/scripts && ./deploy-tracing.sh"
echo
