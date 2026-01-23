#!/bin/bash
# Script pour créer un utilisateur Keycloak exemple avec le rôle nova:reboot

set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak.141.94.213.210.xip.opensteak.fr}"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-2gD7pwIPldZfsxsq}"
REALM_NAME="${REALM_NAME:-openstack}"
USERNAME="${USERNAME:-nova-restart-user}"
PASSWORD="${PASSWORD:-changeme}"
PROJECT_ID="${PROJECT_ID:-}"
PROJECT_NAME="${PROJECT_NAME:-admin}"

if [ -z "$PROJECT_ID" ]; then
  echo "❌ Erreur: PROJECT_ID non défini"
  echo "Usage: PROJECT_ID=<id> PROJECT_NAME=<name> ./create-keycloak-user.sh"
  exit 1
fi

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

# Créer le rôle nova:reboot s'il n'existe pas
echo "📝 Création du rôle nova:reboot..."
ROLE_EXISTS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles/nova:reboot" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" 2>/dev/null | jq -r '.id // empty')

if [ -z "$ROLE_EXISTS" ] || [ "$ROLE_EXISTS" == "null" ]; then
  curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "nova:reboot",
      "description": "Permission to reboot Nova instances"
    }' > /dev/null
  echo "✅ Rôle nova:reboot créé"
else
  echo "ℹ️  Rôle nova:reboot existe déjà"
fi

# Créer l'utilisateur
echo "📝 Création de l'\''utilisateur ${USERNAME}..."
USER_EXISTS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=${USERNAME}" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.[0].id // empty')

if [ -z "$USER_EXISTS" ] || [ "$USER_EXISTS" == "null" ]; then
  USER_ID=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"username\": \"${USERNAME}\",
      \"email\": \"${USERNAME}@example.com\",
      \"firstName\": \"Nova\",
      \"lastName\": \"Restart\",
      \"enabled\": true,
      \"attributes\": {
        \"project_id\": [\"${PROJECT_ID}\"],
        \"project_name\": [\"${PROJECT_NAME}\"],
        \"project_domain\": [\"Default\"],
        \"user_domain\": [\"Default\"]
      }
    }" | jq -r '.id // empty')
  
  if [ -z "$USER_ID" ] || [ "$USER_ID" == "null" ]; then
    echo "❌ Erreur: Impossible de créer l'utilisateur"
    exit 1
  fi
  
  echo "✅ Utilisateur ${USERNAME} créé (ID: ${USER_ID})"
  
  # Définir le mot de passe
  curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/reset-password" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"type\": \"password\",
      \"value\": \"${PASSWORD}\",
      \"temporary\": false
    }" > /dev/null
  echo "✅ Mot de passe défini pour ${USERNAME}"
  
  # Assigner le rôle nova:reboot
  ROLE_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles/nova:reboot" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.id')
  
  curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/role-mappings/realm" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "[{\"id\":\"${ROLE_ID}\",\"name\":\"nova:reboot\"}]" > /dev/null
  echo "✅ Rôle nova:reboot assigné à ${USERNAME}"
  
else
  echo "ℹ️  Utilisateur ${USERNAME} existe déjà (ID: ${USER_EXISTS})"
  USER_ID="$USER_EXISTS"
fi

echo ""
echo "✅ Configuration terminée !"
echo ""
echo "📋 Informations de connexion :"
echo "   Username: ${USERNAME}"
echo "   Password: ${PASSWORD}"
echo "   Project ID: ${PROJECT_ID}"
echo "   Project Name: ${PROJECT_NAME}"
echo ""
echo "🧪 Test d'obtention d'un token :"
echo "curl -X POST \"${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/token\" \\"
echo "  -H \"Content-Type: application/x-www-form-urlencoded\" \\"
echo "  -d \"client_id=openstack-client\" \\"
echo "  -d \"username=${USERNAME}\" \\"
echo "  -d \"password=${PASSWORD}\" \\"
echo "  -d \"grant_type=password\" \\"
echo "  -d \"scope=openid\" | jq -r '.access_token'"
