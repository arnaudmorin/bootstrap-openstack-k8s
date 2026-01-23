#!/bin/bash
# Test access to openstack realm
# Verifies that we can access openstack realm resources

set -e

echo "=== Openstack Realm Access Test ==="
echo ""

# Load configurations
source /etc/profile.d/keycloak.sh 2>/dev/null || true
source /root/keycloakrc 2>/dev/null || {
  echo "❌ File /root/keycloakrc not found"
  exit 1
}

# Configure credentials for master realm (admin can manage all realms)
kcadm.sh config credentials \
  --server "${KEYCLOAK_URL}" \
  --realm master \
  --user "${KEYCLOAK_USER}" \
  --password "${KEYCLOAK_PASSWORD}" > /dev/null 2>&1

echo "1. Test openstack realm:"
REALM_INFO=$(kcadm.sh get realms/openstack 2>&1)
if echo "${REALM_INFO}" | grep -q '"realm" : "openstack"'; then
  echo "   ✅ openstack realm accessible"
  echo "${REALM_INFO}" | grep -E '"realm"|"enabled"' | head -2
else
  echo "   ❌ Cannot access openstack realm"
  echo "${REALM_INFO}"
  exit 1
fi

echo ""

echo "2. Test openstack realm clients:"
CLIENTS=$(kcadm.sh get clients --realm openstack 2>&1)
if echo "${CLIENTS}" | grep -q "nova-middleware\|openstack-client"; then
  echo "   ✅ Clients found in openstack realm"
  echo "${CLIENTS}" | grep -E '"clientId"' | head -5
else
  echo "   ⚠️  No clients found or access error"
  echo "${CLIENTS}" | head -5
fi

echo ""

echo "3. Test openstack realm users:"
USERS=$(kcadm.sh get users --realm openstack 2>&1)
if echo "${USERS}" | grep -q "nova-restart-user"; then
  echo "   ✅ nova-restart-user found"
  echo "${USERS}" | grep -E '"username"' | head -5
else
  echo "   ⚠️  nova-restart-user not found or access error"
  echo "${USERS}" | head -5
fi

echo ""

echo "4. Test openstack realm roles:"
ROLES=$(kcadm.sh get roles --realm openstack 2>&1)
if echo "${ROLES}" | grep -q "nova:reboot"; then
  echo "   ✅ nova:reboot role found"
  echo "${ROLES}" | grep -E '"name"' | head -5
else
  echo "   ⚠️  nova:reboot role not found or access error"
  echo "${ROLES}" | head -5
fi

echo ""
echo "✅ Openstack realm tests completed"
