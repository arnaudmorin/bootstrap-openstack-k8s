#!/bin/bash
# Script pour configurer Keycloak via l'API REST en une seule fois

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

# Vérifier que le fichier de config existe
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Erreur: Fichier de configuration $CONFIG_FILE non trouvé"
  exit 1
fi

echo "🚀 Configuration de Keycloak depuis ${CONFIG_FILE}..."

# Créer le realm s'il n'existe pas
REALM_EXISTS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.id // empty')

if [ -z "$REALM_EXISTS" ] || [ "$REALM_EXISTS" == "null" ]; then
  echo "📦 Création du realm ${REALM_NAME}..."
  curl -s -X POST "${KEYCLOAK_URL}/admin/realms" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"realm\": \"${REALM_NAME}\", \"enabled\": true}" > /dev/null
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
  EXISTING=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients?clientId=${CLIENT_ID}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.[0].id // empty')
  
  if [ -z "$EXISTING" ] || [ "$EXISTING" == "null" ]; then
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$client_json" > /dev/null
    echo "    ✅ Créé"
  else
    echo "    ℹ️  Existe déjà"
  fi
done

# Créer les rôles
echo "📝 Création des rôles..."
ROLES_COUNT=$(echo "$CONFIG_JSON" | jq '.roles.realm | length')
for i in $(seq 0 $((ROLES_COUNT - 1))); do
  role_json=$(echo "$CONFIG_JSON" | jq -c ".roles.realm[${i}]")
  ROLE_NAME=$(echo "$role_json" | jq -r '.name')
  echo "  → Rôle: $ROLE_NAME"
  
  # Vérifier si le rôle existe
  EXISTING=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles/${ROLE_NAME}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" 2>/dev/null | jq -r '.id // empty')
  
  if [ -z "$EXISTING" ] || [ "$EXISTING" == "null" ]; then
    curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$role_json" > /dev/null
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
  
  # Créer l'utilisateur sans credentials et roles
  USER_DATA=$(echo "$user_json" | jq 'del(.credentials, .realmRoles)')
  
  # Vérifier si l'utilisateur existe
  EXISTING=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users?username=${USERNAME}" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.[0].id // empty')
  
  if [ -z "$EXISTING" ] || [ "$EXISTING" == "null" ]; then
    USER_ID=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$USER_DATA" | jq -r '.id // empty' || echo "")
    
    if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
      echo "    ✅ Utilisateur créé"
      
      # Définir le mot de passe
      if [ -n "$PASSWORD" ]; then
        curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/reset-password" \
          -H "Authorization: Bearer ${ADMIN_TOKEN}" \
          -H "Content-Type: application/json" \
          -d "{\"type\": \"password\", \"value\": \"${PASSWORD}\", \"temporary\": false}" > /dev/null
        echo "    ✅ Mot de passe défini"
      fi
      
      # Assigner les rôles
      for role in $REALM_ROLES; do
        ROLE_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles/${role}" \
          -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.id')
        
        if [ -n "$ROLE_ID" ] && [ "$ROLE_ID" != "null" ]; then
          curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/role-mappings/realm" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "[{\"id\":\"${ROLE_ID}\",\"name\":\"${role}\"}]" > /dev/null
        fi
      done
      if [ -n "$REALM_ROLES" ]; then
        echo "    ✅ Rôles assignés"
      fi
    fi
  else
    echo "    ℹ️  Existe déjà, mise à jour complète..."
    USER_ID=$EXISTING
    
    # Mettre à jour les attributs
    curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$USER_DATA" > /dev/null
    echo "    ✅ Attributs mis à jour"
    
    # Définir le mot de passe
    if [ -n "$PASSWORD" ]; then
      curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/reset-password" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"type\": \"password\", \"value\": \"${PASSWORD}\", \"temporary\": false}" > /dev/null
      echo "    ✅ Mot de passe mis à jour"
    fi
    
    # Supprimer tous les rôles existants et réassigner
    EXISTING_ROLES=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/role-mappings/realm" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.[].id // empty')
    
    if [ -n "$EXISTING_ROLES" ]; then
      for role_id in $EXISTING_ROLES; do
        ROLE_NAME=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles-by-id/${role_id}" \
          -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.name')
        if [ -n "$ROLE_NAME" ] && [ "$ROLE_NAME" != "null" ]; then
          curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/role-mappings/realm" \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "[{\"id\":\"${role_id}\",\"name\":\"${ROLE_NAME}\"}]" > /dev/null
        fi
      done
    fi
    
    # Assigner les nouveaux rôles
    for role in $REALM_ROLES; do
      ROLE_ID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/roles/${role}" \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" | jq -r '.id')
      
      if [ -n "$ROLE_ID" ] && [ "$ROLE_ID" != "null" ]; then
        curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users/${USER_ID}/role-mappings/realm" \
          -H "Authorization: Bearer ${ADMIN_TOKEN}" \
          -H "Content-Type: application/json" \
          -d "[{\"id\":\"${ROLE_ID}\",\"name\":\"${role}\"}]" > /dev/null
      fi
    done
    if [ -n "$REALM_ROLES" ]; then
      echo "    ✅ Rôles mis à jour"
    fi
  fi
done

# Récupérer le client secret de nova-middleware
echo ""
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
