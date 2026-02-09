# Distributed Tracing avec Grafana Tempo

Intégration complète du distributed tracing dans la démo Bookinfo avec Grafana Tempo.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Application Bookinfo (namespace: bookinfo)              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐         │
│  │productpage │  │  reviews   │  │  details   │         │
│  │    (v1)    │  │ (v1,v2,v3) │  │    (v1)    │         │
│  └────────────┘  └────────────┘  └────────────┘         │
│         │               │               │                │
│         └───────────────┴───────────────┘                │
│                         │                                │
│  ┌──────────────────────▼─────────────────────────────┐  │
│  │  Waypoint Proxy (L7)                              │  │
│  │  - Génère spans HTTP (headers, status, latence)   │  │
│  └────────────────────┬───────────────────────────────┘  │
│                       │                                  │
│  ┌────────────────────▼───────────────────────────────┐  │
│  │  ZTunnel (L4 - DaemonSet)                         │  │
│  │  - Génère spans TCP/mTLS                          │  │
│  └────────────────────┬───────────────────────────────┘  │
└────────────────────────┼──────────────────────────────────┘
                         │ OTLP traces (port 4317)
                         ↓
┌──────────────────────────────────────────────────────────┐
│  OpenTelemetry Collector (istio-system)                  │
│  - Reçoit traces via OTLP (gRPC + HTTP)                 │
│  - Batch processing et agrégation                       │
│  - Enrichissement (tags, attributs)                     │
└────────────────────────┬─────────────────────────────────┘
                         │
                         ↓
┌──────────────────────────────────────────────────────────┐
│  Grafana Tempo (istio-system)                            │
│  - Stockage des traces (local/S3)                       │
│  - API de requête TraceQL                               │
│  - Génération de métriques (span metrics, service graph)│
│  - Corrélation avec Prometheus                          │
└────────────────────────┬─────────────────────────────────┘
                         │
                         ↓
┌──────────────────────────────────────────────────────────┐
│  Grafana (istio-system)                                  │
│  - Interface de visualisation                            │
│  - Datasources: Tempo + Prometheus                      │
│  - Service Graph                                         │
│  - Trace Explorer                                        │
│  - Exemplars (traces → métriques)                       │
└──────────────────────────────────────────────────────────┘
```

## Composants déployés

### 1. Grafana Tempo (avec Jaeger UI intégrée)
**Rôle** : Backend de stockage et requête des traces

**Fonctionnalités** :
- Stockage des traces distribuées
- Support TraceQL pour requêtes avancées
- Génération de métriques à partir des traces
- Corrélation avec Prometheus (exemplars)

**Endpoints** (créés automatiquement par l'opérateur):
- `tempo-tempo.istio-system.svc.cluster.local:3200` (HTTP API / Query)
- `tempo-tempo.istio-system.svc.cluster.local:4317` (OTLP gRPC Receiver)
- `tempo-tempo.istio-system.svc.cluster.local:4318` (OTLP HTTP Receiver)

**Note**: L'opérateur TempoMonolithic crée automatiquement un service nommé `tempo-tempo` (format: `<CR-name>-<CR-name>`).

### 2. OpenTelemetry Collector
**Rôle** : Agrégateur et routeur de traces

**Fonctionnalités** :
- Réception OTLP (gRPC port 4317, HTTP port 4318)
- Batch processing pour optimisation
- Enrichissement avec attributs custom (cluster, mesh)
- Export vers Tempo

**Endpoints** :
- `otel-collector.istio-system.svc.cluster.local:4317` (OTLP gRPC)
- `otel-collector.istio-system.svc.cluster.local:4318` (OTLP HTTP)

### 3. Jaeger UI (intégrée dans Tempo)
**Rôle** : Interface web pour visualiser les traces

**Fonctionnalités** :
- Interface Jaeger familière et éprouvée
- Recherche de traces par service, opération, tags
- Visualisation des spans et dépendances
- Graphe de dépendances des services
- Analyse de latence
- Comparaison de traces

**Avantages vs Grafana** :
- ✅ Pas de configuration de datasource nécessaire
- ✅ Interface dédiée au tracing (plus simple)
- ✅ Activée automatiquement par l'opérateur Tempo
- ✅ Accès direct sans authentification (route personnalisée)

**Note sur l'authentification** :
L'opérateur Tempo crée une route avec OAuth par défaut (`tempo-tempo-jaegerui`), ce qui peut causer des erreurs d'authentification. Cette démo inclut une **route personnalisée sans OAuth** (`jaeger-query`) pour un accès direct et simplifié.

## Déploiement

**⚠️ Important - Version Istio**: Les manifests de tracing sont configurés pour Istio **v1.27.3**. Si votre cluster utilise une version différente, mettez à jour `tracing/manifests/istio-tracing-config.yaml` avant le déploiement.

### Prérequis

- **Tempo Operator** installé sur OpenShift (pour la CR TempoMonolithic)
- Bookinfo déjà déployé avec Istio en mode ambient
- Prometheus déjà déployé (pour les métriques)
- Kiali optionnel (pour comparaison)

#### Installation du Tempo Operator

Via la console OpenShift:
1. **Operators** → **OperatorHub**
2. Rechercher **"Tempo Operator"**
3. Cliquer sur **Install**
4. Namespace: **openshift-operators** (par défaut)
5. Attendre que le status soit **Succeeded**

Ou via CLI:
```bash
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: tempo-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: tempo-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### Vérification des prérequis

Avant de déployer, vérifiez que tous les prérequis sont en place:

```bash
cd tracing/scripts
./check-prerequisites.sh
```

Le script vérifie:
- ✅ Présence de `oc` ou `kubectl`
- ✅ Connexion au cluster
- ✅ Tempo Operator installé et opérationnel
- ✅ Istio déployé (istiod)
- ✅ Prometheus (optionnel)
- ✅ Bookinfo (optionnel pour tester)
- ✅ Absence de déploiements conflictuels

### Installation complète

```bash
cd tracing/scripts
./deploy-tracing.sh
```

Ce script déploie dans l'ordre :
1. Tempo (backend de stockage)
2. OpenTelemetry Collector (agrégateur)
3. Grafana (visualisation)
4. Configuration Istio pour le tracing
5. Telemetry API pour activer le tracing

**Durée** : ~3 minutes

### Installation manuelle pas à pas

#### 1. Déployer Tempo

```bash
oc apply -f tracing/manifests/tempo.yaml
```

Vérifier le déploiement :
```bash
oc get pods -n istio-system -l app=tempo
oc logs -n istio-system -l app=tempo --tail=20
```

#### 2. Déployer OpenTelemetry Collector

```bash
oc apply -f tracing/manifests/otel-collector.yaml
```

Vérifier :
```bash
oc get pods -n istio-system -l app=otel-collector
oc logs -n istio-system -l app=otel-collector --tail=20
```

#### 3. Déployer Grafana

```bash
oc apply -f tracing/manifests/grafana.yaml
```

Vérifier et récupérer l'URL :
```bash
oc get route grafana -n istio-system
echo "https://$(oc get route grafana -n istio-system -o jsonpath='{.spec.host}')"
```

#### 4. Configurer Istio pour le tracing

```bash
oc apply -f tracing/manifests/istio-tracing-config.yaml
```

Attendre le redémarrage d'istiod :
```bash
oc rollout status deployment istiod -n istio-system
```

#### 5. Activer le tracing via Telemetry API

```bash
oc apply -f tracing/manifests/telemetry.yaml
```

Vérifier :
```bash
oc get telemetry -A
```

## Vérification

### 1. Vérifier que tous les pods sont Running

```bash
oc get pods -n istio-system | grep -E '(tempo|otel|grafana)'
```

Vous devriez voir :
- `tempo-0` → Running (StatefulSet géré par l'opérateur)
- `otel-collector-xxx` → Running
- `grafana-xxx` → Running

Vérifier l'instance TempoMonolithic:
```bash
oc get tempomonolithic tempo -n istio-system
oc describe tempomonolithic tempo -n istio-system
```

Vérifier les services créés par l'opérateur:
```bash
oc get svc -n istio-system -l app.kubernetes.io/instance=tempo
```

Le service principal devrait être `tempo-tempo` avec les ports:
- 3200 (http)
- 4317 (otlp-grpc)
- 4318 (otlp-http)

### 2. Générer du trafic

```bash
cd ../scripts
./generate-traffic.sh
```

Ou manuellement :
```bash
for i in {1..50}; do
  curl -s "https://$(oc get route bookinfo -n istio-system -o jsonpath='{.spec.host}')/productpage" > /dev/null
  echo "Request $i sent"
  sleep 1
done
```

### 3. Vérifier les traces dans Tempo

```bash
# Via API directe
oc port-forward -n istio-system svc/tempo-tempo 3200:3200 &

# Lister les services avec traces
curl -s http://localhost:3200/api/search/tags | jq

# Chercher des traces
curl -s "http://localhost:3200/api/search?tags=service.name%3Dproductpage" | jq
```

### 4. Ouvrir Jaeger UI

```bash
echo "https://$(oc get route jaeger-query -n istio-system -o jsonpath='{.spec.host}')"
```

Dans Jaeger UI (pas d'authentification requise):
1. **Search** → Service: `productpage.bookinfo`
2. Opération: Toutes (ou sélectionner une opération spécifique)
3. Cliquer **Find Traces**
4. Cliquer sur une trace pour voir les détails et le graphique des spans

Vous devriez voir les traces des requêtes vers l'application Bookinfo.

## Fonctionnalités de visualisation

### 1. Trace Explorer (Grafana)

**Navigation** : Explore → Tempo

**Fonctionnalités** :
- Recherche par service name, span name, tags
- Filtrage par durée, status code
- Visualisation de la trace complète (waterfall)
- Inspection des spans individuels
- Attributs et tags détaillés

**Exemple de requête TraceQL** :
```
{ span.service.name = "productpage.bookinfo" && span.http.status_code = 200 }
```

### 2. Service Graph

**Navigation** : Explore → Tempo → Service Graph

Visualise :
- Flux de requêtes entre services
- Latence moyenne par service
- Taux d'erreurs
- Volume de trafic

### 3. Exemplars (Métriques → Traces)

Dans Prometheus/Grafana :
- Les métriques Istio contiennent des exemplars
- Clic sur un point de métrique → trace correspondante dans Tempo
- Corrélation automatique métrique ↔ trace

### 4. Analyse des spans

Pour chaque span, vous verrez :
- **Service** : productpage, reviews, details, ratings
- **Operation** : HTTP GET /productpage, HTTP GET /reviews
- **Duration** : Latence du span
- **Tags** :
  - `http.method`, `http.url`, `http.status_code`
  - `peer.service`, `span.kind`
  - `istio.mesh_id`, `istio.namespace`
  - `component` (waypoint, ztunnel)

## Mode Ambient et Tracing

### Comportement spécifique au mode ambient

En mode ambient, le tracing est généré par :

#### ZTunnel (Layer 4)
- **Spans générés** : Connexions TCP, mTLS handshake
- **Tags** : source/destination workload, mTLS status
- **Propagation** : Headers de contexte (W3C Trace Context)

#### Waypoint Proxy (Layer 7)
- **Spans générés** : Requêtes HTTP, routing L7
- **Tags** : HTTP method, URL, status code, virtual service
- **Opérations** : Retries, circuit breaker, fault injection

### Exemple de trace Bookinfo

Une requête `GET /productpage` génère cette chaîne de spans :

```
productpage.bookinfo [150ms]
├─ waypoint → productpage [5ms]
│  └─ ztunnel mTLS [2ms]
├─ productpage → reviews [80ms]
│  ├─ waypoint → reviews-v2 [3ms]
│  │  └─ ztunnel mTLS [2ms]
│  └─ reviews-v2 → ratings [30ms]
│     ├─ waypoint → ratings [2ms]
│     │  └─ ztunnel mTLS [1ms]
│     └─ ratings processing [20ms]
└─ productpage → details [40ms]
   ├─ waypoint → details [2ms]
   │  └─ ztunnel mTLS [1ms]
   └─ details processing [30ms]
```

### Avantages du mode ambient pour le tracing

✅ **Pas de sidecar** → Moins de spans redondants
✅ **Injection automatique** → Tracing activé sans modification du code
✅ **Visibilité L4 + L7** → Vue complète (TCP + HTTP)
✅ **Attributs enrichis** → Métadonnées Istio automatiques

## Sampling

### Configuration actuelle

**100% sampling** pour la démo (voir `telemetry.yaml`) :
```yaml
spec:
  tracing:
  - randomSamplingPercentage: 100.0
```

### Recommandations production

Pour réduire le volume de traces :

**Option 1** : Sampling aléatoire (par exemple 10%)
```yaml
randomSamplingPercentage: 10.0
```

**Option 2** : Sampling par namespace
```yaml
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: selective-tracing
  namespace: bookinfo
spec:
  tracing:
  - providers:
    - name: otel-collector
    randomSamplingPercentage: 50.0  # 50% pour bookinfo
```

**Option 3** : Désactiver le tracing pour certains services
```yaml
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: disable-tracing
  namespace: bookinfo
spec:
  selector:
    matchLabels:
      app: ratings
  tracing:
  - disableSpanReporting: true
```

## Scénarios de démonstration

### 1. Visualiser le routage de trafic

Appliquer un scénario de routage :
```bash
cd ../scripts
./apply-routing-scenario.sh
# Choisir : reviews-v3-only
```

Générer du trafic :
```bash
./generate-traffic.sh
```

Dans Grafana → Tempo :
- Les traces montrent uniquement les appels vers `reviews-v3`
- Aucun appel vers `reviews-v1` ou `reviews-v2`

### 2. Canary deployment

```bash
./apply-routing-scenario.sh
# Choisir : canary-v3 (90% v1, 10% v3)
```

Dans Tempo :
- ~90% des traces passent par `reviews-v1`
- ~10% des traces passent par `reviews-v3`

### 3. Analyser les erreurs

Appliquer la politique de déni :
```bash
oc apply -f ../bookinfo/routing-scenarios/authz-deny-reviews.yaml
```

Générer du trafic :
```bash
./generate-traffic.sh
```

Dans Tempo :
- Chercher traces avec `span.http.status_code = 403`
- Les spans vers `reviews` montrent RBAC: access denied
- Latence très faible (erreur immédiate)

### 4. Mesurer la latence ajoutée par le mesh

Comparer :
- Latence totale de la requête (span racine)
- Temps passé dans Waypoint (spans waypoint)
- Temps passé dans ZTunnel (spans ztunnel)
- Temps de traitement applicatif

Overhead typique en mode ambient : **< 5ms**

## Troubleshooting

### Erreur OAuth lors de l'accès à Jaeger UI

**Symptôme**: Message d'erreur `server_error` ou `authorization server encountered an unexpected condition` lors de l'accès à l'URL Jaeger UI.

**Cause**: La route par défaut créée par l'opérateur Tempo (`tempo-tempo-jaegerui`) utilise l'authentification OAuth OpenShift.

**Solution 1 - Utiliser la route sans OAuth (recommandé)**:
```bash
# Vérifier que la route sans OAuth existe
oc get route jaeger-query -n istio-system

# Si elle n'existe pas, la créer
oc apply -f tracing/manifests/jaeger-route.yaml

# Obtenir l'URL
oc get route jaeger-query -n istio-system
```

**Solution 2 - Redéployer avec la route sans OAuth**:
```bash
cd tracing/scripts
./deploy-tracing.sh
```

Le script crée automatiquement une route `jaeger-query` sans OAuth.

**Solution 3 - Script de correction**:
```bash
cd tracing/scripts
./fix-jaeger-oauth.sh
```

**URLs à utiliser**:
- ✅ **Route sans OAuth**: `jaeger-query` (recommandée pour la démo)
- ❌ **Route avec OAuth**: `tempo-tempo-jaegerui` (créée par l'opérateur, peut causer des erreurs)

### Les traces n'apparaissent pas dans Tempo

**1. Vérifier que le trafic passe par le waypoint**

```bash
oc get gateway waypoint -n bookinfo
oc get pods -n bookinfo -l gateway.networking.k8s.io/gateway-name=waypoint
```

Sans waypoint, seules les traces L4 (ztunnel) sont générées.

**2. Vérifier les logs OpenTelemetry Collector**

```bash
oc logs -n istio-system -l app=otel-collector --tail=50
```

Chercher les erreurs d'export vers Tempo.

**3. Vérifier les logs Tempo**

```bash
oc logs -n istio-system -l app=tempo --tail=50
```

**4. Tester la connectivité OTLP**

```bash
oc run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://otel-collector.istio-system.svc.cluster.local:4318/v1/traces
```

### Grafana ne trouve pas le datasource Tempo

**1. Vérifier que le service Tempo existe**:
```bash
oc get svc tempo-tempo -n istio-system
```

Le service devrait exposer les ports 3200, 4317, 4318.

**2. Tester la connectivité depuis Grafana vers Tempo**:
```bash
# Obtenir le nom du pod Grafana
GRAFANA_POD=$(oc get pods -n istio-system -l app=grafana -o jsonpath='{.items[0].metadata.name}')

# Tester la connexion
oc exec -n istio-system $GRAFANA_POD -- curl -s http://tempo-tempo.istio-system.svc.cluster.local:3200/status
```

Si la connexion fonctionne, vous devriez voir une réponse JSON.

**3. Vérifier la configuration de la datasource** :
```bash
oc get configmap grafana-datasources -n istio-system -o yaml
```

**4. Redémarrer Grafana** :
```bash
oc rollout restart deployment grafana -n istio-system
oc rollout status deployment grafana -n istio-system
```

**5. Dans Grafana UI, vérifier la datasource**:
- Aller dans **Configuration** → **Data Sources**
- Cliquer sur **Tempo**
- Cliquer sur **Save & Test**
- Vous devriez voir "Data source is working"

### Erreur "invalid TraceQL query: parse error"

Si vous voyez cette erreur dans Grafana:

**Cause**: Configuration incompatible de la datasource Tempo

**Solution**:
```bash
# Mettre à jour la configuration
oc apply -f tracing/manifests/grafana.yaml

# Redémarrer Grafana pour recharger la config
oc rollout restart deployment grafana -n istio-system

# Attendre que Grafana redémarre
oc rollout status deployment grafana -n istio-system
```

**Dans Grafana UI**:
1. **Explore** → Sélectionner **Tempo**
2. Dans le champ de recherche, cliquer sur **Search** (au lieu de TraceQL)
3. Utiliser les filtres de recherche (Service Name, Span Name, etc.)
4. Cliquer sur **Run Query**

**Alternative - Requête TraceQL simple**:
Si vous voulez utiliser TraceQL, commencez avec une requête simple:
```
{}
```

Puis ajoutez des filtres progressivement:
```
{ span.service.name = "productpage.bookinfo" }
```

### Les spans ne contiennent pas assez d'informations

**Augmenter max_path_tag_length dans Istio** :

Modifier `istio-tracing-config.yaml` :
```yaml
meshConfig:
  defaultConfig:
    tracing:
      max_path_tag_length: 512  # Augmenter si nécessaire
```

### Performances dégradées

**Réduire le sampling** :
```bash
oc patch telemetry mesh-tracing -n istio-system --type merge -p '
spec:
  tracing:
  - randomSamplingPercentage: 10.0
'
```

**Augmenter les ressources OpenTelemetry Collector** :

Modifier `otel-collector.yaml` :
```yaml
resources:
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

## Nettoyage

### Supprimer uniquement le tracing (garder Istio et Bookinfo)

```bash
cd tracing/scripts
./cleanup-tracing.sh
```

Supprime :
- Tempo et ses données
- OpenTelemetry Collector
- Grafana
- Configuration de tracing Istio
- Telemetry resources

Conserve :
- Istio infrastructure
- Bookinfo application
- Prometheus et Kiali

### Désactiver le tracing sans supprimer l'infrastructure

```bash
oc delete telemetry mesh-tracing -n istio-system
oc delete telemetry bookinfo-tracing -n bookinfo
```

Les composants restent déployés mais ne reçoivent plus de traces.

## Stockage persistant (optionnel)

Par défaut, Tempo utilise `emptyDir` (données perdues au redémarrage).

Pour persister les traces, créer un PVC :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: tempo-storage
  namespace: istio-system
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

Modifier `tempo.yaml` pour utiliser le PVC :
```yaml
volumes:
- name: storage
  persistentVolumeClaim:
    claimName: tempo-storage
```

## Configuration S3 (production)

Pour utiliser S3 comme backend de stockage :

Modifier la ConfigMap `tempo` :
```yaml
storage:
  trace:
    backend: s3
    s3:
      bucket: tempo-traces
      endpoint: s3.amazonaws.com
      access_key: ${AWS_ACCESS_KEY}
      secret_key: ${AWS_SECRET_KEY}
```

## Ressources

- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Istio Distributed Tracing](https://istio.io/latest/docs/tasks/observability/distributed-tracing/)
- [TraceQL Query Language](https://grafana.com/docs/tempo/latest/traceql/)

## Comparaison avec Jaeger

| Fonctionnalité | Tempo | Jaeger |
|----------------|-------|--------|
| **Backend** | Storage-first | Index-first |
| **Coût stockage** | ✅ Très bas (S3) | ❌ Élevé (Cassandra/ES) |
| **Requêtes** | TraceQL | UI limitée |
| **Métriques** | ✅ Span metrics | ❌ Non |
| **Intégration** | Grafana natif | UI séparée |
| **Scalabilité** | ✅✅✅ Excellent | ✅✅ Bon |

**Recommandation** : Tempo est mieux adapté pour OpenShift avec Istio ambient.
