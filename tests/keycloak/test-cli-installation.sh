#!/bin/bash
# Test Keycloak CLI installation
# Verifies that binaries are installed and accessible

set -e

echo "=== Keycloak CLI Installation Test ==="
echo ""

# Check that Keycloak is downloaded
KEYCLOAK_VERSION=26.0.0
KEYCLOAK_DIR="/root/keycloak-${KEYCLOAK_VERSION}"

if [ ! -d "${KEYCLOAK_DIR}" ]; then
  echo "❌ Keycloak ${KEYCLOAK_VERSION} is not installed in ${KEYCLOAK_DIR}"
  exit 1
fi

echo "✅ Keycloak ${KEYCLOAK_VERSION} is installed"

# Check that binaries exist
if [ ! -f "${KEYCLOAK_DIR}/bin/kcreg.sh" ]; then
  echo "❌ kcreg.sh not found"
  exit 1
fi

if [ ! -f "${KEYCLOAK_DIR}/bin/kcadm.sh" ]; then
  echo "❌ kcadm.sh not found"
  exit 1
fi

echo "✅ kcreg.sh and kcadm.sh binaries present"

# Check that PATH is configured
if ! grep -q "keycloak-${KEYCLOAK_VERSION}/bin" /etc/profile.d/keycloak.sh 2>/dev/null; then
  echo "⚠️  Keycloak PATH not configured in /etc/profile.d/keycloak.sh"
else
  echo "✅ PATH configured in /etc/profile.d/keycloak.sh"
fi

# Load PATH
source /etc/profile.d/keycloak.sh 2>/dev/null || true

# Check that commands are in PATH
if ! command -v kcreg.sh &> /dev/null; then
  echo "⚠️  kcreg.sh is not in PATH"
else
  echo "✅ kcreg.sh is in PATH: $(which kcreg.sh)"
fi

if ! command -v kcadm.sh &> /dev/null; then
  echo "⚠️  kcadm.sh is not in PATH"
else
  echo "✅ kcadm.sh is in PATH: $(which kcadm.sh)"
fi

echo ""
echo "✅ Installation validated successfully"
