#!/bin/bash
# Test: Reboot a Nova instance using Keycloak OAuth2 authentication (demo user)
# This test verifies that the demo user can reboot instances using Keycloak OAuth2

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=== Test: Reboot Instance with Keycloak OAuth2 (demo) ==="
echo ""

# Check if instance ID exists from previous test
if [ -f /tmp/nova-test-instance-id.txt ]; then
  INSTANCE_ID=$(cat /tmp/nova-test-instance-id.txt)
  INSTANCE_NAME=$(cat /tmp/nova-test-instance-name.txt 2>/dev/null || echo "unknown")
  echo "✅ Found existing instance from previous test"
  echo "   Instance ID: ${INSTANCE_ID}"
  echo "   Instance Name: ${INSTANCE_NAME}"
else
  echo "❌ No instance ID found. Please run test-create-instance-keystone.sh first"
  exit 1
fi

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

# Verify instance exists and get current status
echo "2. Verifying instance status..."
INSTANCE_STATUS=$(openstack server show "${INSTANCE_ID}" -c status -f value 2>&1)
if [ -z "${INSTANCE_STATUS}" ]; then
  echo "   ❌ Instance not found"
  exit 1
fi
echo "   ✅ Instance found"
echo "   Current status: ${INSTANCE_STATUS}"
echo ""

# Reboot instance using OAuth2 token
echo "3. Rebooting instance with OAuth2 token..."
REBOOT_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
  "${NOVA_URL}/v2.1/${PROJECT_ID}/servers/${INSTANCE_ID}/action" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"reboot": {"type": "SOFT"}}')

HTTP_CODE=$(echo "${REBOOT_RESPONSE}" | grep "HTTP_CODE:" | cut -d: -f2)
REBOOT_BODY=$(echo "${REBOOT_RESPONSE}" | sed '/HTTP_CODE:/d')

if [ "${HTTP_CODE}" == "202" ] || [ "${HTTP_CODE}" == "204" ]; then
  echo "   ✅ Reboot request accepted (HTTP ${HTTP_CODE})"
elif [ "${HTTP_CODE}" == "401" ]; then
  echo "   ❌ Unauthorized (HTTP 401)"
  echo "   Response: ${REBOOT_BODY}"
  exit 1
elif [ "${HTTP_CODE}" == "403" ]; then
  echo "   ❌ Forbidden (HTTP 403) - User may not have reboot permission"
  echo "   Response: ${REBOOT_BODY}"
  exit 1
else
  echo "   ⚠️  Unexpected response (HTTP ${HTTP_CODE})"
  echo "   Response: ${REBOOT_BODY}"
fi
echo ""

# Wait for instance to be active again
echo "4. Waiting for instance to be active after reboot..."
MAX_WAIT=120
WAIT_TIME=0
while [ ${WAIT_TIME} -lt ${MAX_WAIT} ]; do
  STATUS=$(openstack server show "${INSTANCE_ID}" -c status -f value 2>&1)
  if [ "${STATUS}" == "ACTIVE" ]; then
    echo "   ✅ Instance is ACTIVE again"
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
echo "✅ Test passed: Instance rebooted successfully with Keycloak OAuth2"
echo ""
echo "📋 Final instance status:"
echo "   ID: ${INSTANCE_ID}"
echo "   Name: ${INSTANCE_NAME}"
echo "   Status: ${STATUS}"
