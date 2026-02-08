# Issues Connus et Solutions

## Warning ZTunnel : "failed to connect to the Istio CNI node agent"

### Symptôme

Dans les logs ZTunnel, vous voyez des warnings répétés :

```
warn inpod::workloadmanager failed to connect to the Istio CNI node agent over
"/var/run/ztunnel/ztunnel.sock", is the node agent healthy?
details: Os { code: 2, kind: NotFound, message: "No such file or directory" }.
retrying in 15s
```

### Cause

Dans OpenShift Service Mesh 3 avec Istio Ambient mode, il existe deux modes de fonctionnement pour la redirection du trafic :

1. **Mode CNI Plugin** (utilisé par défaut sur OpenShift)
   - Istio CNI configure directement les règles iptables
   - Pas besoin du node agent socket
   - **Le warning est bénin et peut être ignoré**

2. **Mode CNI Node Agent** (mode alternatif)
   - Utilise un socket Unix pour communication
   - ZTunnel tente de se connecter au socket `/var/run/ztunnel/ztunnel.sock`
   - Si le socket n'existe pas, le warning apparaît

### Impact

⚠️ **AUCUN IMPACT** sur le fonctionnement :
- ✅ Le trafic fonctionne normalement via Istio CNI
- ✅ mTLS est actif entre tous les services
- ✅ VirtualServices et DestinationRules fonctionnent
- ✅ Waypoint Proxy route correctement le trafic L7

Le warning apparaît simplement parce que ZTunnel tente de se connecter au node agent socket qui n'est pas utilisé dans cette configuration.

### Vérification

Pour confirmer que tout fonctionne malgré le warning :

```bash
# Test de connectivité entre services
kubectl exec -n bookinfo deployment/productpage-v1 -- \
  python -c "import urllib.request; \
  print('Reviews v1:', urllib.request.urlopen('http://reviews:9080/reviews/0').getcode())"

# Vérifier les pods
kubectl get pods -n bookinfo
kubectl get pods -n ztunnel

# Vérifier les VirtualServices
kubectl get virtualservice -n bookinfo

# Vérifier le Waypoint
kubectl get gateway waypoint -n bookinfo
```

### Solution (si vous voulez supprimer le warning)

Si le warning vous dérange, vous pouvez ajuster le niveau de log de ZTunnel :

```bash
# Éditer le manifest ztunnel
kubectl edit ztunnel default -n ztunnel

# Ajouter dans spec.values:
spec:
  values:
    ztunnel:
      env:
        RUST_LOG: "warn,inpod::workloadmanager=error"
```

Ou ignorer simplement le warning, car il est **sans conséquence**.

### Références

- [Istio Ambient Mesh Architecture](https://istio.io/latest/docs/ambient/architecture/)
- [OpenShift Service Mesh 3 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.1/)

## Gateway Service Type : LoadBalancer vs ClusterIP

### Symptôme

Par défaut, Istio crée un service de type **LoadBalancer** pour le Gateway, ce qui n'est pas optimal sur OpenShift.

```bash
kubectl get svc -n istio-system
NAME                     TYPE           ...
bookinfo-gateway-istio   LoadBalancer   # ❌ Reste en "pending" sur OpenShift
```

### Solution

Utiliser l'annotation pour forcer le type **ClusterIP** :

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: bookinfo-gateway
  namespace: istio-system
  annotations:
    networking.istio.io/service-type: ClusterIP  # ✅ Recommandé pour OpenShift
spec:
  ...
```

Ou appliquer l'annotation après coup :

```bash
kubectl annotate gateway bookinfo-gateway \
  networking.istio.io/service-type=ClusterIP \
  --namespace=istio-system --overwrite
```

### Pourquoi ClusterIP ?

Sur OpenShift, on expose les services via **Routes** qui pointent vers des services ClusterIP :

```
Internet → OpenShift Route → ClusterIP Service → Gateway Pod
```

Pas besoin de LoadBalancer externe.

## API Version : v1beta1 vs v1

### Symptôme

VirtualServices ou DestinationRules créés avec l'ancienne API version peuvent ne pas fonctionner correctement.

### Solution

Utiliser **v1** au lieu de v1beta1 :

```yaml
# ✅ Correct
apiVersion: networking.istio.io/v1
kind: VirtualService

# ❌ Obsolète
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
```

Tous les manifests dans ce projet utilisent déjà **v1**.

## Productpage n'a pas de VirtualService

### Question

Pourquoi `productpage` n'a pas de VirtualService alors que les autres services en ont ?

### Réponse

C'est **normal et voulu**. Voici pourquoi :

**Trafic EXTERNE** (Internet → productpage) :
```
Internet → Route → Gateway → HTTPRoute → Service productpage
```
Le HTTPRoute route directement vers le service, **pas besoin de VirtualService**.

**Trafic INTERNE** (service → service) :
```
productpage → Waypoint → VirtualService reviews → reviews v3
productpage → Waypoint → VirtualService details → details v1
reviews → Waypoint → VirtualService ratings → ratings v1
```

**Conclusion** :
- `productpage` est le **point d'entrée** de l'application
- Aucun autre service ne l'appelle depuis l'intérieur du mesh
- Les VirtualServices ne servent que pour le routage **service-to-service**
- HTTPRoute gère le routage **externe → service**

### Services avec VirtualServices

| Service | VirtualService | Raison |
|---------|---------------|--------|
| **productpage** | ❌ Non | Point d'entrée, personne ne l'appelle |
| **reviews** | ✅ Oui | Appelé par productpage (routage v1/v2/v3) |
| **details** | ✅ Oui | Appelé par productpage |
| **ratings** | ✅ Oui | Appelé par reviews |

## AuthorizationPolicy en mode ambient

### Symptôme

Vous créez une AuthorizationPolicy avec `selector` mais elle ne bloque pas le trafic :

```yaml
spec:
  selector:
    matchLabels:
      app: reviews
  action: DENY
  rules:
  - {}
```

Le trafic vers reviews passe toujours.

### Cause

En **mode ambient avec waypoint**, les AuthorizationPolicy doivent utiliser **`targetRefs`** au lieu de `selector` pour cibler les services.

Le `selector` fonctionne uniquement en mode sidecar traditionnel.

### Solution

Utilisez `targetRefs` pour cibler le service :

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: deny-reviews
  namespace: bookinfo
spec:
  targetRefs:
  - kind: Service
    group: ""
    name: reviews
  action: DENY
  rules:
  - {}  # Bloque tout le trafic
```

### Résultat

Avec `targetRefs`, le trafic est correctement bloqué :
- HTTP 403 Forbidden
- La page productpage affiche : "Error fetching product reviews"

### Référence

- [Istio Authorization Policy](https://istio.io/latest/docs/reference/config/security/authorization-policy/)
- Utiliser `targetRefs` est la méthode recommandée en mode ambient
