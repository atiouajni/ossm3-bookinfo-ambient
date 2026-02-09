#!/bin/bash

set -e

echo "=========================================="
echo "  Désactivation OAuth pour Jaeger UI"
echo "=========================================="
echo

# Vérifier que la route existe
if ! oc get route tempo-tempo-jaegerui -n istio-system &> /dev/null; then
    echo "❌ Erreur: Route tempo-tempo-jaegerui non trouvée"
    echo "   Attendez que l'opérateur Tempo crée la route"
    exit 1
fi

echo "📝 Suppression des annotations OAuth..."

# Supprimer les annotations OAuth de la route
oc annotate route tempo-tempo-jaegerui -n istio-system \
    haproxy.router.openshift.io/disable_cookies- \
    route.openshift.io/cookie_name- \
    --overwrite &> /dev/null || true

# Supprimer le service-account et autres configs OAuth si présentes
oc patch route tempo-tempo-jaegerui -n istio-system --type=json -p='[
  {"op": "remove", "path": "/metadata/annotations/route.openshift.io~1cookie_name"},
  {"op": "remove", "path": "/metadata/annotations/haproxy.router.openshift.io~1disable_cookies"}
]' 2>/dev/null || true

echo "✅ OAuth désactivé"
echo

# Afficher l'URL
JAEGER_URL=$(oc get route tempo-tempo-jaegerui -n istio-system -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -n "$JAEGER_URL" ]; then
    echo "🌐 Jaeger UI est maintenant accessible sans authentification:"
    echo "   https://${JAEGER_URL}"
    echo
    echo "💡 Si vous obtenez encore une erreur OAuth, essayez:"
    echo "   1. Vider le cache du navigateur"
    echo "   2. Utiliser une fenêtre privée/incognito"
    echo "   3. Redémarrer le pod Tempo:"
    echo "      oc delete pod tempo-tempo-0 -n istio-system"
    echo
else
    echo "⚠️  Route non trouvée"
fi
