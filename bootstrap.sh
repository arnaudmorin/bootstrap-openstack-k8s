#!/bin/bash

###
# Fonction
###

display_help() {
    echo "Usage: $0 [options...]"
    echo "Options:"
    echo "  --deploiment-prefix <value>   Choose a prefix to have capacity to deploy multiple openstack on the same region and project. default is a random uuidgen."
    echo "  --help                        Print this helper message."
    exit 0
}

# Init params
declare -A params

# Check param
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --help)
            display_help
            ;;
        *)
        if [[ $# -gt 1 ]]; then
            # check if the next param is a value
            if [[ "$2" != -* ]]; then
                value="$2"
                shift
            elif [[ -n "$2" ]]; then
                display_help
            fi
        fi
        params["$key"]="$value"
        ;;
    esac
    shift
done

get_value() {
    local key="$1"
    local default_value="$2"
    if [[ -n "${params[$key]+1}" && -n "${params[$key]}" ]]; then
        echo "${params[$key]}"
    else
        echo "$default_value"
    fi
}

function create_keypair(){(
    openstack keypair show zob 2>&1 >/dev/null
    if [ $? -eq 1 ] ; then
        openstack keypair create --public-key ansible/files/zob.pub zob
    fi
)}

function create_networks(){(
    networks=$(openstack network list -c Name -f value)
    echo $networks | grep -q 'public' || {
        openstack network create public --disable-port-security --provider-network-type=vrack --provider-segment=0
        openstack subnet create --no-dhcp --gateway none --subnet-range 192.168.1.0/24 --network public --dns-nameserver 0.0.0.0 192.168.1.0/24
    }
)}

function boot(){(
    SMALL_UUID=$1
    NAME=$2
    FLAVOR=$3
    PUBLIC_NET=$4

    FULLNAME="$1-$2"

    echo ""
    echo "Booting $FULLNAME ..."

    [[ $FLAVOR == bm-* ]] && EXTNET="Ext-Net-Baremetal" || EXTNET="Ext-Net"
    [[ $FLAVOR == bm-* ]] && IMAGE="Baremetal - Debian 12" || IMAGE="Debian 12"
    [ -n "$PUBLIC_NET" ] && EXTRA="--net $PUBLIC_NET"

    # Checking if instances does not already exists
    ID=$(openstack server list --name $FULLNAME -f value -c ID)

    if [ -z "$ID" ] ; then
        openstack server create \
            --key-name zob \
            --net $EXTNET $EXTRA \
            --image "$IMAGE" \
            --flavor $FLAVOR \
            --user-data userdata/${NAME/-[0-9]*/} \
            $FULLNAME
    else
        echo "$FULLNAME already exists with ID $ID, nothing to do."
    fi
)}

function t
{
    local string="$1"
    local stringw=$((77 - $(wc -L <<< "$string")))
    echo ""
    echo "┌──────────────────────────────────────────────────────────────────────────────┐"
    echo -n "│ $string"
    for i in $(seq 1 ${stringw}); do echo -n " " ; done
    echo "│"
    echo "└──────────────────────────────────────────────────────────────────────────────┘"
    date -R
    echo ""
}

deploiment_prefix=$(get_value "--deploiment-prefix" "$(openssl rand -hex 4)")

t "Your deploiment-prefix: $deploiment_prefix"

create_keypair
create_networks
boot $deploiment_prefix k8s-1 r3-64
#boot k8s-2
#boot k8s-3
boot $deploiment_prefix compute-1 r3-64 public
boot $deploiment_prefix compute-2 r3-64 public
#boot compute-3 bm-l1 public
#boot compute-4 bm-l1 public
#boot compute-5 public
boot $deploiment_prefix network-1 r3-64 public
boot $deploiment_prefix network-2 r3-64 public
