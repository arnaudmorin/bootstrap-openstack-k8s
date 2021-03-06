Table of Contents
=================

* [Introduction](#introduction)
* [Bootstrap](#bootstrap)
  * [Clone the repo](#clone-the-repo)
  * [Source your openrc](#source-your-openrc)
  * [Start instances](#start-instances)
  * [SSH into instances](#ssh-into-instances)
* [k8s\-1](#k8s-1)
  * [Install k3s](#install-k3s)
  * [Install frep](#install-frep)
  * [Install ansible](#install-ansible)
  * [Install plik](#install-plik)
  * [Clone the repo (on k8s\-1)](#clone-the-repo-on-k8s-1)
* [Install OpenStack (control plane)](#install-openstack-control-plane)
  * [Configuration](#configuration)
  * [MariaDB](#mariadb)
  * [Rabbit](#rabbit)
  * [Keystone](#keystone)
  * [Glance](#glance)
  * [Placement](#placement)
  * [Neutron](#neutron)
  * [Nova](#nova)
  * [Test your OpenStack deployment](#test-your-openstack-deployment)
  * [In case of error \- debugging](#in-case-of-error---debugging)
* [compute\-1](#compute-1)
  * [Clone the repo (on compute\-1)](#clone-the-repo-on-compute-1)
  * [Copy the config file from k8s\-1](#copy-the-config-file-from-k8s-1)
  * [Run the play](#run-the-play)
* [Populate your OpenStack with default values](#populate-your-openstack-with-default-values)

# Introduction
TODO

# Bootstrap
## Clone the repo
```bash
git clone https://github.com/arnaudmorin/bootstrap-openstack-k8s.git
cd bootstrap-openstack-k8s
```

## Source your openrc
You need an OpenStack account to continue, source the `openrc` file now:
```bash
source openrc
```

## Start instances
The `bootstrap.sh` script will start 2 instances:
* k8s-1
* compute-1
```bash
# Execute this
./bootstrap.sh
```

```bash
# List instances you have to retrieve the IPs
openstack server list
```

## SSH into instances
At the end, you should be able to ssh both instances using the `zob` key:
```bash
chmod 600 ansible/files/zob
ssh debian@ip -i ansible/files/zob		# replace ip with the real server IP
```

# k8s-1
 On the k8s-1 instance, we will install k3s and few other tools to manage have a full `kubernetes` cluster.
 See https://k3s.io/ for more info.

## Install k3s
SSH into `k3s-1` and login as `root`, then:
```bash
curl -sfL https://get.k3s.io | sh -
```

### Check
Create an `alias` (this will help you saving your keyboard):
```
alias k='kubectl'
```

Test:
```
k get all
```


## Install frep
`frep` is a tool to generate files from templates. Its re-using the `go` templating language.
We will use `frep` to transform k8s templates into manifests.
I did not wanted to use `helm` for this because it's heavy and more difficult to understand.
`frep` is much more simpler.
```bash
curl -fSL https://github.com/subchen/frep/releases/download/v1.3.12/frep-1.3.12-linux-amd64 -o /usr/local/bin/frep
chmod +x /usr/local/bin/frep
```

More info here: https://github.com/subchen/frep

## Install ansible
We will need `ansible` at some point.
```bash
apt-get install -y ansible
```

## Install plik
`plik` is a tool to upload files to a remote URL.
It's useful to easily transfer files a from a system to another.

```bash
# nothing to do, it's already done by bootstrap.sh script :)
```

## Clone the repo (on k8s-1)
We will need some of the `kubernetes` templates that are in the repo:
```bash
apt-get install -y git
git clone https://github.com/arnaudmorin/bootstrap-openstack-k8s.git
cd bootstrap-openstack-k8s
```

# Install OpenStack (control plane)
We will use `kubectl` on `k8s-1` to install all `OpenStack` control plane (so `OpenStack` will run on top of `kubernetes`), including the `mariadb` and `rabbitmq`.

For steps where you create some `kubernetes` resources, take your time to check if the resources are well created, eventually slow down your copy paste rate :).
You can also check the result with:
```bash
k get all
```

## Configuration
### Prepare the config
Edit your config:
```bash
cp config/config.yaml.sample config/config.yaml
vim config/config.yaml
```

### Plik the config
You will need the `config.yaml` file on your compute, so `plik` it and copy the URL:
```bash
plik -s config/config.yaml
# Copy the URL, you will need it later
```

## MariaDB
### Install and create empty databases
```bash
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=keystone | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=nova | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=placement | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=neutron | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=glance | kubectl apply -f -
```
Databases for all `OpenStack` services are created (empty) during this step.

### Create all configmaps
```bash
frep k8s/config.yaml.in:- --load config/config.yaml | kubectl apply -f -
```
All config files for all services are created during this step.

### Populate databases
It's time now to sync (create structures / tables) all `OpenStack` services databases.

```bash
frep k8s/mysql-populate.yaml.in:- --load config/config.yaml | kubectl apply -f -
```
Databases for all `OpenStack` services are now populated with empty tables.

## Rabbit
```bash
frep k8s/rabbit.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

## Keystone
```bash
frep k8s/keystone.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

Keystone need also some bootstraping, which can be done using the following playbook.
Run the playbook only when keystone is ready (check with `k get all`)
```bash
ansible-playbook ansible/bootstrap-keystone.yaml
```
This will create the endpoints for all `OpenStack` services and also two users (`admin` and `demo`).
This will also install the `openstack` command line tool (openstack-client) and create two `openrc` file (one for each user). With this, you will then be able to manipulate your `OpenStack` cluster from `k8s-1` server.

## Glance
```bash
frep k8s/glance.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

## Placement
```bash
frep k8s/placement.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

## Neutron
```bash
frep k8s/neutron.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

## Nova
```bash
frep k8s/nova.yaml.in:- --load config/config.yaml | kubectl apply -f -
```
Nova will take longer than others, this is the more complex.

## Test your OpenStack deployment
### openrc_admin
When you executed the `bootstrap-keystone` playbook, you also installed an `openrc_admin` file to access your `OpenStack` cluster as an administrator.
Source this file:
```bash
source /root/openrc_admin
```

Now try each element of your `OpenStack`

### Keystone
```bash
openstack token issue
# This command is doing an API call against `keystone` and should give you something like:
+------------+---------------------------------------
| Field      | Value                                 
+------------+---------------------------------------
| expires    | 2021-11-05T21:35:40+0000              
| id         | gAAAAABhhZWc-f-TGVV2NNqN03KXLpgIDmBD2f
| project_id | 966629a3e2f34ad996d0ec8d57f6a1bd      
| user_id    | fd6a41322bdc4941ae74354697fcc2db      
+------------+---------------------------------------
```
If you have your token, it means `keystone` is good!

### Glance
```bash
openstack image list
# This will do an API call against `glance` API
```
If this is answering an empty line, you're good! (you don't have any image yet)

### Neutron

```bash
openstack network list
# This will do an API call against `neutron` API
```
If this is answering an empty line, you're good! (you don't have any network yet)

### Nova

```bash
openstack server list
# This will do an API call against `nova` API
```
If this is answering an empty line, you're good! (you don't have any instance yet)

## In case of error - debugging

If something failed, this is perhaps due to a race condition during deployment.

So you can rollout restart some services.

Most of the issue will appear on nova side:

```bash
k rollout restart deployment/nova-api
k rollout restart deployment/nova-metadata-api
```

You may also have to re-execute some jobs, such as `nova db sync`.

You can either do it from nova-api pod, or delete and recreate the related job.

To make sure that this is the root cause of your issue, you can connect on the DB:

```bash
k exec -it mysql-89d76b8-qtx2j -- mysql -u root -p
```

You can also check the logs:

```bash
k exec -it nova-api-b6995b597-xmvfm -- bash
# and then
tail -F /var/log/nova/nova-api.log
```

# compute-1
Now that the `OpenStack` control plane is ready, you can install your compute.
Like you did for  `k3s-1`, now SSH in `compute-1` and login as `root`.

## Clone the repo (on compute-1)
We will need some of the `ansible` playbooks that are in the repo:
```bash
apt-get install -y git
git clone https://github.com/arnaudmorin/bootstrap-openstack-k8s.git
cd bootstrap-openstack-k8s
```

## Copy the config file from k8s-1

```bash
cd config
# Paste the cURL (result of `plik -s` command from k8s-1)
# You should now have config.yaml along side with config.yaml.sample
# Get back to previous folder
cd ..
```

## Run the play
All `OpenStack` services running on the compute are going to be executed outside of `kubernetes` (`kubernetes` is installed only on `k3s-1` node, not on the `compute-1`).
To install them, we rely on a playbook:
```bash
apt-get install -y ansible
ansible-playbook ansible/bootstrap-compute.yaml
```

# Populate your OpenStack with default values

From your `k3s-1` node, as root:
```sh
# Source helper functions
source helper

# Following actions are done as admin
source openrc_admin
create_flavors
create_image_cirros
create_image_debian
# Before running this one, adjust the parameters with your network settings
create_network_public 5.135.0.208/28 5.135.0.222

# Following actions are done as demo
source openrc_demo
create_network_private
create_rules
create_key
create_server_public
```


# Notes

If you decide to add more `k8s-x` and `compute-x` nodes, this is very easy, just edit the bootstrap.sh script and start again.

To let k3s on other nodes join the first one, just use something like this:

```
export K3S_TOKEN='xxxyyyy'    # retrieve from master node with: cat /var/lib/rancher/k3s/server/node-token
export K3S_URL='https://ip_first_node:6443'
curl -sfL https://get.k3s.io | sh -
```
