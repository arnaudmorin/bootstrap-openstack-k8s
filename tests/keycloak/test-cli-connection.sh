#!/bin/bash
# Test Keycloak CLI connection
# Verifies that credentials are configured and connection works

set -e

echo "=== Keycloak CLI Connection Test ==="
echo ""

# Load configurations
source /etc/profile.d/keycloak.sh 2>/dev/null || true
source /root/keycloakrc 2>/dev/null || {
  echo "❌ File /root/keycloakrc not found"
  exit 1
}

echo "✅ keycloakrc file loaded"
echo "   KEYCLOAK_URL=${KEYCLOAK_URL}"
echo "   KEYCLOAK_USER=${KEYCLOAK_USER}"
echo "   KEYCLOAK_REALM=${KEYCLOAK_REALM}"
echo ""

# Test kcadm.sh - Configure credentials
echo "1. Test kcadm.sh (Admin CLI):"
if kcadm.sh config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm master \
  --user "${KEYCLOAK_USER}" \
  --password "${KEYCLOAK_PASSWORD}" 2>&1 | grep -q "Logging into"; then
  echo "   ✅ Connection to master realm: OK"
else
  echo "   ❌ Connection failed"
  exit 1
fi

# Test kcadm.sh - List realms
if kcadm.sh get realms 2>&1 | grep -q "openstack"; then
  echo "   ✅ List of realms: OK (openstack realm found)"
else
  echo "   ⚠️  openstack realm not found in list"
fi

echo ""

# Test kcreg.sh - Configure credentials
echo "2. Test kcreg.sh (Client Registration CLI):"
if kcreg.sh config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm master \
  --user "${KEYCLOAK_USER}" \
  --password "${KEYCLOAK_PASSWORD}" 2>&1 | grep -q "Logging into"; then
  echo "   ✅ Credentials configuration: OK"
else
  echo "   ❌ Configuration failed"
  exit 1
fi

echo ""
echo "✅ Connection validated successfully"
