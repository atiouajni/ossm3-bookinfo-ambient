# Routing Scenarios for Bookinfo Reviews Service

Ce répertoire contient des scénarios de routage prédéfinis pour le service `reviews` de Bookinfo.

## Scénarios disponibles

### 1. reviews-v1-only.yaml
Route 100% du trafic vers **reviews v1** (pas d'étoiles).

**Usage :**
```bash
kubectl apply -f reviews-v1-only.yaml
```

**Cas d'usage :** Rollback vers une version stable.

---

### 2. reviews-v2-only.yaml
Route 100% du trafic vers **reviews v2** (étoiles noires).

**Usage :**
```bash
kubectl apply -f reviews-v2-only.yaml
```

**Cas d'usage :** Test d'une version spécifique.

---

### 3. reviews-v3-only.yaml
Route 100% du trafic vers **reviews v3** (étoiles rouges).

**Usage :**
```bash
kubectl apply -f reviews-v3-only.yaml
```

**Cas d'usage :** Déploiement complet d'une nouvelle version.

---

### 4. reviews-canary-v3.yaml
Route 90% du trafic vers **v1** et 10% vers **v3**.

**Usage :**
```bash
kubectl apply -f reviews-canary-v3.yaml
```

**Cas d'usage :** Canary deployment - déploiement progressif d'une nouvelle version.

---

### 5. reviews-user-based.yaml
Route le trafic basé sur le header `end-user` :
- User **"jason"** → v2 (étoiles noires)
- Autres users → v3 (étoiles rouges)

**Usage :**
```bash
kubectl apply -f reviews-user-based.yaml
```

**Test :**
1. Ouvrir Bookinfo sans login → étoiles rouges
2. Se connecter avec username "jason" → étoiles noires
3. Se déconnecter → étoiles rouges

**Cas d'usage :** A/B testing par utilisateur.

---

## Utilisation avec le script

Au lieu d'appliquer manuellement, vous pouvez utiliser le script interactif :

```bash
cd ../../scripts
./apply-routing-scenario.sh
```

Le script vous guide pour choisir et appliquer le scénario souhaité.

## Visualisation

Pour voir l'effet du routage :

1. Appliquer un scénario
2. Générer du trafic :
   ```bash
   ./generate-traffic.sh 100
   ```
3. Ouvrir Kiali pour visualiser la distribution

## Retour au comportement par défaut

Pour revenir au round-robin équilibré (33/33/34) :

```bash
kubectl apply -f ../traffic-management.yaml
```

Ou via le script :
```bash
./apply-routing-scenario.sh
# Choisir option 1: default
```
