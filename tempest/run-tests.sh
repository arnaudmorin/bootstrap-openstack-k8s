#!/bin/bash
# Run Tempest against this OpenStack deployment, from k8s-0.
#
#
# Usage:
#   bash tempest/run-tests.sh                                     # smoke tests (default)
#   bash tempest/run-tests.sh --regex tempest.api.compute
#   bash tempest/run-tests.sh --regex tempest.api.identity.v3
#   bash tempest/run-tests.sh --recreate                          # rebuild the workspace + tempest.conf first
set -e

VENV=/opt/tempest
WS=/root/tempest-workspace

function title.print
{
    local string="$1"
    local stringw=$((77 - $(wc -L <<< "$string")))
    echo ""
    echo "|------------------------------------------------------------------------------|"
    echo -n "| $string"
    for i in $(seq 1 ${stringw}); do echo -n " " ; done
    echo "|"
    echo "|------------------------------------------------------------------------------|"
    echo ""
}

# Parse our own flags, then forward whatever is left to 'tempest run'.
# --recreate|-r : wipe and regenerate the workspace (and tempest.conf)
RECREATE=0
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --recreate|-r) RECREATE=1 ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]}"

# venv
if [ ! -x "$VENV/bin/tempest" ]; then
    title.print "Creating venv (${VENV})"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --upgrade pip
    "$VENV/bin/pip" install tempest python-tempestconf neutron-tempest-plugin mistral-tempest-tests
    ln -sf "$VENV/bin/tempest" /usr/local/bin/tempest
fi

# workspace (rebuilt when missing, or when --recreate was passed)
if [ "$RECREATE" = "1" ] || [ ! -f "$WS/etc/tempest.conf" ]; then
    title.print "Creating workspace (${WS})"
    rm -rf "$WS"
    rm -rf /root/.tempest/
    "$VENV/bin/tempest" init "$WS"

    # generate tempest.conf by discovering the running cloud as admin.
    title.print "Generating tempest.conf"
    source /root/openrc_admin
    cd "$WS"
    "$VENV/bin/discover-tempest-config" \
        --create \
        --out etc/tempest.conf
fi

# Run the tests (defaults to --smoke if no args are given)
title.print "Run tempest (workspace in ${WS}"
"$VENV/bin/tempest" run "${@:---smoke}"
