#!/bin/bash
DOMAIN="monkong.duckdns.org"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
KONG_SSL_PATH="./ssl"

# Créer le répertoire SSL s'il n'existe pas
mkdir -p "$KONG_SSL_PATH"

# Vérifier si les certificats existent
if [ -f "$CERT_PATH/fullchain.pem" ] && [ -f "$CERT_PATH/privkey.pem" ]; then
  echo "Certificats trouvés pour $DOMAIN"
  
  # Copier le certificat et la clé
  sudo cp "$CERT_PATH/fullchain.pem" "$KONG_SSL_PATH/$DOMAIN.crt"
  sudo cp "$CERT_PATH/privkey.pem" "$KONG_SSL_PATH/$DOMAIN.key"
  
  # Combiner fullchain et clé privée pour Kong
  sudo bash -c "cat $CERT_PATH/fullchain.pem $CERT_PATH/privkey.pem > $KONG_SSL_PATH/$DOMAIN.pem"
  
  # Définir les permissions appropriées
  sudo chmod 644 "$KONG_SSL_PATH/$DOMAIN.crt"
  sudo chmod 644 "$KONG_SSL_PATH/$DOMAIN.key"
  sudo chmod 644 "$KONG_SSL_PATH/$DOMAIN.pem"
  
  # S'assurer que Docker peut lire les fichiers
  sudo chown $USER:$USER "$KONG_SSL_PATH/$DOMAIN.crt"
  sudo chown $USER:$USER "$KONG_SSL_PATH/$DOMAIN.key"
  sudo chown $USER:$USER "$KONG_SSL_PATH/$DOMAIN.pem"
  
  echo "Certificats préparés pour Kong dans $KONG_SSL_PATH"
else
  echo "Certificats non trouvés dans $CERT_PATH"
  echo "Assurez-vous d'avoir exécuté Certbot pour obtenir des certificats."
  exit 1
fi
