#!/bin/bash

apt-get update
apt-get install -y git ansible
git clone -b 2024.2 https://github.com/arnaudmorin/bootstrap-openstack-k8s.git
cd bootstrap-openstack-k8s

cp config/config.yaml.sample config/config.yaml
sed -i -r "s/somewhere.net/${k8s_ip}.xip.opensteak.fr/" config/config.yaml

ansible-playbook ansible/bootstrap-compute.yaml

