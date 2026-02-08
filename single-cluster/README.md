# Bookinfo sur OpenShift Service Mesh 3 (Ambient Mode)

Déploiement simple de l'application Bookinfo sur un seul cluster OpenShift avec Istio en mode ambient.

## Prérequis

- OpenShift 4.x (SNO ou cluster complet)
- OpenShift Service Mesh Operator 3.x installé
- oc CLI

**Note sur Gateway API**: Les CRDs Gateway API peuvent être pré-installés selon votre version d'OpenShift. Le script de déploiement les installera automatiquement uniquement s'ils ne sont pas déjà présents.

## Installation Service Mesh Operator

Via la console OpenShift :
1. **Operators** → **OperatorHub**
2. Rechercher **"OpenShift Service Mesh"**
3. Cliquer sur **Install**
4. Sélectionner la version **3.x**
5. Attendre que le status soit **Succeeded**

## Vérification des prérequis

Avant de déployer, vérifiez que tous les prérequis sont en place:

```bash
cd single-cluster/scripts
./check-prerequisites.sh
```

Le script vérifie:
- ✅ Présence de `oc` ou `kubectl`
- ✅ Connexion au cluster
- ✅ Version d'OpenShift (4.12+ recommandé)
- ✅ Service Mesh Operator 3.x installé et opérationnel
- ✅ Gateway API CRDs (optionnel)
- ✅ Permissions cluster-admin
- ✅ Absence de déploiements conflictuels

## Déploiement

### Méthode automatique - Déploiement complet (recommandé)

Déploie Istio et Bookinfo en une seule commande:

```bash
cd single-cluster/scripts
./deploy-all.sh
```

Le script déploie en 2 phases:
- **Phase 1**: Infrastructure Istio (CNI, Control Plane, ZTunnel)
- **Phase 2**: Application Bookinfo

**Durée** : ~5 minutes

### Méthode manuelle - Déploiement en plusieurs phases

Si vous souhaitez plus de contrôle ou réutiliser Istio pour d'autres applications:

#### Phase 1: Déployer Istio (Infrastructure L4)

```bash
./deploy-istio.sh
```

Ce script va :
1. ✅ Vérifier que Service Mesh Operator est installé
2. ✅ Créer les namespaces (istio-system, istio-cni, ztunnel)
3. ✅ Vérifier/Installer Gateway API CRDs
4. ✅ Déployer Istio CNI
5. ✅ Déployer Istio Control Plane (mode ambient)
6. ✅ Déployer ZTunnel (proxy L4)

**Durée** : ~3 minutes

À ce stade, vous avez :
- ✅ mTLS automatique entre services
- ✅ Métriques de base
- ❌ Pas de routage avancé (VirtualServices ne fonctionneront pas)

#### Phase 2: Déployer Bookinfo (avec Waypoint L7 automatique)

```bash
./deploy-bookinfo.sh
```

Ce script va :
1. ✅ Vérifier qu'Istio est installé
2. ✅ Créer le namespace bookinfo (avec label ambient)
3. ✅ Créer les service accounts
4. ✅ Déployer tous les services Bookinfo
5. ✅ **Déployer Waypoint Proxy (infrastructure Istio L7)**
6. ✅ Déployer VirtualServices et DestinationRules
7. ✅ Créer le Gateway et la Route OpenShift

**Durée** : ~3 minutes

**Note** : Le Waypoint Proxy est automatiquement déployé car Bookinfo utilise des VirtualServices pour le routage avancé.

#### Optionnel : Déployer le Waypoint manuellement

Si vous souhaitez déployer le Waypoint pour un autre namespace ou l'activer/désactiver :

```bash
# Déployer waypoint pour un namespace spécifique
./deploy-waypoint.sh <namespace>

# Exemple pour bookinfo
./deploy-waypoint.sh bookinfo

# Supprimer le waypoint (garde le namespace et les apps)
./cleanup-waypoint.sh <namespace>
```

Le Waypoint peut être :
- **Requis** : Si vous utilisez VirtualServices, DestinationRules, traffic splitting
- **Optionnel** : Si vous n'avez besoin que de mTLS et métriques de base (L4)

### Accès à l'application

Le script affichera l'URL à la fin :

```
https://bookinfo-istio-system.apps.your-cluster.com/productpage
```

Ou récupérer manuellement :

```bash
oc get route bookinfo -n istio-system -o jsonpath='{.spec.host}'
```

## Observabilité (optionnel)

### Kiali

Kiali fournit une visualisation complète de votre service mesh avec une interface dédiée.

### Prérequis

Le **Kiali Operator** doit être installé depuis OperatorHub :

1. Console OpenShift → **Operators** → **OperatorHub**
2. Rechercher **"Kiali"**
3. Installer **Kiali Operator** (canal stable)

Ou via CLI :

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kiali
  namespace: openshift-operators
spec:
  channel: stable
  name: kiali-ossm
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### Déploiement de Kiali

Une fois l'opérateur installé :

```bash
cd single-cluster/scripts
./deploy-kiali.sh
```

Le script déploie :
- ✅ **Prometheus** - Collecte des métriques Istio
- ✅ **Kiali** - Interface de visualisation
- ✅ **Route OpenShift** - Accès externe à Kiali

**Durée** : ~2 minutes

### Accès à Kiali

Le script affichera l'URL à la fin :

```bash
https://kiali-istio-system.apps.your-cluster.com
```

Ou récupérer manuellement :

```bash
oc get route kiali -n istio-system -o jsonpath='{.spec.host}'
```

### Générer du trafic pour la visualisation

Utilisez le script fourni :

```bash
./generate-traffic.sh
```

Ou manuellement :

```bash
for i in {1..100}; do
  curl -s https://$(oc get route bookinfo -n istio-system -o jsonpath='{.spec.host}')/productpage > /dev/null
  echo "Request $i"
done
```

### Fonctionnalités Kiali

Dans l'interface Kiali, vous pouvez :

- **Graph** : Visualiser la topologie des services et le flux de trafic
- **Applications** : Vue par application avec santé et métriques
- **Workloads** : Détails des déploiements et pods
- **Services** : Configuration et métriques des services
- **Istio Config** : Validation de la configuration Istio

## Architecture déployée

```
┌─────────────────────────────────────────────────┐
│           OpenShift SNO Hetzner                 │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Namespace: istio-system                  │  │
│  │  - istiod (Control Plane)                 │  │
│  │  - bookinfo-gateway (Ingress)             │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Namespace: ztunnel                       │  │
│  │  - ztunnel (DaemonSet - Ambient proxy)    │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Namespace: bookinfo (ambient mode)       │  │
│  │                                           │  │
│  │  ┌─────────────┐  ┌─────────────┐        │  │
│  │  │productpage  │  │  details    │        │  │
│  │  │  (v1)       │  │   (v1)      │        │  │
│  │  └─────────────┘  └─────────────┘        │  │
│  │                                           │  │
│  │  ┌─────────────┐  ┌─────────────┐        │  │
│  │  │  reviews    │  │  ratings    │        │  │
│  │  │ (v1,v2,v3)  │  │   (v1)      │        │  │
│  │  └─────────────┘  └─────────────┘        │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  Route OpenShift:                               │
│  bookinfo-istio-system.apps.cluster.com        │
└─────────────────────────────────────────────────┘
```

## Services Bookinfo

L'application complète est déployée :

| Service | Version(s) | Description |
|---------|-----------|-------------|
| **productpage** | v1 | Page principale de l'application |
| **details** | v1 | Détails du livre |
| **reviews** | v1, v2, v3 | Avis des lecteurs (v2 et v3 avec étoiles) |
| **ratings** | v1 | Système de notation |

## Mode Ambient

**Ambient mode** signifie :
- ❌ **Pas de sidecars** injectés dans les pods
- ✅ **ZTunnel** gère le trafic L4 (mTLS, connectivité)
- ✅ **Waypoint Proxy** gère le trafic L7 (routing, retries, VirtualServices)
- ✅ Plus simple, moins de ressources

### Architecture en 2 couches

Le mode Ambient utilise une architecture en deux couches :

#### 1. Couche L4 - ZTunnel (automatique)
- **DaemonSet** sur chaque nœud
- Gère :
  - mTLS automatique entre tous les services
  - Connectivité de base
  - Métriques TCP
- **Aucune configuration requise**

#### 2. Couche L7 - Waypoint Proxy (optionnel)
- **Deployment** à la demande (un pod par namespace)
- Gère les fonctionnalités avancées :
  - VirtualServices (routage avancé)
  - DestinationRules (load balancing, circuit breaker)
  - Traffic splitting (canary, A/B testing)
  - Fault injection, retries, timeouts
- **Requis uniquement** pour les fonctionnalités L7

### Pourquoi le Waypoint Proxy ?

Sans waypoint proxy :
- ✅ mTLS fonctionne (géré par ZTunnel)
- ✅ Métriques de base disponibles
- ❌ **VirtualServices sont ignorés**
- ❌ **DestinationRules ne fonctionnent pas**
- ❌ Pas de routage avancé

Avec waypoint proxy :
- ✅ Toutes les fonctionnalités ci-dessus
- ✅ **VirtualServices actifs**
- ✅ **DestinationRules appliqués**
- ✅ Traffic splitting, canary, A/B testing

Pour en savoir plus :
```bash
./explain-waypoint.sh
```

## Vérification

```bash
# Vérifier les pods Istio
oc get pods -n istio-system
oc get pods -n ztunnel

# Vérifier les pods Bookinfo
oc get pods -n bookinfo

# Vérifier les services
oc get svc -n bookinfo

# Tester l'application
curl https://$(oc get route bookinfo -n istio-system -o jsonpath='{.spec.host}')/productpage
```

## Gestion du Trafic (Traffic Management)

Bookinfo est déployé avec des **VirtualServices** et **DestinationRules** Istio pour contrôler le routage du trafic **interne** (service-to-service).

### VirtualServices et DestinationRules déployés

**Services avec VirtualServices** (trafic mesh interne uniquement) :
- **reviews** : Contrôle la distribution entre v1, v2, v3
- **details** : Route vers details v1
- **ratings** : Route vers ratings v1

**Note** : `productpage` n'a **pas** de VirtualService car c'est le point d'entrée de l'application. Le trafic externe (Internet → productpage) passe par l'**HTTPRoute** du Gateway, pas par un VirtualService.

**Configuration par défaut** - Le trafic vers reviews est distribué équitablement :
- **reviews v1** : 33% (pas d'étoiles)
- **reviews v2** : 33% (étoiles noires)
- **reviews v3** : 34% (étoiles rouges)

### Scénarios de routage disponibles

Utilisez le script interactif pour appliquer différents scénarios :

```bash
cd single-cluster/scripts
./apply-routing-scenario.sh
```

**Scénarios disponibles :**

| Scénario | Description | Cas d'usage |
|----------|-------------|-------------|
| **default** | Round-robin 33/33/34 | Load balancing équilibré |
| **v1-only** | 100% vers v1 (pas d'étoiles) | Rollback vers version stable |
| **v2-only** | 100% vers v2 (étoiles noires) | Test d'une version spécifique |
| **v3-only** | 100% vers v3 (étoiles rouges) | Déploiement complet nouvelle version |
| **canary-v3** | 90% v1, 10% v3 | Canary deployment progressif |
| **deny-reviews** | AuthorizationPolicy DENY | Démonstration sécurité : bloquer reviews |

### Démonstration interactive

Lancez la démo complète qui vous guide à travers tous les scénarios :

```bash
./demo-traffic-routing.sh
```

La démo montre :
1. ✅ Routage vers une version spécifique (100% v1 ou v3)
2. ✅ Canary deployment (déploiement progressif)
3. ✅ Sécurité avec AuthorizationPolicy (bloquer reviews)
4. ✅ Retour au load balancing par défaut

### Exemples de configuration

#### Exemple 1 : Tout le trafic vers v3

```bash
./apply-routing-scenario.sh
# Choisir option 4: v3-only
```

Ou manuellement :

```bash
kubectl apply -f bookinfo/routing-scenarios/reviews-v3-only.yaml
```

#### Exemple 2 : Canary deployment (90/10)

```bash
kubectl apply -f bookinfo/routing-scenarios/reviews-canary-v3.yaml
```

#### Exemple 3 : Bloquer l'accès à reviews avec AuthorizationPolicy

```bash
kubectl apply -f bookinfo/routing-scenarios/authz-deny-reviews.yaml
```

La page productpage se charge mais la section reviews affiche une erreur (HTTP 403 Forbidden).

**Important** : En mode ambient, utilisez `targetRefs` au lieu de `selector` pour cibler les services :

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-reviews
  namespace: bookinfo
spec:
  targetRefs:
  - kind: Service
    name: reviews
  action: DENY
  rules:
  - {}
```

Pour restaurer l'accès :
```bash
kubectl delete authorizationpolicy deny-reviews -n bookinfo
```

### Scénario de démo avec Kiali

#### 1. État initial : Round Robin

Par défaut, sans aucune règle de routage, Istio distribue le trafic en **round robin** entre toutes les versions de reviews (v1, v2, v3).

#### 2. Générer du trafic continu

Dans un terminal, lancez la génération de trafic en continu :

```bash
./generate-traffic.sh
```

Ce script envoie des requêtes régulières vers l'application Bookinfo, permettant de visualiser les flux en temps réel dans Kiali.

#### 3. Ouvrir Kiali

Récupérez l'URL de Kiali :

```bash
echo "https://$(oc get route kiali -n istio-system -o jsonpath='{.spec.host}')"
```

Ouvrez Kiali dans votre navigateur et accédez à **Graph** > sélectionnez le namespace **bookinfo**.

#### 4. Appliquer des scénarios de routage

Vous avez **deux options** pour modifier le routage :

**Option A : Démo interactive guidée**

```bash
./demo-traffic-routing.sh
```

Cette démo vous guide à travers tous les scénarios avec des explications et génération automatique de trafic.

**Option B : Application manuelle de scénarios**

```bash
./apply-routing-scenario.sh
```

Menu interactif permettant de sélectionner et appliquer un scénario spécifique :
- **0** : Afficher l'état actuel (règles actives)
- **1** : 100% vers reviews v1 (sans étoiles)
- **2** : 100% vers reviews v2 (étoiles noires)
- **3** : 100% vers reviews v3 (étoiles rouges)
- **4** : Canary 90/10 (v1/v3)
- **5** : Bloquer reviews (AuthorizationPolicy)
- **6** : Retour au round robin

#### 5. Visualiser dans Kiali

Avec `generate-traffic.sh` toujours actif en parallèle, observez dans Kiali :

- **Graph** : Visualisation en temps réel du flux de trafic
  - Les pourcentages de trafic vers chaque version
  - Le poids configuré dans les VirtualServices
  - Les flèches avec les volumes de requêtes

- **Versioned app graph** : Pour voir distinctement v1, v2, v3

- **Applications** : Métriques détaillées par service
  - Taux de succès/erreur
  - Latence
  - Débit

Exemple : Après avoir appliqué "reviews-v3-only", vous verrez dans le graphe que 100% du trafic va uniquement vers reviews-v3 (étoiles rouges).

## Fonctionnalités testables

### 1. Load balancing entre versions

Rechargez plusieurs fois la page `/productpage` :
- Parfois sans étoiles (reviews v1)
- Parfois avec étoiles noires (reviews v2)
- Parfois avec étoiles rouges (reviews v3)

### 2. Observabilité avec Kiali

Si Kiali est installé, visualisez le trafic en temps réel :

```bash
# Générer du trafic
./generate-traffic.sh

# Ouvrir Kiali
echo "https://$(oc get route kiali -n istio-system -o jsonpath='{.spec.host}')"
```

Dans Kiali, observez :
- Flux de trafic entre les services
- Répartition du load balancing sur les 3 versions de reviews
- Métriques de performance (latence, débit, erreurs)
- mTLS automatique entre tous les services

### 3. mTLS automatique

En mode ambient, toutes les communications sont automatiquement chiffrées en mTLS sans configuration.

## Nettoyage

### Nettoyage complet (Bookinfo + Istio)

Pour supprimer complètement Bookinfo et Istio :

```bash
cd single-cluster/scripts
./cleanup.sh
```

Le script demande confirmation avant de supprimer tous les composants.

### Nettoyage partiel

#### Supprimer uniquement Bookinfo (garder Istio)

Utile si vous voulez déployer une autre application sur Istio :

```bash
./cleanup-bookinfo.sh
```

Supprime :
- Namespace bookinfo
- Gateway et Route Bookinfo
- HTTPRoute

Conserve :
- Istio infrastructure (CNI, Control Plane, ZTunnel)
- Kiali et Prometheus
- Namespaces Istio

#### Supprimer uniquement Kiali et Prometheus (garder Istio)

Utile si vous voulez désactiver l'observabilité :

```bash
./cleanup-kiali.sh
```

Supprime :
- Kiali et sa Route
- Prometheus et ses métriques

Conserve :
- Istio infrastructure
- Application Bookinfo

#### Supprimer uniquement Istio

**Attention** : Supprime toute l'infrastructure Istio :

```bash
./cleanup-istio.sh
```

Le script demande confirmation avant de procéder.

## Troubleshooting

### Les pods ne démarrent pas

**Problème** : Erreur de permissions OpenShift SCC

```bash
# Accorder les permissions manuellement
oc adm policy add-scc-to-user anyuid -z bookinfo-productpage -n bookinfo
oc adm policy add-scc-to-user anyuid -z bookinfo-details -n bookinfo
oc adm policy add-scc-to-user anyuid -z bookinfo-reviews -n bookinfo
oc adm policy add-scc-to-user anyuid -z bookinfo-ratings -n bookinfo
```

### La Route ne fonctionne pas

**Vérifier** :

```bash
# Status de la Route
oc get route bookinfo -n istio-system

# Status du service Gateway
oc get svc -n istio-system | grep bookinfo-gateway

# Logs du Gateway
oc logs -n istio-system -l gateway.networking.k8s.io/gateway-name=bookinfo-gateway
```

### istiod ne démarre pas

**Vérifier les logs** :

```bash
oc logs -n istio-system -l app=istiod --tail=50
```

### Les VirtualServices ne fonctionnent pas (routage ignoré)

**Problème** : Le trafic n'est pas routé selon les VirtualServices (toutes les versions sont toujours utilisées)

**Cause** : Le Waypoint Proxy n'est pas déployé ou les services ne l'utilisent pas

**Solution** :

1. Vérifier le waypoint :
```bash
kubectl get gateway waypoint -n bookinfo
kubectl get pods -n bookinfo -l gateway.networking.k8s.io/gateway-name=waypoint
```

2. Si le waypoint n'existe pas, le déployer :
```bash
kubectl apply -f manifests/waypoint.yaml
```

3. Vérifier que les services utilisent le waypoint :
```bash
kubectl get service reviews -n bookinfo -o jsonpath='{.metadata.labels.istio\.io/use-waypoint}'
```

4. Si le label est absent, l'ajouter :
```bash
kubectl label service reviews -n bookinfo istio.io/use-waypoint=waypoint
```

5. Expliquer le waypoint :
```bash
./explain-waypoint.sh
```

## Structure des fichiers

```
single-cluster/
├── manifests/
│   ├── istio-cni.yaml          # Istio CNI plugin
│   ├── istio.yaml              # Istio Control Plane (ambient)
│   ├── ztunnel.yaml            # ZTunnel (ambient proxy L4)
│   ├── waypoint.yaml           # Waypoint proxy (ambient L7)
│   ├── gatewayclass.yaml       # Gateway API GatewayClass
│   ├── prometheus.yaml         # Prometheus pour métriques
│   └── kiali.yaml              # Kiali pour observabilité
├── bookinfo/
│   ├── namespace.yaml          # Namespace avec label ambient
│   ├── serviceaccounts.yaml    # Service accounts
│   ├── bookinfo.yaml           # Tous les services Bookinfo
│   ├── gateway.yaml            # Gateway + HTTPRoute
│   ├── traffic-management.yaml # VirtualServices + DestinationRules
│   └── routing-scenarios/      # Scénarios de routage prédéfinis
│       ├── reviews-v1-only.yaml
│       ├── reviews-v2-only.yaml
│       ├── reviews-v3-only.yaml
│       ├── reviews-canary-v3.yaml
│       └── authz-deny-reviews.yaml  # AuthorizationPolicy (sécurité)
├── scripts/
│   ├── check-prerequisites.sh  # Vérification des prérequis
│   ├── deploy-all.sh           # Déploiement complet (Istio + Bookinfo + Kiali)
│   ├── deploy-istio.sh         # Déploiement Istio infrastructure L4
│   ├── deploy-waypoint.sh      # Déploiement Waypoint (Istio L7) pour un namespace
│   ├── deploy-bookinfo.sh      # Déploiement Bookinfo (inclut waypoint)
│   ├── deploy-kiali.sh         # Déploiement Kiali et Prometheus
│   ├── cleanup.sh              # Nettoyage complet (tout)
│   ├── cleanup-bookinfo.sh     # Nettoyage Bookinfo uniquement
│   ├── cleanup-waypoint.sh     # Nettoyage Waypoint d'un namespace
│   ├── cleanup-kiali.sh        # Nettoyage Kiali et Prometheus
│   ├── cleanup-istio.sh        # Nettoyage Istio uniquement
│   ├── configure-ingress.sh    # Configuration Route/Gateway
│   ├── generate-traffic.sh     # Génération de trafic pour tests
│   ├── apply-routing-scenario.sh  # Appliquer scénarios de routage
│   ├── demo-traffic-routing.sh    # Démo interactive routage
│   ├── demo-with-kiali.sh      # Démo Bookinfo + Kiali
│   ├── preuves-ambient-l4.sh   # Preuves du mode ambient
│   ├── verify-ambient-mode.sh  # Vérification détaillée ambient
│   ├── explain-traffic-redirection.sh  # Explication redirection
│   ├── explain-waypoint.sh     # Explication waypoint proxy L7
│   └── serve-docs.sh           # Serveur de documentation
├── docs/
│   └── index.html              # Documentation HTML interactive
└── README.md                   # Ce fichier
```

## Documentation HTML

Une documentation interactive complète est disponible en HTML:

```bash
cd single-cluster/scripts
./serve-docs.sh
```

Puis ouvrir dans votre navigateur: **http://localhost:8080**

La documentation contient:
- 📖 Introduction au mode Ambient
- 🏗️ Architecture détaillée
- ⚙️ Guide d'installation pas à pas
- 🔍 Preuves du mode Ambient
- 🔀 Explication de la redirection de trafic
- 🔧 Troubleshooting complet
- 📜 Référence des scripts

Vous pouvez également ouvrir directement le fichier:
```bash
open single-cluster/docs/index.html
```

## Références

- [OpenShift Service Mesh 3 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.1/)
- [Istio Ambient Mesh](https://istio.io/latest/docs/ambient/)
- [Bookinfo Application](https://istio.io/latest/docs/examples/bookinfo/)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
