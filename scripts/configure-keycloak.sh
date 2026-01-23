#!/bin/bash
# Script pour configurer Keycloak pour l'intégration avec OpenStack Nova

set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak.141.94.213.210.xip.opensteak.fr}"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-2gD7pwIPldZfsxsq}"
REALM_NAME="${REALM_NAME:-openstack}"

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

echo "✅ Token admin obtenu"

# Créer le realm OpenStack
echo "📦 Création du realm ${REALM_NAME}..."
REALM_EXISTS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.id // empty')

if [ -z "$REALM_EXISTS" ]; then
  curl -s -X POST "${KEYCLOAK_URL}/admin/realms" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"realm\": \"${REALM_NAME}\",
      \"enabled\": true
    }" > /dev/null
  echo "✅ Realm ${REALM_NAME} créé"
else
  echo "ℹ️  Realm ${REALM_NAME} existe déjà"
fi

# Créer le client nova-middleware
echo "🔧 Configuration du client nova-middleware..."
CLIENT_EXISTS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=nova-middleware" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.[0].id // empty')

if [ -z "$CLIENT_EXISTS" ]; then
  CLIENT_ID=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "clientId": "nova-middleware",
      "enabled": true,
      "clientAuthenticatorType": "client-secret",
      "secret": "",
      "serviceAccountsEnabled": true,
      "standardFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "publicClient": false
    }' | jq -r '.id // empty')
  
  # Récupérer le secret
  CLIENT_SECRET=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=nova-middleware" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.[0].id' | xargs -I {} curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/{}/client-secret" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.value')
  
  echo "✅ Client nova-middleware créé"
  echo "🔑 Client Secret: ${CLIENT_SECRET}"
  echo "⚠️  IMPORTANT: Ajoutez ce secret dans config/config.yaml sous keycloak_client_secret"
  
  # Assigner le rôle view-clients au service account
  SERVICE_ACCOUNT_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=nova-middleware" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.[0].serviceAccountsEnabled // false')
  
  if [ "$SERVICE_ACCOUNT_ID" == "true" ]; then
    SERVICE_ACCOUNT_USER_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=nova-middleware" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" | jq -r '.[0].id' | xargs -I {} curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/{}/service-account-user" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" | jq -r '.id')
    
    REALM_MANAGEMENT_CLIENT_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=realm-management" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" | jq -r '.[0].id')
    
    VIEW_CLIENTS_ROLE_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/${REALM_MANAGEMENT_CLIENT_ID}/roles/view-clients" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" | jq -r '.id')
    
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${SERVICE_ACCOUNT_USER_ID}/role-mappings/clients/${REALM_MANAGEMENT_CLIENT_ID}" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "[{\"id\":\"${VIEW_CLIENTS_ROLE_ID}\",\"name\":\"view-clients\"}]" > /dev/null
    
    echo "✅ Rôle view-clients assigné au service account"
  fi
else
  echo "ℹ️  Client nova-middleware existe déjà"
  CLIENT_SECRET=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=nova-middleware" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.[0].id' | xargs -I {} curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/{}/client-secret" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.value')
  echo "🔑 Client Secret existant: ${CLIENT_SECRET}"
fi

# Créer le client openstack-client
echo "🔧 Configuration du client openstack-client..."
CLIENT_EXISTS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=openstack-client" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.[0].id // empty')

if [ -z "$CLIENT_EXISTS" ]; then
  curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "clientId": "openstack-client",
      "enabled": true,
      "publicClient": true,
      "standardFlowEnabled": true,
      "directAccessGrantsEnabled": true,
      "serviceAccountsEnabled": false,
      "redirectUris": ["*"],
      "webOrigins": ["*"]
    }' > /dev/null
  echo "✅ Client openstack-client créé"
else
  echo "ℹ️  Client openstack-client existe déjà"
fi

echo ""
echo "✅ Configuration de base terminée !"
echo ""
echo "📝 Prochaines étapes manuelles :"
echo "1. Connectez-vous à Keycloak: ${KEYCLOAK_URL}"
echo "2. Allez dans le realm '${REALM_NAME}'"
echo "3. Configurez les mappers pour les tokens (voir docs/KEYCLOAK_SETUP.md)"
echo "4. Créez un utilisateur exemple avec les attributs project_id, project_name, etc."
echo "5. Ajoutez le client secret dans config/config.yaml: keycloak_client_secret: ${CLIENT_SECRET}"
