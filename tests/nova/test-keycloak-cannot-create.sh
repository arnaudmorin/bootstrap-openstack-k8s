#!/bin/bash
# Test: Verify that Keycloak OAuth2 cannot create instances (only reboot allowed)
# This test verifies that the demo user with Keycloak OAuth2 cannot create instances

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=== Test: Keycloak OAuth2 Cannot Create Instance (demo) ==="
echo ""

# Load demo openrc to get project info
if [ -f /root/openrc_demo ]; then
  source /root/openrc_demo
else
  echo "❌ File /root/openrc_demo not found"
  exit 1
fi

# Get project ID
PROJECT_ID=$(openstack project show "${OS_PROJECT_NAME}" -c id -f value 2>&1)
if [ -z "${PROJECT_ID}" ]; then
  echo "❌ Cannot get project ID for ${OS_PROJECT_NAME}"
  exit 1
fi
echo "✅ Project ID: ${PROJECT_ID}"
echo ""

# Load Keycloak configuration
if [ -f /root/keycloakrc ]; then
  source /root/keycloakrc
else
  echo "❌ File /root/keycloakrc not found"
  exit 1
fi

echo "✅ Loaded Keycloak configuration"
echo "   KEYCLOAK_URL=${KEYCLOAK_URL}"
echo "   KEYCLOAK_REALM=${KEYCLOAK_REALM}"
echo ""

# Get Nova API URL from openrc
NOVA_URL=$(echo "${OS_AUTH_URL}" | sed 's|keystone|nova|g' | sed 's|/v3||g')
echo "✅ Nova API URL: ${NOVA_URL}"
echo ""

# Get OAuth2 token from Keycloak for demo user
echo "1. Obtaining OAuth2 token from Keycloak..."
TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=openstack-client" \
  -d "username=${OS_USERNAME}" \
  -d "password=${OS_PASSWORD}" \
  -d "grant_type=password" \
  -d "scope=openid")

ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")

if [ -z "${ACCESS_TOKEN}" ] || [ "${ACCESS_TOKEN}" == "None" ]; then
  echo "   ❌ Failed to obtain OAuth2 token"
  echo "   Response: ${TOKEN_RESPONSE}"
  echo ""
  echo "   ℹ️  Note: The demo user may need to be created in Keycloak first"
  exit 1
fi

echo "   ✅ OAuth2 token obtained"
echo "   Token (first 20 chars): ${ACCESS_TOKEN:0:20}..."
echo ""

# Get available image and flavor (using Keystone for this)
echo "2. Getting image and flavor info (using Keystone)..."
IMAGE_ID=$(openstack image list --limit 1 -c ID -f value 2>&1 | head -1)
FLAVOR_NAME=$(openstack flavor list --limit 1 -c Name -f value 2>&1 | head -1)

if [ -z "${IMAGE_ID}" ] || [ -z "${FLAVOR_NAME}" ]; then
  echo "   ❌ Cannot get image or flavor"
  exit 1
fi

echo "   ✅ Image ID: ${IMAGE_ID}"
echo "   ✅ Flavor: ${FLAVOR_NAME}"
echo ""

# Try to create instance using OAuth2 token
echo "3. Attempting to create instance with OAuth2 token..."
INSTANCE_NAME="test-instance-keycloak-$(date +%s)"

# Prepare server creation request
SERVER_CREATE_JSON=$(cat <<EOF
{
  "server": {
    "name": "${INSTANCE_NAME}",
    "imageRef": "${IMAGE_ID}",
    "flavorRef": "${FLAVOR_NAME}"
  }
}
EOF
)

CREATE_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
  "${NOVA_URL}/v2.1/${PROJECT_ID}/servers" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${SERVER_CREATE_JSON}")

HTTP_CODE=$(echo "${CREATE_RESPONSE}" | grep "HTTP_CODE:" | cut -d: -f2)
CREATE_BODY=$(echo "${CREATE_RESPONSE}" | sed '/HTTP_CODE:/d')

echo "   HTTP Status: ${HTTP_CODE}"
echo "   Response: ${CREATE_BODY}"
echo ""

# Verify that creation was denied
if [ "${HTTP_CODE}" == "403" ]; then
  echo "   ✅ Creation correctly denied with 403 Forbidden"
  echo "   ✅ Test passed: Keycloak OAuth2 cannot create instances"
elif [ "${HTTP_CODE}" == "401" ]; then
  echo "   ⚠️  Unauthorized (401) - Authentication issue"
  echo "   This might indicate a configuration problem"
  exit 1
elif [ "${HTTP_CODE}" == "201" ] || [ "${HTTP_CODE}" == "202" ]; then
  echo "   ❌ Test failed: Instance creation was allowed (HTTP ${HTTP_CODE})"
  echo "   This should not be possible with Keycloak OAuth2"
  
  # Try to get instance ID and delete it
  INSTANCE_ID=$(echo "${CREATE_BODY}" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('server', {}).get('id', ''))" 2>/dev/null || echo "")
  if [ -n "${INSTANCE_ID}" ]; then
    echo "   🧹 Cleaning up: Deleting instance ${INSTANCE_ID}..."
    openstack server delete "${INSTANCE_ID}" 2>&1 || true
  fi
  
  exit 1
else
  echo "   ⚠️  Unexpected response (HTTP ${HTTP_CODE})"
  echo "   Expected: 403 Forbidden"
  echo "   This might indicate a configuration issue"
  exit 1
fi

echo ""
echo "✅ Test passed: Keycloak OAuth2 correctly prevents instance creation"
echo ""
echo "📋 Summary:"
echo "   ✅ OAuth2 token obtained successfully"
echo "   ✅ Instance creation denied (HTTP 403)"
echo "   ✅ Security policy enforced correctly"
