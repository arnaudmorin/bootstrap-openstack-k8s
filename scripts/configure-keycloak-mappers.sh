#!/bin/bash
# Script pour configurer les mappers Keycloak pour OpenStack

set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak.141.94.213.210.xip.opensteak.fr}"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-2gD7pwIPldZfsxsq}"
REALM_NAME="${REALM_NAME:-openstack}"
CLIENT_ID="${CLIENT_ID:-openstack-client}"

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

# Récupérer l'ID du client
CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=${CLIENT_ID}" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.[0].id')

if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" == "null" ]; then
  echo "❌ Erreur: Client ${CLIENT_ID} non trouvé"
  exit 1
fi

echo "✅ Client UUID: ${CLIENT_UUID}"

# Fonction pour créer un mapper s'il n'existe pas
create_mapper() {
  local name=$1
  local mapper_type=$2
  local user_attribute=$3
  local token_claim=$4
  
  echo "📝 Création du mapper: ${name}..."
  
  # Vérifier si le mapper existe déjà (au niveau du client)
  EXISTING=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/${CLIENT_UUID}/protocol-mappers/models" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" | jq -r ".[] | select(.name == \"${name}\") | .id" 2>/dev/null || echo "")
  
  if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ] && [ "$EXISTING" != "" ]; then
    echo "ℹ️  Mapper ${name} existe déjà"
    return
  fi
  
  if [ "$mapper_type" == "User Attribute" ]; then
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/${CLIENT_UUID}/protocol-mappers/models" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${name}\",
        \"protocol\": \"openid-connect\",
        \"protocolMapper\": \"oidc-usermodel-attribute-mapper\",
        \"config\": {
          \"user.attribute\": \"${user_attribute}\",
          \"claim.name\": \"${token_claim}\",
          \"jsonType.label\": \"String\",
          \"id.token.claim\": \"true\",
          \"access.token.claim\": \"true\",
          \"userinfo.token.claim\": \"true\"
        }
      }" > /dev/null
  elif [ "$mapper_type" == "User Realm Role" ]; then
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients/${CLIENT_UUID}/protocol-mappers/models" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${name}\",
        \"protocol\": \"openid-connect\",
        \"protocolMapper\": \"oidc-usermodel-realm-role-mapper\",
        \"config\": {
          \"claim.name\": \"${token_claim}\",
          \"multivalued\": \"true\",
          \"id.token.claim\": \"true\",
          \"access.token.claim\": \"true\",
          \"userinfo.token.claim\": \"true\"
        }
      }" > /dev/null
  fi
  
  echo "✅ Mapper ${name} créé"
}

# Créer les mappers
create_mapper "project_id" "User Attribute" "project_id" "project_id"
create_mapper "project_name" "User Attribute" "project_name" "project_name"
create_mapper "project_domain" "User Attribute" "project_domain" "project_domain"
create_mapper "user_domain" "User Attribute" "user_domain" "user_domain"
create_mapper "openstack_roles" "User Realm Role" "" "realm_access.roles"

echo ""
echo "✅ Tous les mappers ont été configurés !"
echo ""
echo "📝 Prochaines étapes :"
echo "1. Créez un utilisateur dans Keycloak avec les attributs suivants :"
echo "   - project_id: <ID_DU_PROJET_OPENSTACK>"
echo "   - project_name: <NOM_DU_PROJET_OPENSTACK>"
echo "   - project_domain: Default"
echo "   - user_domain: Default"
echo "2. Assignez un rôle (ex: nova:reboot) à l'utilisateur"
echo "3. Testez l'authentification avec un token OAuth2"
