#!/bin/bash

# Install k3s
curl -sfL https://get.k3s.io | sh -
kubectl get all

# Enable kubectl completion
kubectl completion bash > /etc/bash_completion.d/kubectl
echo 'complete -F __start_kubectl k' > /etc/profile.d/k.sh

# Install frep
curl -fSL https://github.com/subchen/frep/releases/download/v1.3.12/frep-1.3.12-linux-amd64 -o /usr/local/bin/frep
chmod +x /usr/local/bin/frep

apt-get update

# Install ansible and git
apt-get install -y ansible git

# Clone bootstrap
git clone -b 2024.2 https://github.com/arnaudmorin/bootstrap-openstack-k8s.git
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
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=skyline | kubectl apply -f -
kubectl wait --for=condition=available --timeout=60s deployment/mysql-keystone
kubectl wait --for=condition=available --timeout=60s deployment/mysql-nova
kubectl wait --for=condition=available --timeout=60s deployment/mysql-placement
kubectl wait --for=condition=available --timeout=60s deployment/mysql-neutron
kubectl wait --for=condition=available --timeout=60s deployment/mysql-glance
kubectl wait --for=condition=available --timeout=60s deployment/mysql-skyline

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

# Skyline
frep k8s/skyline.yaml.in:- --load config/config.yaml | kubectl apply -f -

# Sleep few secs
sleep 30

# Install k9s
curl -sS https://webi.sh/k9s | sh

# Source helper functions
source /root/helper

# Following actions are done as admin
source /root/openrc_admin
create_flavors
create_image_cirros
create_image_debian
# Before running this one, adjust the parameters with your network settings
# If you need to buy an IPFO block, check the tool in order-ipfo/ folder
#create_network_public 51.91.90.2 51.91.90.126

