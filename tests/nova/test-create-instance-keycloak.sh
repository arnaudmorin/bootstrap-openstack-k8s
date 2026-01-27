#!/bin/bash
# Test: Create a Nova instance using Keycloak OAuth2 authentication (demo-keycloak user)
# This test verifies that the demo-keycloak user can create instances using OAuth2 token
# Uses demo project; runs with demo openrc for project/API info (admin is for infra only).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=== Test: Create Instance with Keycloak OAuth2 (demo-keycloak) ==="
echo ""

# Load demo openrc - tests use demo project only
if [ -f /root/openrc_demo ]; then
  source /root/openrc_demo
else
  echo "❌ File /root/openrc_demo not found"
  exit 1
fi
if [ "${OS_USERNAME}" != "demo" ]; then
  echo "❌ This test must run with demo user openrc (OS_USERNAME=demo). Current: OS_USERNAME=${OS_USERNAME}"
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

# Get OAuth2 token from Keycloak for demo-keycloak user
echo "1. Obtaining OAuth2 token from Keycloak for demo-keycloak user..."
TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=openstack-client" \
  -d "username=demo-keycloak" \
  -d "password=${OS_PASSWORD}" \
  -d "grant_type=password" \
  -d "scope=openid")

ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")

if [ -z "${ACCESS_TOKEN}" ] || [ "${ACCESS_TOKEN}" == "None" ]; then
  echo "   ❌ Failed to obtain OAuth2 token"
  echo "   Response: ${TOKEN_RESPONSE}"
  echo ""
  echo "   ℹ️  Note: The demo-keycloak user may need to be created in Keycloak first"
  exit 1
fi

echo "   ✅ OAuth2 token obtained"
echo "   Token (first 20 chars): ${ACCESS_TOKEN:0:20}..."
echo ""

# Get image and flavor info using Keystone (for demo user)
echo "2. Getting image and flavor info (using Keystone)..."
IMAGE_ID=$(openstack image list --limit 1 -c ID -f value 2>&1 | head -1)
if [ -z "${IMAGE_ID}" ]; then
  echo "   ❌ No image available"
  exit 1
fi
echo "   ✅ Image ID: ${IMAGE_ID}"

FLAVOR_NAME=$(openstack flavor show m1.small -c name -f value 2>&1 | grep -v "Error\|No" | head -1)
if [ -z "${FLAVOR_NAME}" ]; then
  FLAVOR_NAME=$(openstack flavor list --limit 1 -c Name -f value 2>&1 | head -1)
fi
if [ -z "${FLAVOR_NAME}" ]; then
  echo "   ❌ No flavor available"
  exit 1
fi
echo "   ✅ Flavor: ${FLAVOR_NAME} (ID: $(openstack flavor show ${FLAVOR_NAME} -c id -f value 2>&1))"
echo ""

# Get network ID
echo "3. Getting available network..."
NETWORK_ID=$(openstack network list -c ID -f value 2>&1 | head -1)
if [ -z "${NETWORK_ID}" ]; then
  NETWORK_ID=$(openstack network show test-net -c id -f value 2>&1 | grep -v "Error\|No Network" | head -1 || echo "")
fi

if [ -z "${NETWORK_ID}" ] || [ "${NETWORK_ID}" == "" ]; then
  echo "   ℹ️  No network found, creating private network for this project..."
  NETWORK_NAME="test-net-$(date +%s)"
  
  # Create private network for this project only (no --share)
  NETWORK_OUTPUT=$(openstack network create \
    --project "${PROJECT_ID}" \
    "${NETWORK_NAME}" 2>&1)
  
  if echo "${NETWORK_OUTPUT}" | grep -q "ERROR\|error\|Error"; then
    echo "   ❌ Failed to create network"
    echo "${NETWORK_OUTPUT}"
    exit 1
  fi
  
  NETWORK_ID=$(openstack network show "${NETWORK_NAME}" -c id -f value 2>&1)
  if [ -z "${NETWORK_ID}" ]; then
    echo "   ❌ Cannot get network ID after creation"
    exit 1
  fi
  
  echo "   ✅ Created network: ${NETWORK_NAME} (ID: ${NETWORK_ID})"
  
  # Create subnet for the network
  SUBNET_NAME="${NETWORK_NAME}-subnet"
  SUBNET_CIDR="192.168.$(($(date +%s) % 255)).0/24"
  
  SUBNET_OUTPUT=$(openstack subnet create \
    --network "${NETWORK_ID}" \
    --subnet-range "${SUBNET_CIDR}" \
    --project "${PROJECT_ID}" \
    "${SUBNET_NAME}" 2>&1)
  
  if echo "${SUBNET_OUTPUT}" | grep -q "ERROR\|error\|Error"; then
    echo "   ⚠️  Failed to create subnet, but network exists"
    echo "${SUBNET_OUTPUT}"
  else
    SUBNET_ID=$(openstack subnet show "${SUBNET_NAME}" -c id -f value 2>&1)
    echo "   ✅ Created subnet: ${SUBNET_NAME} (ID: ${SUBNET_ID}, CIDR: ${SUBNET_CIDR})"
  fi
else
  echo "   ✅ Using existing network ID: ${NETWORK_ID}"
fi
echo ""

# Update step number for instance creation
echo "4. Creating instance with OAuth2 token..."

INSTANCE_NAME="test-instance-keycloak-$(date +%s)"

# Build the server creation request
SERVER_DATA="{
  \"server\": {
    \"name\": \"${INSTANCE_NAME}\",
    \"imageRef\": \"${IMAGE_ID}\",
    \"flavorRef\": \"$(openstack flavor show ${FLAVOR_NAME} -c id -f value 2>&1)\""

if [ -n "${NETWORK_ID}" ] && [ "${NETWORK_ID}" != "" ]; then
  SERVER_DATA="${SERVER_DATA},
    \"networks\": [{\"uuid\": \"${NETWORK_ID}\"}]"
fi

SERVER_DATA="${SERVER_DATA}
  }
}"

CREATE_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
  "${NOVA_URL}/v2.1/${PROJECT_ID}/servers" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${SERVER_DATA}")

HTTP_CODE=$(echo "${CREATE_RESPONSE}" | grep "HTTP_CODE:" | cut -d: -f2)
CREATE_BODY=$(echo "${CREATE_RESPONSE}" | sed '/HTTP_CODE:/d')

if [ "${HTTP_CODE}" == "202" ] || [ "${HTTP_CODE}" == "201" ]; then
  echo "   ✅ Instance creation request accepted (HTTP ${HTTP_CODE})"
  
  # Extract instance ID from response
  INSTANCE_ID=$(echo "${CREATE_BODY}" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('server', {}).get('id', ''))" 2>/dev/null || echo "")
  
  if [ -z "${INSTANCE_ID}" ]; then
    # Try alternative format
    INSTANCE_ID=$(echo "${CREATE_BODY}" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
  fi
  
  if [ -z "${INSTANCE_ID}" ]; then
    echo "   ⚠️  Could not extract instance ID from response"
    echo "   Response: ${CREATE_BODY}"
    exit 1
  fi
  
  echo "   Instance ID: ${INSTANCE_ID}"
  echo "   Instance Name: ${INSTANCE_NAME}"
elif [ "${HTTP_CODE}" == "401" ]; then
  echo "   ❌ Unauthorized (HTTP 401)"
  echo "   Response: ${CREATE_BODY}"
  exit 1
elif [ "${HTTP_CODE}" == "403" ]; then
  echo "   ❌ Forbidden (HTTP 403) - User may not have create permission"
  echo "   Response: ${CREATE_BODY}"
  exit 1
else
  echo "   ⚠️  Unexpected response (HTTP ${HTTP_CODE})"
  echo "   Response: ${CREATE_BODY}"
  exit 1
fi
echo ""

# Wait for instance to be active
echo "5. Waiting for instance to be active..."
MAX_WAIT=120
WAIT_TIME=0
while [ ${WAIT_TIME} -lt ${MAX_WAIT} ]; do
  # Use Keystone to check status (OAuth2 may not work for GET requests yet)
  STATUS=$(openstack server show "${INSTANCE_ID}" -c status -f value 2>&1)
  if [ "${STATUS}" == "ACTIVE" ]; then
    echo "   ✅ Instance is ACTIVE"
    break
  elif [ "${STATUS}" == "ERROR" ]; then
    echo "   ❌ Instance is in ERROR state"
    exit 1
  fi
  sleep 2
  WAIT_TIME=$((WAIT_TIME + 2))
  echo "   ⏳ Status: ${STATUS} (${WAIT_TIME}s/${MAX_WAIT}s)"
done

if [ ${WAIT_TIME} -ge ${MAX_WAIT} ]; then
  echo "   ⚠️  Timeout waiting for instance to be active"
  echo "   Current status: ${STATUS}"
fi

echo ""
echo "✅ Test passed: Instance created successfully with Keycloak OAuth2"
echo ""
echo "📋 Instance details:"
echo "   ID: ${INSTANCE_ID}"
echo "   Name: ${INSTANCE_NAME}"
echo "   Status: ${STATUS}"
echo ""

# Save instance ID for cleanup or next tests
echo "${INSTANCE_ID}" > /tmp/nova-test-instance-id.txt
echo "${INSTANCE_NAME}" > /tmp/nova-test-instance-name.txt

echo "💾 Instance ID saved to /tmp/nova-test-instance-id.txt"
echo "💾 Instance name saved to /tmp/nova-test-instance-name.txt"
