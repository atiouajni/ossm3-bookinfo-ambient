# Bookinfo sur OpenShift Service Mesh 3 (Ambient Mode)

Déploiement de l'application Bookinfo sur OpenShift avec Istio en mode ambient.

## Architecture

- **Mode**: Ambient (sans sidecars, utilise ZTunnel pour L4)
- **Cluster**: Single cluster OpenShift (SNO ou multi-node)
- **Mesh ID**: mesh1
- **Application**: Bookinfo (tous les microservices sur le même cluster)

## Qu'est-ce que le mode Ambient?

Le **mode ambient** d'Istio est une nouvelle architecture qui simplifie le service mesh:

- ✅ **Pas de sidecars** - Pas d'injection de proxy dans les pods applicatifs
- ✅ **ZTunnel** - DaemonSet qui gère le trafic L4 (mTLS, connectivité)
- ✅ **Waypoint** (optionnel) - Pour les fonctionnalités L7 (routing avancé, retries)
- ✅ **Moins de ressources** - Réduction de la consommation CPU/mémoire
- ✅ **Déploiement simplifié** - Pas de redémarrage des pods applicatifs

### Architecture déployée

```
┌─────────────────────────────────────────────────┐
│           OpenShift Cluster                     │
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

## Prérequis

- OpenShift 4.x (SNO ou cluster complet)
- OpenShift Service Mesh Operator 3.x installé
- oc CLI
- Accès cluster-admin

### Installation Service Mesh Operator

Via la console OpenShift :
1. **Operators** → **OperatorHub**
2. Rechercher **"OpenShift Service Mesh"**
3. Cliquer sur **Install**
4. Sélectionner la version **3.x**
5. Attendre que le status soit **Succeeded**

## Quick Start

### 1. Vérifier les prérequis

```bash
cd single-cluster/scripts
./check-prerequisites.sh
```

Le script vérifie:
- ✅ CLI tools (oc/kubectl)
- ✅ Connexion au cluster
- ✅ Service Mesh Operator 3.x installé
- ✅ Permissions cluster-admin
- ✅ Pas de déploiements conflictuels

### 2. Déployer Bookinfo

```bash
./deploy-all.sh
```

Le script va :
1. ✅ Créer les namespaces (istio-system, istio-cni, ztunnel, bookinfo)
2. ✅ Vérifier/Installer Gateway API CRDs
3. ✅ Déployer Istio CNI
4. ✅ Déployer Istio Control Plane (mode ambient)
5. ✅ Déployer ZTunnel
6. ✅ Déployer l'application Bookinfo (tous les services)
7. ✅ Créer la Route OpenShift pour accès externe

**Durée** : ~5 minutes

### 3. Accéder à l'application

L'URL sera affichée à la fin du déploiement:

```
https://bookinfo-istio-system.apps.your-cluster.com/productpage
```

Ou récupérer manuellement:

```bash
oc get route bookinfo -n istio-system -o jsonpath='{.spec.host}'
```

## Services Bookinfo

L'application complète est déployée:

| Service | Version(s) | Description |
|---------|-----------|-------------|
| **productpage** | v1 | Page principale de l'application |
| **details** | v1 | Détails du livre |
| **reviews** | v1, v2, v3 | Avis des lecteurs (v2 et v3 avec étoiles) |
| **ratings** | v1 | Système de notation |

## Fonctionnalités testables

### 1. Load balancing entre versions

Rechargez plusieurs fois la page `/productpage`:
- Parfois sans étoiles (reviews v1)
- Parfois avec étoiles noires (reviews v2)
- Parfois avec étoiles rouges (reviews v3)

### 2. mTLS automatique

En mode ambient, toutes les communications sont automatiquement chiffrées en mTLS sans configuration.

### 3. Observabilité

Générer du trafic:

```bash
for i in {1..100}; do
  curl -s https://$(oc get route bookinfo -n istio-system -o jsonpath='{.spec.host}')/productpage > /dev/null
  echo "Request $i"
done
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

## Nettoyage

Pour supprimer complètement Bookinfo et Istio:

```bash
cd single-cluster/scripts
./cleanup.sh
```

## Troubleshooting

### Les pods ne démarrent pas

**Problème**: Erreur de permissions OpenShift SCC

```bash
# Accorder les permissions manuellement
oc adm policy add-scc-to-user anyuid -z bookinfo-productpage -n bookinfo
oc adm policy add-scc-to-user anyuid -z bookinfo-details -n bookinfo
oc adm policy add-scc-to-user anyuid -z bookinfo-reviews -n bookinfo
oc adm policy add-scc-to-user anyuid -z bookinfo-ratings -n bookinfo
```

### La Route ne fonctionne pas

**Vérifier**:

```bash
# Status de la Route
oc get route bookinfo -n istio-system

# Status du service Gateway
oc get svc -n istio-system | grep bookinfo-gateway

# Logs du Gateway
oc logs -n istio-system -l gateway.networking.k8s.io/gateway-name=bookinfo-gateway
```

### istiod ne démarre pas

**Vérifier les logs**:

```bash
oc logs -n istio-system -l app=istiod --tail=50
```

## Structure du projet

```
ossm3-bookinfo-ambient/
├── single-cluster/           # Déploiement single-cluster (cette démo)
│   ├── manifests/
│   │   ├── istio-cni.yaml
│   │   ├── istio.yaml
│   │   ├── ztunnel.yaml
│   │   └── gatewayclass.yaml
│   ├── bookinfo/
│   │   ├── namespace.yaml
│   │   ├── serviceaccounts.yaml
│   │   ├── bookinfo.yaml
│   │   └── gateway.yaml
│   ├── scripts/
│   │   ├── check-prerequisites.sh
│   │   ├── deploy-all.sh
│   │   └── cleanup.sh
│   └── README.md
├── archive/
│   └── multi-cluster-attempt/  # Ancienne tentative multi-cluster
└── README.md                 # Ce fichier
```

## Documentation détaillée

Pour plus de détails sur le déploiement, consultez:
- [Documentation complète](single-cluster/README.md)

## Références

- [OpenShift Service Mesh 3 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.1/)
- [Istio Ambient Mesh](https://istio.io/latest/docs/ambient/)
- [Bookinfo Application](https://istio.io/latest/docs/examples/bookinfo/)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
