#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  🔄 Mise à jour de la version Istio"
echo "=========================================="
echo

# Vérifier le paramètre
if [ -z "$1" ]; then
    echo -e "${RED}❌ Erreur: Version non spécifiée${NC}"
    echo
    echo "Usage: $0 <version>"
    echo
    echo "Exemples:"
    echo "  $0 v1.27.3"
    echo "  $0 v1.28.0"
    echo
    echo "💡 Pour voir les versions disponibles sur votre cluster:"
    echo "   oc get istiorevisions -n istio-system"
    echo
    exit 1
fi

NEW_VERSION="$1"

# Valider le format de la version
if [[ ! "$NEW_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}❌ Erreur: Format de version invalide${NC}"
    echo
    echo "Le format doit être: vX.Y.Z (ex: v1.27.3)"
    echo "Vous avez fourni: $NEW_VERSION"
    echo
    exit 1
fi

# Détecter la version actuelle
CURRENT_VERSION=$(grep -m1 "version: v" "${PROJECT_ROOT}/manifests/istio.yaml" | awk '{print $2}' || echo "unknown")

echo -e "${BLUE}ℹ️  Version actuelle: ${CURRENT_VERSION}${NC}"
echo -e "${BLUE}ℹ️  Nouvelle version: ${NEW_VERSION}${NC}"
echo

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
    echo -e "${YELLOW}⚠️  La version est déjà ${NEW_VERSION}${NC}"
    echo
    read -p "Voulez-vous forcer la mise à jour des fichiers? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Annulé"
        exit 0
    fi
fi

# Liste des fichiers à mettre à jour
FILES=(
    "manifests/istio.yaml"
    "manifests/istio-cni.yaml"
    "manifests/ztunnel.yaml"
    "tracing/manifests/istio-tracing-config.yaml"
    "tracing/scripts/cleanup-tracing.sh"
    "docs/index.html"
)

echo "📝 Fichiers qui seront mis à jour:"
echo
for file in "${FILES[@]}"; do
    if [ -f "${PROJECT_ROOT}/${file}" ]; then
        echo -e "  ${GREEN}✓${NC} ${file}"
    else
        echo -e "  ${YELLOW}⚠${NC} ${file} (non trouvé, sera ignoré)"
    fi
done
echo

read -p "Continuer? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Annulé"
    exit 0
fi

echo
echo "🔄 Mise à jour en cours..."
echo

UPDATED_COUNT=0
FAILED_COUNT=0

# Fonction pour mettre à jour un fichier
update_file() {
    local file=$1
    local full_path="${PROJECT_ROOT}/${file}"

    if [ ! -f "$full_path" ]; then
        echo -e "  ${YELLOW}⊘${NC} ${file} - Fichier non trouvé, ignoré"
        return
    fi

    # Détecter le pattern selon le type de fichier
    if [[ "$file" == *.yaml ]]; then
        # YAML files: "version: vX.Y.Z"
        if grep -q "version: v[0-9]\+\.[0-9]\+\.[0-9]\+" "$full_path"; then
            sed -i.bak "s/version: v[0-9]\+\.[0-9]\+\.[0-9]\+/version: ${NEW_VERSION}/g" "$full_path"
            rm -f "${full_path}.bak"
            echo -e "  ${GREEN}✓${NC} ${file}"
            ((UPDATED_COUNT++))
        else
            echo -e "  ${YELLOW}⊘${NC} ${file} - Pas de version trouvée"
        fi
    elif [[ "$file" == *.html ]]; then
        # HTML files: badge with version
        if grep -q "Istio v[0-9]\+\.[0-9]\+\.[0-9]\+" "$full_path"; then
            sed -i.bak "s/Istio v[0-9]\+\.[0-9]\+\.[0-9]\+/Istio ${NEW_VERSION}/g" "$full_path"
            rm -f "${full_path}.bak"
            echo -e "  ${GREEN}✓${NC} ${file}"
            ((UPDATED_COUNT++))
        else
            echo -e "  ${YELLOW}⊘${NC} ${file} - Pas de version trouvée"
        fi
    elif [[ "$file" == *.sh ]]; then
        # Shell scripts: embedded YAML in cat <<EOF
        if grep -q "version: v[0-9]\+\.[0-9]\+\.[0-9]\+" "$full_path"; then
            sed -i.bak "s/version: v[0-9]\+\.[0-9]\+\.[0-9]\+/version: ${NEW_VERSION}/g" "$full_path"
            rm -f "${full_path}.bak"
            echo -e "  ${GREEN}✓${NC} ${file}"
            ((UPDATED_COUNT++))
        else
            echo -e "  ${YELLOW}⊘${NC} ${file} - Pas de version trouvée"
        fi
    fi
}

# Mettre à jour chaque fichier
for file in "${FILES[@]}"; do
    update_file "$file"
done

echo

# Mettre à jour les warnings dans les README
echo "📄 Mise à jour des documentations..."
echo

# README principal
README_MAIN="${PROJECT_ROOT}/README.md"
if [ -f "$README_MAIN" ]; then
    if grep -q "configurée pour Istio \*\*v[0-9]\+\.[0-9]\+\.[0-9]\+\*\*" "$README_MAIN"; then
        sed -i.bak "s/configurée pour Istio \*\*v[0-9]\+\.[0-9]\+\.[0-9]\+\*\*/configurée pour Istio **${NEW_VERSION}**/g" "$README_MAIN"
        rm -f "${README_MAIN}.bak"
        echo -e "  ${GREEN}✓${NC} README.md"
        ((UPDATED_COUNT++))
    fi
fi

# README tracing
README_TRACING="${PROJECT_ROOT}/tracing/README.md"
if [ -f "$README_TRACING" ]; then
    if grep -q "configurés pour Istio \*\*v[0-9]\+\.[0-9]\+\.[0-9]\+\*\*" "$README_TRACING"; then
        sed -i.bak "s/configurés pour Istio \*\*v[0-9]\+\.[0-9]\+\.[0-9]\+\*\*/configurés pour Istio **${NEW_VERSION}**/g" "$README_TRACING"
        rm -f "${README_TRACING}.bak"
        echo -e "  ${GREEN}✓${NC} tracing/README.md"
        ((UPDATED_COUNT++))
    fi
fi

echo

# Vérification finale
echo "=========================================="
echo "  ✅ Mise à jour terminée!"
echo "=========================================="
echo
echo -e "${GREEN}✓ ${UPDATED_COUNT} fichiers mis à jour${NC}"

if [ $FAILED_COUNT -gt 0 ]; then
    echo -e "${RED}✗ ${FAILED_COUNT} fichiers en erreur${NC}"
fi

echo
echo "🔍 Vérification des changements..."
echo

# Afficher un résumé des occurrences de la nouvelle version
OCCURRENCES=$(grep -r "${NEW_VERSION}" "${PROJECT_ROOT}" \
    --exclude-dir=.git \
    --exclude-dir=.DS_Store \
    --include="*.yaml" \
    --include="*.html" \
    --include="*.md" \
    --include="*.sh" \
    2>/dev/null | wc -l | tr -d ' ')

echo -e "  ${BLUE}📊 ${OCCURRENCES} occurrences de ${NEW_VERSION} trouvées${NC}"
echo

# Afficher les fichiers modifiés
echo "📝 Fichiers modifiés:"
echo
grep -rl "${NEW_VERSION}" "${PROJECT_ROOT}" \
    --exclude-dir=.git \
    --include="*.yaml" \
    --include="*.html" \
    --include="*.md" \
    --include="*.sh" \
    2>/dev/null | sed "s|${PROJECT_ROOT}/||g" | while read -r file; do
    echo -e "  ${GREEN}•${NC} ${file}"
done

echo
echo "=========================================="
echo "  📋 Prochaines étapes"
echo "=========================================="
echo
echo "1. Vérifier que la version ${NEW_VERSION} est disponible:"
echo "   oc get istiorevisions -n istio-system"
echo
echo "2. Si Istio est déjà déployé, appliquer les changements:"
echo "   kubectl apply -f manifests/istio.yaml"
echo "   kubectl apply -f manifests/istio-cni.yaml"
echo "   kubectl apply -f manifests/ztunnel.yaml"
echo
echo "3. Vérifier le rollout:"
echo "   kubectl rollout status deployment/istiod -n istio-system"
echo "   kubectl get pods -n istio-system"
echo "   kubectl get pods -n ztunnel"
echo
echo "4. Tester l'application après la mise à jour"
echo
echo "💡 Pour un déploiement complet depuis zéro:"
echo "   cd scripts && ./deploy-all.sh"
echo
