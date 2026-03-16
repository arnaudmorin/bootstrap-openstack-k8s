#!/bin/bash
# Script to run all Keycloak tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=========================================="
echo "  Keycloak Tests - Full Execution"
echo "=========================================="
echo ""

# List of tests to run in order
TESTS=(
  "test-cli-installation.sh"
  "test-cli-connection.sh"
  "test-realm-openstack.sh"
)

PASSED=0
FAILED=0

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
