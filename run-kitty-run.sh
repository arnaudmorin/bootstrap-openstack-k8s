#!/bin/bash

###
# Fonction
###

display_help() {
    echo "Usage: $0 [options...]"
    echo "Options:"
    echo "  --deploiment-prefix <value>   Choose a prefix to have capacity to deploy multiple openstack on the same region and project. default is a random uuidgen."
    echo "  --deploiment-type   <value>   Choose the type of deploiment you want, two types are availables: ovs (default) or ovn."
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

s='ssh -l root -i ansible/files/zob -oStrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null '

###
# Get data from input of script and openstack infra
###

deploiment_prefix=$(get_value "--deploiment-prefix" "$(openssl rand -hex 4)")
deploiment_type=$(get_value "--deploiment-type" "ovs")

if [[ "$deploiment_type" == "ovs" || "$deploiment_type" == "ovn" ]]; then
    t "You choose a deploiment-type: $deploiment_type with deploiment-prefix: $deploiment_prefix"
else
    t "You choose a deploiment-type: $deploiment_type not supported by this tool."
    display_help
fi

os_server_list=$(openstack server list -f json -c name -c networks --name "${deploiment_prefix}-*")

instance_list=$(echo "$os_server_list" | jq -r '.[] | {(.Name): .Networks["Ext-Net"][1]}' | jq -s 'add')

###
# Start deploy
###

k8s_name="${deploiment_prefix}-k8s-1"
k8s_ip=$(echo "$instance_list" | jq -r --arg key "$k8s_name" '.[$key]')

t " Working on: $k8s_name with IP: $k8s_ip"

if [ ! -e done-$name ] ; then
    $s $k8s_ip < ./postinstall/k8s.sh
    touch done-$name
else
    echo "Nothing to do, already done"
fi

t "DONE $k8s_name ($k8s_ip)"

echo "$instance_list" | jq -r 'to_entries[] | "\(.key) \(.value)"' | while read -r key value; do
    name=${key//${deploiment_prefix}-/}
    t " Working on: $name with IP: $value"

    if [ ! -e done-$name ] ; then
        if [[ "$name" =~ "k8s" ]]; then
            echo "Already done outside the loop"
        elif [[ "$name" =~ "compute" ]]; then
            $s $value < ./postinstall/compute.sh
        elif [[ "$name" =~ "network" ]]; then
            $s $value < ./postinstall/network.sh
        fi
        touch done-$name
    else
        echo "Nothing to do, already done"
    fi

    t "DONE $name ($value)"
done

t "Printing openrc files"

$s $k8s_ip << 'EOF'
echo ""
echo ""
echo ""
echo "---------"
echo "| ADMIN |"
echo "---------"
cat /root/openrc_admin

echo ""
echo ""
echo ""
echo "---------"
echo "| DEMO  |"
echo "---------"
cat /root/openrc_demo

echo ""
echo ""
echo ""
EOF

echo "----------"
echo "| WEB UI |"
echo "----------"

echo "http://skyline.${k8s_ip}.xip.opensteak.fr"
echo ""
echo ""
echo ""
