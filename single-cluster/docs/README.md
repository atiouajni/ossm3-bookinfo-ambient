# Documentation HTML Bookinfo

Documentation interactive complète pour le déploiement de Bookinfo sur OpenShift Service Mesh 3 en mode Ambient.

## 🌐 Visualisation

### Option 1: Serveur local (recommandé)

```bash
cd ../scripts
./serve-docs.sh
```

Puis ouvrir dans votre navigateur: **http://localhost:8080**

Vous pouvez changer le port:
```bash
./serve-docs.sh 3000  # Utilise le port 3000
```

### Option 2: Ouvrir directement

```bash
open index.html
# ou
xdg-open index.html  # Linux
# ou
start index.html     # Windows
```

## 📋 Contenu

La documentation couvre:

1. **Introduction** - Qu'est-ce que le mode Ambient
2. **Architecture** - Composants et services déployés
3. **Prérequis** - Requirements et installation de l'opérateur
4. **Installation** - Guide pas à pas du déploiement
5. **Vérification** - Tests et validation
6. **Preuves Ambient** - 6 preuves concrètes du mode L4
7. **Redirection Trafic** - Comment le CNI redirige vers ZTunnel
8. **Troubleshooting** - Résolution des problèmes courants
9. **Scripts** - Référence de tous les scripts disponibles

## 🎨 Fonctionnalités

- ✨ Design moderne et responsive
- 🎯 Navigation sticky
- 📱 Compatible mobile
- 🎨 Diagrammes ASCII art
- 💻 Blocs de code avec syntaxe
- 🔍 Sections collapsibles
- 🌈 Gradient backgrounds

## 📦 Fichiers

- `index.html` - Documentation complète (fichier unique, pas de dépendances)
- `README.md` - Ce fichier

## 🚀 Déploiement

La documentation est un fichier HTML statique autonome sans dépendances externes. Vous pouvez:

- L'ouvrir localement avec un navigateur
- La servir avec n'importe quel serveur HTTP
- L'héberger sur GitHub Pages, Netlify, etc.
- La partager par email (fichier unique)

## 📝 Licence

Documentation pour OpenShift Service Mesh 3 - Bookinfo Demo
