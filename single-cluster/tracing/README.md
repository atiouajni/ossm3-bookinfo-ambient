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

### 1. Grafana Tempo
**Rôle** : Backend de stockage et requête des traces

**Fonctionnalités** :
- Stockage des traces distribuées
- Support TraceQL pour requêtes avancées
- Génération de métriques à partir des traces
- Corrélation avec Prometheus (exemplars)

**Endpoints** :
- `tempo.istio-system.svc.cluster.local:3200` (HTTP API)
- `tempo.istio-system.svc.cluster.local:4317` (OTLP gRPC)
- `tempo.istio-system.svc.cluster.local:4318` (OTLP HTTP)

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

### 3. Grafana
**Rôle** : Interface de visualisation

**Datasources configurées** :
- **Tempo** : Visualisation des traces
- **Prometheus** : Métriques et exemplars

**Fonctionnalités** :
- Trace Explorer
- Service Graph (visualisation des dépendances)
- Exemplars (lien métriques → traces)
- TraceQL queries

## Déploiement

**⚠️ Important - Version Istio**: Les manifests de tracing sont configurés pour Istio **v1.27.3**. Si votre cluster utilise une version différente, mettez à jour `tracing/manifests/istio-tracing-config.yaml` avant le déploiement.

### Prérequis

- Bookinfo déjà déployé avec Istio en mode ambient
- Prometheus déjà déployé (pour les métriques)
- Kiali optionnel (pour comparaison)

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
kubectl apply -f tracing/manifests/tempo.yaml
```

Vérifier le déploiement :
```bash
kubectl get pods -n istio-system -l app=tempo
kubectl logs -n istio-system -l app=tempo --tail=20
```

#### 2. Déployer OpenTelemetry Collector

```bash
kubectl apply -f tracing/manifests/otel-collector.yaml
```

Vérifier :
```bash
kubectl get pods -n istio-system -l app=otel-collector
kubectl logs -n istio-system -l app=otel-collector --tail=20
```

#### 3. Déployer Grafana

```bash
kubectl apply -f tracing/manifests/grafana.yaml
```

Vérifier et récupérer l'URL :
```bash
kubectl get route grafana -n istio-system
echo "https://$(kubectl get route grafana -n istio-system -o jsonpath='{.spec.host}')"
```

#### 4. Configurer Istio pour le tracing

```bash
kubectl apply -f tracing/manifests/istio-tracing-config.yaml
```

Attendre le redémarrage d'istiod :
```bash
kubectl rollout status deployment istiod -n istio-system
```

#### 5. Activer le tracing via Telemetry API

```bash
kubectl apply -f tracing/manifests/telemetry.yaml
```

Vérifier :
```bash
kubectl get telemetry -A
```

## Vérification

### 1. Vérifier que tous les pods sont Running

```bash
kubectl get pods -n istio-system | grep -E '(tempo|otel|grafana)'
```

Vous devriez voir :
- `tempo-xxx` → Running
- `otel-collector-xxx` → Running
- `grafana-xxx` → Running

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
kubectl port-forward -n istio-system svc/tempo 3200:3200 &

# Lister les services avec traces
curl -s http://localhost:3200/api/search/tags | jq

# Chercher des traces
curl -s "http://localhost:3200/api/search?tags=service.name%3Dproductpage" | jq
```

### 4. Ouvrir Grafana

```bash
echo "https://$(kubectl get route grafana -n istio-system -o jsonpath='{.spec.host}')"
```

Dans Grafana :
1. **Explore** → Sélectionner **Tempo** datasource
2. **Query type** → Search
3. **Service Name** → `productpage.bookinfo`
4. Cliquer **Run Query**

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
kubectl apply -f ../bookinfo/routing-scenarios/authz-deny-reviews.yaml
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

### Les traces n'apparaissent pas dans Tempo

**1. Vérifier que le trafic passe par le waypoint**

```bash
kubectl get gateway waypoint -n bookinfo
kubectl get pods -n bookinfo -l gateway.networking.k8s.io/gateway-name=waypoint
```

Sans waypoint, seules les traces L4 (ztunnel) sont générées.

**2. Vérifier les logs OpenTelemetry Collector**

```bash
kubectl logs -n istio-system -l app=otel-collector --tail=50
```

Chercher les erreurs d'export vers Tempo.

**3. Vérifier les logs Tempo**

```bash
kubectl logs -n istio-system -l app=tempo --tail=50
```

**4. Tester la connectivité OTLP**

```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://otel-collector.istio-system.svc.cluster.local:4318/v1/traces
```

### Grafana ne trouve pas le datasource Tempo

**Vérifier la configuration** :
```bash
kubectl get configmap grafana-datasources -n istio-system -o yaml
```

**Redémarrer Grafana** :
```bash
kubectl rollout restart deployment grafana -n istio-system
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
kubectl patch telemetry mesh-tracing -n istio-system --type merge -p '
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
kubectl delete telemetry mesh-tracing -n istio-system
kubectl delete telemetry bookinfo-tracing -n bookinfo
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
