#!/bin/bash
# Test: Create a Nova instance using Keystone authentication (demo user)
# This test verifies that the demo user can create instances using Keystone

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "=== Test: Create Instance with Keystone (demo) ==="
echo ""

# Load demo openrc
if [ -f /root/openrc_demo ]; then
  source /root/openrc_demo
else
  echo "❌ File /root/openrc_demo not found"
  exit 1
fi

echo "✅ Loaded demo openrc"
echo "   OS_USERNAME=${OS_USERNAME}"
echo "   OS_PROJECT_NAME=${OS_PROJECT_NAME}"
echo "   OS_AUTH_URL=${OS_AUTH_URL}"
echo ""

# Get project ID
PROJECT_ID=$(openstack project show "${OS_PROJECT_NAME}" -c id -f value 2>&1)
if [ -z "${PROJECT_ID}" ]; then
  echo "❌ Cannot get project ID for ${OS_PROJECT_NAME}"
  exit 1
fi
echo "✅ Project ID: ${PROJECT_ID}"
echo ""

# Get available image
echo "1. Getting available image..."
IMAGE_ID=$(openstack image list --limit 1 -c ID -f value 2>&1 | head -1)
if [ -z "${IMAGE_ID}" ]; then
  echo "❌ No image available"
  exit 1
fi
echo "   ✅ Image ID: ${IMAGE_ID}"
echo ""

# Get available flavor (prefer m1.small if available, otherwise any flavor)
echo "2. Getting available flavor..."
FLAVOR_NAME=$(openstack flavor show m1.small -c name -f value 2>&1 | grep -v "Error\|No" | head -1)
if [ -z "${FLAVOR_NAME}" ]; then
  FLAVOR_NAME=$(openstack flavor list --limit 1 -c Name -f value 2>&1 | head -1)
fi
if [ -z "${FLAVOR_NAME}" ]; then
  echo "❌ No flavor available"
  exit 1
fi
echo "   ✅ Flavor: ${FLAVOR_NAME}"
echo ""

# Get network ID (try to find any available network)
echo "3. Getting available network..."
NETWORK_ID=$(openstack network list -c ID -f value 2>&1 | head -1)
if [ -z "${NETWORK_ID}" ]; then
  # Try to get specific networks (may fail if not accessible to demo user)
  NETWORK_ID=$(openstack network show lb-mgmt-net -c id -f value 2>&1 | grep -v "Error\|No Network" | head -1 || \
               openstack network show public -c id -f value 2>&1 | grep -v "Error\|No Network" | head -1 || \
               openstack network show default -c id -f value 2>&1 | grep -v "Error\|No Network" | head -1 || echo "")
fi

if [ -n "${NETWORK_ID}" ] && [ "${NETWORK_ID}" != "" ]; then
  echo "   ✅ Network ID: ${NETWORK_ID}"
else
  echo "   ℹ️  No network specified (will use auto-assign)"
  NETWORK_ID=""
fi
echo ""

# Create instance
echo "4. Creating Nova instance..."
INSTANCE_NAME="test-instance-keystone-$(date +%s)"
if [ -n "${NETWORK_ID}" ] && [ "${NETWORK_ID}" != "" ]; then
  INSTANCE_OUTPUT=$(openstack server create \
    --image "${IMAGE_ID}" \
    --flavor "${FLAVOR_NAME}" \
    --network "${NETWORK_ID}" \
    "${INSTANCE_NAME}" 2>&1)
else
  # Create without network (Nova will auto-assign if possible)
  INSTANCE_OUTPUT=$(openstack server create \
    --image "${IMAGE_ID}" \
    --flavor "${FLAVOR_NAME}" \
    "${INSTANCE_NAME}" 2>&1)
fi

if echo "${INSTANCE_OUTPUT}" | grep -q "ERROR\|error\|Error"; then
  echo "   ❌ Failed to create instance"
  echo "${INSTANCE_OUTPUT}"
  exit 1
fi

# Get instance ID
INSTANCE_ID=$(openstack server show "${INSTANCE_NAME}" -c id -f value 2>&1)
if [ -z "${INSTANCE_ID}" ]; then
  echo "   ❌ Cannot get instance ID"
  exit 1
fi

echo "   ✅ Instance created successfully"
echo "   Instance ID: ${INSTANCE_ID}"
echo "   Instance Name: ${INSTANCE_NAME}"
echo ""

# Wait for instance to be active
echo "5. Waiting for instance to be active..."
MAX_WAIT=120
WAIT_TIME=0
while [ ${WAIT_TIME} -lt ${MAX_WAIT} ]; do
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
echo "✅ Test passed: Instance created successfully with Keystone"
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
