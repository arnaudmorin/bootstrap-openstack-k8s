#!/bin/bash

# Clean a project, from k8s-1
function echo_green(){
    m=$1
    echo -e "\033[0;32m${1}\033[0m"
}

function delete_servers(){
    k=$(openstack server list -f value -c ID)
    [ ! -z "$k" ] && openstack server delete $k
}

function delete_keypairs(){
    k=$(openstack keypair list -f value -c Name)
    [ ! -z "$k" ] && openstack keypair delete $k
}

function delete_secgroups(){
    k=$(openstack security group rule list -c ID -f value)
    [ ! -z "$k" ] && openstack security group rule delete $k
}

function create_secgroups(){
    openstack security group rule create --egress default >/dev/null
}

function delete_fips(){
    k=$(openstack floating ip list -c ID -f value)
    [ ! -z "$k" ] && openstack floating ip delete $k
}

function delete_routers(){
    for router in $(openstack router list -c ID -f value); do
        for subnet in $(openstack router show -c interfaces_info $router -f json | jq -r ".interfaces_info[].subnet_id" | uniq) ; do
            openstack router remove subnet $router $subnet
        done
        openstack router delete $router
    done
}

function delete_networks(){
    k=$(openstack network list --internal -f value -c ID)
    [ ! -z "$k" ] && openstack network delete $k
}

function delete_all(){
    openstack 
}

echo -n 'Deleting servers... '
delete_servers
echo_green "DONE"
echo -n 'Deleting keypairs... '
delete_keypairs
echo_green "DONE"
echo -n 'Deleting secgroups... '
delete_secgroups
echo_green "DONE"
echo -n 'Creating default secgroups... '
create_secgroups
echo_green "DONE"
echo -n 'Deleting fips... '
delete_fips
echo_green "DONE"
echo -n 'Deleting routers... '
delete_routers
echo_green "DONE"
echo -n 'Deleting networks... '
delete_networks
echo_green "DONE"
