# kong-certbot

# Kong API Gateway avec SSL

Ce document décrit la configuration d'une instance Kong API Gateway avec SSL activé, utilisant des certificats auto-signés ou Let's Encrypt (pour une prochaine fois).

## Prérequis

- Docker et Docker Compose
- OpenSSL pour la génération des certificats
- Un nom de domaine (pour notre exemple: monkong.duckdns.org)

## Structure du projet

```
kong-certbot/
├── docker-compose.yml
├── prepare-kong-certs.sh
└── ssl/
    ├── rootCA.key
    ├── rootCA.pem
    ├── monkong.duckdns.org.conf
    ├── monkong.duckdns.org.csr
    ├── monkong.duckdns.org.crt
    ├── monkong.duckdns.org.key
    └── monkong.duckdns.org.pem
```

## Configuration

### 1. Fichier docker-compose.yml

```yaml
version: '3'

services:
  # Base de données Kong
  kong-database:
    image: postgres:13
    container_name: kong-database
    restart: always
    environment:
      POSTGRES_USER: kong
      POSTGRES_DB: kong
      POSTGRES_PASSWORD: kong_pass
    volumes:
      - kong_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "kong"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - kong-net

  # Migration Kong
  kong-migration:
    image: kong:latest
    command: "kong migrations bootstrap"
    restart: on-failure
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong_pass
    depends_on:
      - kong-database
    networks:
      - kong-net

  # Kong Gateway avec SSL
  kong:
    image: kong:latest
    container_name: kong
    restart: always
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong_pass
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001
      KONG_PROXY_LISTEN: 0.0.0.0:8000, 0.0.0.0:8443 ssl
      KONG_SSL: "on"
    depends_on:
      - kong-migration
    ports:
      - "8000:8000"
      - "8443:8443"
      - "8001:8001"
    networks:
      - kong-net

networks:
  kong-net:
    driver: bridge

volumes:
  kong_data:
    driver: local
```

### 2. Génération des certificats auto-signés

```bash
# Créer le répertoire pour les certificats
mkdir -p ./ssl

# Générer une clé privée pour votre CA
openssl genrsa -out ./ssl/rootCA.key 2048

# Générer un certificat auto-signé pour votre CA
openssl req -x509 -new -nodes -key ./ssl/rootCA.key -sha256 -days 1024 -out ./ssl/rootCA.pem -subj "/C=FR/ST=YourState/L=YourCity/O=YourOrganization/CN=YourCA"

# Générer une clé privée pour votre domaine
openssl genrsa -out ./ssl/monkong.duckdns.org.key 2048

# Créer un fichier de configuration pour la demande de certificat
cat > ./ssl/monkong.duckdns.org.conf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C=FR
ST=YourState
L=YourCity
O=YourOrganization
OU=YourOrganizationalUnit
CN=monkong.duckdns.org

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = monkong.duckdns.org
DNS.2 = localhost
EOF

# Générer une demande de certificat (CSR)
openssl req -new -key ./ssl/monkong.duckdns.org.key -out ./ssl/monkong.duckdns.org.csr -config ./ssl/monkong.duckdns.org.conf

# Signer la demande avec votre CA
openssl x509 -req -in ./ssl/monkong.duckdns.org.csr -CA ./ssl/rootCA.pem -CAkey ./ssl/rootCA.key -CAcreateserial -out ./ssl/monkong.duckdns.org.crt -days 365 -sha256 -extensions req_ext -extfile ./ssl/monkong.duckdns.org.conf

# Créer le fichier PEM combinant certificat et clé pour Kong
cat ./ssl/monkong.duckdns.org.crt ./ssl/monkong.duckdns.org.key > ./ssl/monkong.duckdns.org.pem

# Définir les permissions appropriées
chmod 644 ./ssl/monkong.duckdns.org.crt
chmod 644 ./ssl/monkong.duckdns.org.key
chmod 644 ./ssl/monkong.duckdns.org.pem
```

### 3. Démarrage initial de Kong sans SSL

Si vous rencontrez des problèmes de permissions avec les certificats, vous pouvez démarrer Kong sans SSL temporairement :

1. Modifiez docker-compose.yml :
```yaml
# Dans la section environment de kong
KONG_ADMIN_LISTEN: 0.0.0.0:8001
KONG_PROXY_LISTEN: 0.0.0.0:8000
# Commentez ces lignes
# KONG_PROXY_LISTEN: 0.0.0.0:8000, 0.0.0.0:8443 ssl
# KONG_SSL: "on"
```

2. Démarrez les conteneurs :
```bash
docker-compose down
docker-compose up -d
```

### 4. Configuration des certificats via l'API Admin

Une fois Kong démarré, configurez les certificats via l'API Admin :

```bash
# Ajouter le certificat à Kong
curl -i -X POST http://localhost:8001/certificates \
  -F "cert=@./ssl/monkong.duckdns.org.crt" \
  -F "key=@./ssl/monkong.duckdns.org.key" \
  -F "snis=monkong.duckdns.org"

# Vérifier que le certificat a été ajouté
curl http://localhost:8001/certificates
```

### 5. Réactivation de SSL

Modifiez à nouveau docker-compose.yml pour réactiver SSL :

```yaml
# Dans la section environment de kong
KONG_ADMIN_LISTEN: 0.0.0.0:8001
KONG_PROXY_LISTEN: 0.0.0.0:8000, 0.0.0.0:8443 ssl
KONG_SSL: "on"
```

Redémarrez Kong pour appliquer les changements :
```bash
docker-compose restart kong
```

### 6. Test de la configuration

Créez un service et une route de test :

```bash
# Créer un service de test
curl -i -X POST http://localhost:8001/services \
  --data name=example-service \
  --data url='http://mockbin.org'

# Créer une route pour ce service
curl -i -X POST http://localhost:8001/services/example-service/routes \
  --data 'paths[]=/example' \
  --data name=example-route

# Ou un service httpbin
curl -i -X POST http://localhost:8001/services \
  --data name=httpbin-service \
  --data url='https://httpbin.org'

curl -i -X POST http://localhost:8001/services/httpbin-service/routes \
  --data 'paths[]=/test' \
  --data name=httpbin-route
```

Testez avec curl :
```bash
# Test HTTPS
curl -k https://localhost:8443/example

# Test avec nom de domaine spécifique
curl -k https://localhost:8443/example -H "Host: monkong.duckdns.org"

# Test du service httpbin
curl -k https://localhost:8443/test
```

## Script d'automatisation (prepare-kong-certs.sh)

Ce script automatise la configuration des certificats, soit auto-signés soit depuis Let's Encrypt (pour plus tard) :

```bash
#!/bin/bash
DOMAIN="monkong.duckdns.org"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
KONG_SSL_PATH="./ssl"
KONG_ADMIN_URL="http://localhost:8001"

# Vérifier si l'API Admin de Kong est accessible
if ! curl -s $KONG_ADMIN_URL > /dev/null; then
  echo "Erreur: Impossible d'accéder à l'API Admin de Kong à $KONG_ADMIN_URL"
  exit 1
fi

# Mode de fonctionnement: auto-signé ou Let's Encrypt
if [ "$1" == "--self-signed" ]; then
  echo "Génération de certificats auto-signés pour $DOMAIN"
  
  mkdir -p "$KONG_SSL_PATH"
  
  # Générer une clé privée pour l'autorité de certification
  openssl genrsa -out "$KONG_SSL_PATH/rootCA.key" 2048
  
  # Générer un certificat auto-signé pour l'autorité de certification
  openssl req -x509 -new -nodes -key "$KONG_SSL_PATH/rootCA.key" -sha256 -days 1024 -out "$KONG_SSL_PATH/rootCA.pem" -subj "/C=FR/ST=YourState/L=YourCity/O=YourOrganization/CN=YourCA"
  
  # Générer une clé privée pour le domaine
  openssl genrsa -out "$KONG_SSL_PATH/$DOMAIN.key" 2048
  
  # Créer un fichier de configuration pour la demande de certificat
  cat > "$KONG_SSL_PATH/$DOMAIN.conf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C=FR
ST=YourState
L=YourCity
O=YourOrganization
OU=YourOrganizationalUnit
CN=$DOMAIN

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = localhost
EOF
  
  # Générer une demande de certificat
  openssl req -new -key "$KONG_SSL_PATH/$DOMAIN.key" -out "$KONG_SSL_PATH/$DOMAIN.csr" -config "$KONG_SSL_PATH/$DOMAIN.conf"
  
  # Signer la demande avec l'autorité de certification
  openssl x509 -req -in "$KONG_SSL_PATH/$DOMAIN.csr" -CA "$KONG_SSL_PATH/rootCA.pem" -CAkey "$KONG_SSL_PATH/rootCA.key" -CAcreateserial -out "$KONG_SSL_PATH/$DOMAIN.crt" -days 365 -sha256 -extensions req_ext -extfile "$KONG_SSL_PATH/$DOMAIN.conf"
  
  # Combiner le certificat et la clé pour Kong
  cat "$KONG_SSL_PATH/$DOMAIN.crt" "$KONG_SSL_PATH/$DOMAIN.key" > "$KONG_SSL_PATH/$DOMAIN.pem"
  
  # Définir les permissions appropriées
  chmod 644 "$KONG_SSL_PATH/$DOMAIN.crt"
  chmod 644 "$KONG_SSL_PATH/$DOMAIN.key"
  chmod 644 "$KONG_SSL_PATH/$DOMAIN.pem"
  
  CERT_FILE="$KONG_SSL_PATH/$DOMAIN.crt"
  KEY_FILE="$KONG_SSL_PATH/$DOMAIN.key"
  
  echo "Certificats auto-signés générés avec succès dans $KONG_SSL_PATH"
else
  # Vérifier si les certificats Let's Encrypt existent
  if [ -f "$CERT_PATH/fullchain.pem" ] && [ -f "$CERT_PATH/privkey.pem" ]; then
    echo "Certificats Let's Encrypt trouvés pour $DOMAIN"
    
    # Copier le certificat et la clé
    mkdir -p "$KONG_SSL_PATH"
    sudo cp "$CERT_PATH/fullchain.pem" "$KONG_SSL_PATH/$DOMAIN.crt"
    sudo cp "$CERT_PATH/privkey.pem" "$KONG_SSL_PATH/$DOMAIN.key"
    
    # Combiner fullchain et clé privée pour Kong
    sudo bash -c "cat $CERT_PATH/fullchain.pem $CERT_PATH/privkey.pem > $KONG_SSL_PATH/$DOMAIN.pem"
    
    # Définir les permissions appropriées
    sudo chmod 644 "$KONG_SSL_PATH/$DOMAIN.crt"
    sudo chmod 644 "$KONG_SSL_PATH/$DOMAIN.key"
    sudo chmod 644 "$KONG_SSL_PATH/$DOMAIN.pem"
    
    # S'assurer que les fichiers sont lisibles
    sudo chown $USER:$USER "$KONG_SSL_PATH/$DOMAIN.crt"
    sudo chown $USER:$USER "$KONG_SSL_PATH/$DOMAIN.key"
    sudo chown $USER:$USER "$KONG_SSL_PATH/$DOMAIN.pem"
    
    CERT_FILE="$KONG_SSL_PATH/$DOMAIN.crt"
    KEY_FILE="$KONG_SSL_PATH/$DOMAIN.key"
    
    echo "Certificats Let's Encrypt préparés pour Kong dans $KONG_SSL_PATH"
  else
    echo "Certificats Let's Encrypt non trouvés dans $CERT_PATH"
    echo "Assurez-vous d'avoir exécuté Certbot pour obtenir des certificats, ou utilisez --self-signed pour générer des certificats auto-signés."
    exit 1
  fi
fi

# Configurer les certificats dans Kong via l'API Admin
echo "Configuration des certificats dans Kong..."

# Vérifier si le certificat existe déjà et le supprimer
CERT_ID=$(curl -s $KONG_ADMIN_URL/certificates | grep -o '"id":"[^"]*"' | head -1 | cut -d '"' -f 4)
if [ ! -z "$CERT_ID" ]; then
  echo "Suppression du certificat existant (ID: $CERT_ID)..."
  curl -i -X DELETE $KONG_ADMIN_URL/certificates/$CERT_ID
fi

# Ajouter le nouveau certificat
echo "Ajout du nouveau certificat..."
curl -i -X POST $KONG_ADMIN_URL/certificates \
  -F "cert=@$CERT_FILE" \
  -F "key=@$KEY_FILE" \
  -F "snis=$DOMAIN"

echo "Certificats configurés avec succès dans Kong!"
```

Usage:
```bash
# Pour générer et configurer des certificats auto-signés
./prepare-kong-certs.sh --self-signed

# Pour configurer des certificats Let's Encrypt existants
./prepare-kong-certs.sh
```

## Utilisation avec Let's Encrypt

Pour utiliser des certificats Let's Encrypt :

1. Obtenez les certificats avec Certbot :
```bash
sudo certbot certonly --standalone -d monkong.duckdns.org
```

2. Configurez Kong avec les certificats :
```bash
./prepare-kong-certs.sh
```
