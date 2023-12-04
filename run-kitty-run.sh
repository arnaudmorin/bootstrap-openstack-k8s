#!/bin/bash

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


k8s_ip=$(openstack server show k8s-1 -c addresses -f json | jq -r '.addresses["Ext-Net"][]' | grep -v 2001)


t "Working on k8s-1 (${k8s_ip})"

if [ ! -e done-k8s-1 ] ; then

$s $k8s_ip << 'EOF'
# Install k3s
curl -sfL https://get.k3s.io | sh -
kubectl get all

# Install frep
curl -fSL https://github.com/subchen/frep/releases/download/v1.3.12/frep-1.3.12-linux-amd64 -o /usr/local/bin/frep
chmod +x /usr/local/bin/frep

# Install ansible and git
apt-get install -y ansible git

# Clone bootstrap
git clone -b 2023.2 https://github.com/arnaudmorin/bootstrap-openstack-k8s.git
cd bootstrap-openstack-k8s
cp config/config.yaml.sample config/config.yaml
ip=$(hostname -I | awk '{print $1}')
sed -i -r "s/somewhere.net/${ip}.xip.opensteak.fr/" config/config.yaml

# Mysql
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=keystone | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=nova | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=placement | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=neutron | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=glance | kubectl apply -f -
kubectl wait --for=condition=available --timeout=60s deployment/mysql-keystone
kubectl wait --for=condition=available --timeout=60s deployment/mysql-nova
kubectl wait --for=condition=available --timeout=60s deployment/mysql-placement
kubectl wait --for=condition=available --timeout=60s deployment/mysql-neutron
kubectl wait --for=condition=available --timeout=60s deployment/mysql-glance

# Config
frep k8s/config.yaml.in:- --load config/config.yaml | kubectl apply -f -

# Populate
frep k8s/mysql-populate.yaml.in:- --load config/config.yaml | kubectl apply -f -
kubectl wait --for=condition=complete --timeout=60s job/keystone-init
kubectl wait --for=condition=complete --timeout=60s job/glance-init
kubectl wait --for=condition=complete --timeout=60s job/neutron-init
kubectl wait --for=condition=complete --timeout=60s job/nova-init
kubectl wait --for=condition=complete --timeout=60s job/placement-init

# Rabbit
frep k8s/rabbit.yaml.in:- --load config/config.yaml | kubectl apply -f -

# Keystone
frep k8s/keystone.yaml.in:- --load config/config.yaml | kubectl apply -f -
kubectl wait --for=condition=available --timeout=60s deployment/keystone

# Keystone bootstrap
ansible-playbook ansible/bootstrap-keystone.yaml

# Glance
frep k8s/glance.yaml.in:- --load config/config.yaml | kubectl apply -f -

# Placement
frep k8s/placement.yaml.in:- --load config/config.yaml | kubectl apply -f -

# Neutron
frep k8s/neutron.yaml.in:- --load config/config.yaml | kubectl apply -f -

# Nova
frep k8s/nova.yaml.in:- --load config/config.yaml | kubectl apply -f -

# Sleep few secs
sleep 30

# Source helper functions
source /root/helper

# Following actions are done as admin
source /root/openrc_admin
create_flavors
create_image_cirros
create_image_debian
# Before running this one, adjust the parameters with your network settings
# If you need to buy an IPFO block, check the tool in order-ipfo/ folder
#create_network_public 51.91.90.0/25 51.91.90.126

EOF

touch done-k8s-1

else
    echo "Nothing to do, already done"
fi

t "DONE k8s-1 (${k8s_ip})"









c_ip=$(openstack server show compute-1 -c addresses -f json | jq -r '.addresses["Ext-Net-Baremetal"][]' | grep -v 2001)

t "Working on compute-1 (${c_ip})"


if [ ! -e done-compute-1 ] ; then
$s $c_ip << EOF

apt-get install -y git ansible
git clone -b 2023.2 https://github.com/arnaudmorin/bootstrap-openstack-k8s.git
cd bootstrap-openstack-k8s

cp config/config.yaml.sample config/config.yaml
sed -i -r "s/somewhere.net/${k8s_ip}.xip.opensteak.fr/" config/config.yaml

ansible-playbook ansible/bootstrap-compute.yaml


EOF

touch done-compute-1

else
    echo "Nothing to do, already done"
fi

t "DONE compute-1 (${c_ip})"








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


