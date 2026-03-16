#!/bin/bash
# Script to run all Nova tests
# Tests verify Keystone and Keycloak OAuth2 authentication with Nova API
#
# All tests MUST run as the demo user only. Admin user is for infra setup only.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Ensure we use demo user for the whole test run (cleanup, etc.)
if [ -f /root/openrc_demo ]; then
  source /root/openrc_demo
  if [ "${OS_USERNAME}" != "demo" ] || [ "${OS_PROJECT_NAME}" != "demo" ]; then
    echo "❌ openrc_demo must define demo user (OS_USERNAME=demo, OS_PROJECT_NAME=demo)"
    exit 1
  fi
else
  echo "❌ /root/openrc_demo not found. Tests require demo user credentials."
  exit 1
fi

echo "=========================================="
echo "  Nova API Tests - Full Execution (demo user)"
echo "=========================================="
echo "   OS_USERNAME=${OS_USERNAME}  OS_PROJECT_NAME=${OS_PROJECT_NAME}"
echo ""

# List of tests to run in order
TESTS=(
  "test-create-instance-keystone.sh"
  "test-create-instance-keycloak.sh"
  "test-reboot-instance-keycloak.sh"
  "test-keycloak-cannot-create.sh"
)

PASSED=0
FAILED=0

# Cleanup function
cleanup() {
  echo ""
  echo "🧹 Cleaning up test resources..."
  
  if [ -f /tmp/nova-test-instance-id.txt ]; then
    INSTANCE_ID=$(cat /tmp/nova-test-instance-id.txt)
    INSTANCE_NAME=$(cat /tmp/nova-test-instance-name.txt 2>/dev/null || echo "")
    
    if [ -n "${INSTANCE_ID}" ]; then
      echo "   Deleting test instance: ${INSTANCE_ID}"
      if [ -f /root/openrc_demo ]; then
        source /root/openrc_demo
        openstack server delete "${INSTANCE_ID}" 2>&1 || true
      fi
    fi
    
    rm -f /tmp/nova-test-instance-id.txt
    rm -f /tmp/nova-test-instance-name.txt
  fi
  
  echo "   ✅ Cleanup completed"
}

# Trap to cleanup on exit
trap cleanup EXIT

for test in "${TESTS[@]}"; do
  if [ ! -f "${test}" ]; then
    echo "⚠️  Test ${test} not found, ignored"
    continue
  fi

  echo "=== Running ${test} ==="
  if bash "${test}"; then
    echo "✅ ${test}: PASSED"
    PASSED=$((PASSED + 1))
  else
    echo "❌ ${test}: FAILED"
    FAILED=$((FAILED + 1))
    # Continue with other tests even if one fails
  fi
  echo ""
done

echo "=========================================="
echo "  Summary"
echo "=========================================="
echo "Tests passed: ${PASSED}"
echo "Tests failed: ${FAILED}"
echo "Total: $((PASSED + FAILED))"
echo ""

if [ ${FAILED} -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed"
  exit 1
fi
