#!/bin/bash
# Script pour configurer Keycloak avec kcadm.sh en une seule fois

set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak.141.94.213.210.xip.opensteak.fr}"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-2gD7pwIPldZfsxsq}"
REALM_NAME="${REALM_NAME:-openstack}"
CONFIG_FILE="${CONFIG_FILE:-/root/keycloak-config.json}"

echo "🔐 Connexion à Keycloak..."
ADMIN_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${KEYCLOAK_ADMIN}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ "$ADMIN_TOKEN" == "null" ] || [ -z "$ADMIN_TOKEN" ]; then
  echo "❌ Erreur: Impossible d'obtenir le token admin"
  exit 1
fi

# Supprimer l'utilisateur existant s'il existe
echo "🗑️  Suppression de l'utilisateur existant (s'il existe)..."
USER_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=nova-restart-user" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.[0].id // empty')

if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
  curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" > /dev/null
  echo "✅ Utilisateur nova-restart-user supprimé"
fi

# Vérifier si kcadm.sh est installé (CLI officielle Keycloak)
if ! command -v kcadm.sh &> /dev/null; then
  echo "📦 Installation de kcadm.sh..."
  # Télécharger kcadm.sh depuis les releases Keycloak
  KEYCLOAK_VERSION="26.0.0"
  curl -sL "https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/kcadm.sh" -o /usr/local/bin/kcadm.sh
  chmod +x /usr/local/bin/kcadm.sh
  echo "✅ kcadm.sh installé"
fi

# Créer le fichier de configuration kcadm
echo "📝 Création du fichier de configuration kcadm..."
cat > /root/.kcadm.config <<EOF
{
  "serverUrl": "${KEYCLOAK_URL}",
  "realm": "master"
}
EOF

# Vérifier que le fichier de config existe
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Erreur: Fichier de configuration $CONFIG_FILE non trouvé"
  exit 1
fi

echo "🔐 Authentification avec kcadm.sh..."
kcadm.sh config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm master \
  --user "${KEYCLOAK_ADMIN}" \
  --password "${KEYCLOAK_ADMIN_PASSWORD}" \
  --config /root/.kcadm.config

if [ $? -ne 0 ]; then
  echo "❌ Erreur lors de l'authentification"
  exit 1
fi

echo "🚀 Configuration de Keycloak..."

# Créer le realm s'il n'existe pas
REALM_EXISTS=$(kcadm.sh get realms/${REALM_NAME} --config /root/.kcadm.config 2>/dev/null | jq -r '.id // empty' || echo "")
if [ -z "$REALM_EXISTS" ] || [ "$REALM_EXISTS" == "null" ]; then
  echo "📦 Création du realm ${REALM_NAME}..."
  echo '{"realm": "'${REALM_NAME}'", "enabled": true}' | kcadm.sh create realms --config /root/.kcadm.config -f -
  echo "✅ Realm ${REALM_NAME} créé"
else
  echo "ℹ️  Realm ${REALM_NAME} existe déjà"
fi

# Lire le JSON de configuration
CONFIG_JSON=$(cat "$CONFIG_FILE")

# Créer les clients
echo "📝 Création des clients..."
for client_json in $(echo "$CONFIG_JSON" | jq -c '.clients[]'); do
  CLIENT_ID=$(echo "$client_json" | jq -r '.clientId')
  echo "  → Client: $CLIENT_ID"
  
  # Vérifier si le client existe
  EXISTING=$(kcadm.sh get clients --config /root/.kcadm.config -r ${REALM_NAME} --fields id,clientId 2>/dev/null | jq -r ".[] | select(.clientId == \"${CLIENT_ID}\") | .id" || echo "")
  
  if [ -z "$EXISTING" ] || [ "$EXISTING" == "null" ]; then
    echo "$client_json" | kcadm.sh create clients --config /root/.kcadm.config -r ${REALM_NAME} -f - 2>/dev/null
    echo "    ✅ Créé"
  else
    echo "    ℹ️  Existe déjà"
  fi
done

# Créer les rôles
echo "📝 Création des rôles..."
for role_json in $(echo "$CONFIG_JSON" | jq -c '.roles.realm[]'); do
  ROLE_NAME=$(echo "$role_json" | jq -r '.name')
  echo "  → Rôle: $ROLE_NAME"
  
  # Vérifier si le rôle existe
  EXISTING=$(kcadm.sh get roles --config /root/.kcadm.config -r ${REALM_NAME} --fields name 2>/dev/null | jq -r ".[] | select(.name == \"${ROLE_NAME}\") | .name" || echo "")
  
  if [ -z "$EXISTING" ] || [ "$EXISTING" == "null" ]; then
    echo "$role_json" | kcadm.sh create roles --config /root/.kcadm.config -r ${REALM_NAME} -f - 2>/dev/null
    echo "    ✅ Créé"
  else
    echo "    ℹ️  Existe déjà"
  fi
done

# Créer les utilisateurs
echo "📝 Création des utilisateurs..."
for user_json in $(echo "$CONFIG_JSON" | jq -c '.users[]'); do
  USERNAME=$(echo "$user_json" | jq -r '.username')
  echo "  → Utilisateur: $USERNAME"
  
  # Extraire les informations
  PASSWORD=$(echo "$user_json" | jq -r '.credentials[0].value // empty')
  REALM_ROLES=$(echo "$user_json" | jq -r '.realmRoles[] // empty')
  USER_ATTRS=$(echo "$user_json" | jq '.attributes')
  
  # Créer l'utilisateur sans credentials et roles
  USER_DATA=$(echo "$user_json" | jq 'del(.credentials, .realmRoles)')
  
  # Vérifier si l'utilisateur existe
  EXISTING=$(kcadm.sh get users --config /root/.kcadm.config -r ${REALM_NAME} --query username=${USERNAME} 2>/dev/null | jq -r '.[0].id // empty' || echo "")
  
  if [ -z "$EXISTING" ] || [ "$EXISTING" == "null" ]; then
    echo "$USER_DATA" | kcadm.sh create users --config /root/.kcadm.config -r ${REALM_NAME} -f - 2>/dev/null
    echo "    ✅ Utilisateur créé"
    
    # Définir le mot de passe
    if [ -n "$PASSWORD" ]; then
      kcadm.sh set-password --config /root/.kcadm.config -r ${REALM_NAME} --username ${USERNAME} --new-password "${PASSWORD}" --temporary false 2>/dev/null
      echo "    ✅ Mot de passe défini"
    fi
    
    # Assigner les rôles
    for role in $REALM_ROLES; do
      kcadm.sh add-roles --config /root/.kcadm.config -r ${REALM_NAME} --uusername ${USERNAME} --rolename ${role} 2>/dev/null
    done
    if [ -n "$REALM_ROLES" ]; then
      echo "    ✅ Rôles assignés"
    fi
  else
    echo "    ℹ️  Existe déjà, mise à jour..."
    # Mettre à jour les attributs
    if [ "$USER_ATTRS" != "null" ] && [ -n "$USER_ATTRS" ]; then
      USER_ID=$EXISTING
      echo "$USER_DATA" | kcadm.sh update users/${USER_ID} --config /root/.kcadm.config -r ${REALM_NAME} -f - 2>/dev/null
      echo "    ✅ Attributs mis à jour"
    fi
  fi
done

echo "✅ Configuration terminée !"

# Récupérer le client secret de nova-middleware
echo "🔑 Récupération du client secret..."
CLIENT_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=nova-middleware" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.[0].id')

CLIENT_SECRET=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/${CLIENT_ID}/client-secret" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.value')

echo ""
echo "✅ Configuration terminée !"
echo ""
echo "🔑 Client Secret (nova-middleware): ${CLIENT_SECRET}"
echo "📝 Ajoutez ce secret dans config/config.yaml:"
echo "   keycloak_client_secret: ${CLIENT_SECRET}"
echo ""
echo "🧪 Test de l'utilisateur:"
echo "   Username: nova-restart-user"
echo "   Password: changeme"
echo "   Project: demo (utilisateur standard, pas admin)"
