#!/bin/bash
# Run Tempest against this OpenStack deployment, from k8s-0.
#
# Self-contained and idempotent: on first run it creates a /opt/tempest venv
# (same pattern as /opt/oscli), then auto-generates tempest.conf from the live
# cloud with python-tempestconf and runs the smoke suite.
#
# Usage:
#   bash tempest/run-tests.sh                       # smoke tests (default)
#   bash tempest/run-tests.sh --regex tempest.api.compute
#   bash tempest/run-tests.sh --regex tempest.api.identity.v3
set -e

VENV=/opt/tempest
WS=/root/tempest-workspace

# 1. venv (idempotent) -- mirrors the /opt/oscli setup in tofu/userdata/k8s.tftpl
if [ ! -x "$VENV/bin/tempest" ]; then
    echo "== installing tempest venv in $VENV (first run only)"
    apt-get install -y python3-venv
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --upgrade pip
    "$VENV/bin/pip" install tempest python-tempestconf neutron-tempest-plugin mistral-tempest-plugin
    ln -sf "$VENV/bin/tempest" /usr/local/bin/tempest
fi

# Ensure the tempest plugins are installed
"$VENV/bin/python" -c "import neutron_tempest_plugin" 2>/dev/null || \
    "$VENV/bin/pip" install neutron-tempest-plugin
"$VENV/bin/python" -c "import mistral_tempest_tests" 2>/dev/null || \
    "$VENV/bin/pip" install mistral-tempest-plugin

# 2. workspace (idempotent)
if [ ! -f "$WS/etc/tempest.conf" ]; then
    echo "== initialising tempest workspace in $WS"
    rm -rf "$WS"
    "$VENV/bin/tempest" init "$WS"
fi

# 3. (re)generate tempest.conf by discovering the running cloud as admin.
#    --create reuses existing flavors/network and uploads a cirros test image
#    (which also exercises the glance -> garage S3 backend).
#    cinder/designate have keystone endpoints but no pods, so disable them to
#    avoid smoke-test noise.
echo "== generating tempest.conf from the live cloud (openrc_admin)"
source /root/openrc_admin
cd "$WS"
"$VENV/bin/discover-tempest-config" \
    --create \
    --out etc/tempest.conf \
    identity.region RegionOne \
    service_available.cinder False \
    service_available.designate False

# 4. run the tests (defaults to --smoke if no args are given)
echo "== running: tempest run ${*:---smoke}"
"$VENV/bin/tempest" run "${@:---smoke}"
