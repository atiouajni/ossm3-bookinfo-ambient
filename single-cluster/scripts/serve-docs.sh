#!/bin/bash

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCS_DIR="$( cd "$SCRIPT_DIR/../docs" && pwd )"

PORT=${1:-8080}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Serveur de documentation Bookinfo${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ ! -f "$DOCS_DIR/index.html" ]; then
    echo -e "${YELLOW}✗ Fichier index.html non trouvé dans $DOCS_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Documentation trouvée${NC}"
echo ""
echo -e "${YELLOW}Démarrage du serveur HTTP sur le port $PORT...${NC}"
echo ""
echo -e "${GREEN}📖 Documentation disponible à :${NC}"
echo -e "${BLUE}   http://localhost:$PORT${NC}"
echo ""
echo -e "${YELLOW}Appuyez sur Ctrl+C pour arrêter${NC}"
echo ""

cd "$DOCS_DIR"

# Utiliser python pour servir les fichiers
if command -v python3 &> /dev/null; then
    python3 -m http.server $PORT
elif command -v python &> /dev/null; then
    python -m SimpleHTTPServer $PORT
else
    echo -e "${YELLOW}Python non trouvé. Vous pouvez ouvrir directement le fichier :${NC}"
    echo -e "${BLUE}   file://$DOCS_DIR/index.html${NC}"
fi
