#!/bin/bash

todelete=""

IFS=$'\n'
for line in $(openstack server list -f value -c ID -c Name) ; do
    id=$(echo $line | awk '{ print $1}')
    name=$(echo $line | awk '{ print $2}')

    if [[ "$name" =~ k8s|compute ]]; then
        echo "Deleting $name"
        todelete="$todelete $id"
    fi
done

eval "openstack server delete $todelete"
