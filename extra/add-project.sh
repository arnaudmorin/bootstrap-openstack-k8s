#!/bin/bash

source /root/openrc_admin
source /opt/oscli/bin/activate

# Clean a project, from k8s-1
function echo_green(){
    m=$1
    echo -e "\033[0;32m${1}\033[0m"
}

function usage(){
    echo "bash add-project.sh project_name password"
    exit 1
}

if [ -z "$1" ] ; then
    echo "missing project_name"
    usage
fi

if [ -z "$2" ] ; then
    echo "missing password"
    usage
fi

echo_green "Creating project and user in keystone"

cat <<EOF > /tmp/add-project-keystone-$$
---
users_roles:
  default:
    $1:
      $1_user1:
        roles:
        - user
        - member
        password: $2
EOF
/root/bootstrap-openstack-k8s/keystone-bootstrap/keystone-bootstrap --settings /tmp/add-project-keystone-$$
rm /tmp/add-project-keystone-$$

echo_green "Creating /root/openrc_$1"
frep /root/bootstrap-openstack-k8s/files/openrc.in:/root/openrc_$1 --load /root/bootstrap-openstack-k8s/config/config.yaml -e openrc_user=$1_user1 -e openrc_project=$1 -e password=$2

if grep -q "^  $1:$" /root/.config/openstack/clouds.yaml; then
    echo_green "Cloud $1 already in /root/.config/openstack/clouds.yaml"
    exit 0
fi
echo_green "Adding cloud $1 to /root/.config/openstack/clouds.yaml"
DOMAIN=$(awk '/^domain:/ {print $2}' /root/bootstrap-openstack-k8s/config/config.yaml)
cat <<EOF >> /root/.config/openstack/clouds.yaml
  $1:
    auth:
      auth_url: http://keystone.${DOMAIN}/v3
      username: $1_user1
      password: "$2"
      project_name: $1
      user_domain_name: Default
      project_domain_name: Default
    region_name: RegionOne
    identity_api_version: 3
EOF
