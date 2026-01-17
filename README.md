Table of Contents
=================

* [Table of Contents](#table-of-contents)
* [Introduction](#introduction)
  * [Objective](#objective)
  * [Architecture](#architecture)
* [Bootstrap](#bootstrap)
  * [Source your openrc](#source-your-openrc)
  * [Clone this repo](#clone-this-repo)
  * [tofu](#tofu)
  * [Start instances](#start-instances)
  * [SSH into instances](#ssh-into-instances)
* [k8s\-0](#k8s-0)
  * [k3s](#k3s)
  * [k9s](#k9s)
  * [plik](#plik)
  * [config\.yaml](#configyaml)
  * [frep](#frep)
* [compute\-x and network\-x](#compute-x-and-network-x)
  * [logs](#logs)
  * [playbook](#playbook)
* [Test your OpenStack deployment](#test-your-openstack-deployment)
  * [openrc\_admin](#openrc_admin)
  * [Keystone](#keystone)
  * [Glance](#glance)
  * [Neutron](#neutron)
  * [Nova](#nova)
  * [Skyline](#skyline)
  * [In case of error \- debugging](#in-case-of-error---debugging)
  * [Collect and centralize logs](#collect-and-centralize-logs)
* [Populate your OpenStack with default values](#populate-your-openstack-with-default-values)
* [Notes](#notes)

# Introduction

## Objective

Main objective is to create a small OpenStack infrastructure within an OVH public cloud project (which is also run by OpenStack by the way :p So we will create an OpenStack over OpenStack).

## Architecture

```
                   ┌─────────────────────────────────────────────────┐
                   │       k8s-0  (control plane)                    │
          ssh      ├───┐                                             │
      ───────────► │ E │   ┌──────────┐     ┌──────────┐             │
 you               │ N │   │ neutron  │     │ mysql    │             │
         http      │ S │   └──────────┘     └──────────┘             │
      ───────────► │ 3 │                                   Using:    │
                   ├───┘   ┌──────────┐     ┌──────────┐   -kubectl  │
                   │       │ nova     │     │ rabbit   │   -ansible  │
                   │       └──────────┘     └──────────┘             │
                   │                                                 │
                   │       ┌──────────┐     ┌──────────┐             │
                   │       │ keystone │     │ skyline  │             │
                   │       └──────────┘     └──────────┘             │
                   │                                                 │
                   │       ┌──────────┐     ┌──────────┐             │
                   │       │ glance   │     │ ...      │             │
                   │       └──────────┘     └──────────┘             │
                   │                                                 │
                   └─────────────────────────────────────────────────┘

                   ┌─────────────────────────────────────────────────┐
                   │        compute-0 (data plane)                   │
          ssh      ├───┐                                             │
 you  ───────────► │ E │    ┌─────────────────────┐                  │
                   │ N │    │    neutron agents   │        Using:    │
                   │ S │    └─────────────────────┘        -ansible  │
                   │ 3 │                                             │
                   ├───┘    ┌─────────────────────┐                  │
                   │        │     nova compute    │                  │
                   │        └─────────────────────┘                  │
         ┌───┐     │                                                 │
         │   │     ├───┐    ┌─────────────────────┐                  │
         │ v │     │ E │    │     openvswitch     │                  │
inter    │ R │     │ N │    └─────────────────────┘                  │
net ─────┤ a ├─────┤ S │                                             │
         │ c │     │ 4 │                                             │
         │ k │  ▲  ├───┘                                             │
         │   │  │  │                                                 │
         └───┘  │  └─────────────────────────────────────────────────┘
                │
                └─ Instances public access with /28 network block
                                routed in vRack (vlan 0)

                   ┌─────────────────────────────────────────────────┐
                   │        network-0 (data plane)                   │
          ssh      ├───┐                                             │
 you  ───────────► │ E │    ┌─────────────────────┐                  │
                   │ N │    │    neutron agents   │        Using:    │
                   │ S │    └─────────────────────┘        -ansible  │
                   │ 3 │                                             │
                   ├───┘                                             │
                   │                                                 │
         ┌───┐     │                                                 │
         │   │     ├───┐    ┌─────────────────────┐                  │
         │ v │     │ E │    │     openvswitch     │                  │
inter    │ R │     │ N │    └─────────────────────┘                  │
net ─────┤ a ├─────┤ S │                                             │
         │ c │     │ 4 │                                             │
         │ k │  ▲  ├───┘                                             │
         │   │  │  │                                                 │
         └───┘  │  └─────────────────────────────────────────────────┘
                │
                └─ Routers public access with /28 network block
                                routed in vRack (vlan 0)
```

All nodes (k8s, compute-x, network-x) will have a public IP and be accessible from internet.

`k8s` server will be used to host OpenStack control plane (mostly API, database, queues, schedulers, etc.).

Each OpenStack service will be started in a container, orchestrated using kubernetes (k3s).

`compute` server will be used to host OpenStack data plane (mostly nova compute and neutron agents (L2 and L3)).

`compute` will also have an extra network interface connected to a vRack (using vlan 0).

`network` server will be used for `dvr_snat` and `dhcp`. As of today, OpenStack does not support having DVR with SNAT on computes.

See: https://docs.openstack.org/neutron/latest/admin/deploy-ovs-ha-dvr.html#network-node

And bug: https://bugs.launchpad.net/neutron/+bug/1934666

In this vRack, a routed network acquired from OVHcloud will give the possibility to create a flat external network.

Instances and routers will be able to use this flat network to reach internet.

# Bootstrap

## Source your openrc
You need an OpenStack account to continue, source the `openrc` file now:
```bash
source openrc
```

## Clone this repo
```bash
git clone https://github.com/arnaudmorin/bootstrap-openstack-k8s.git
cd bootstrap-openstack-k8s
```

## tofu

Install `tofu` if not yet done, see here: [https://opentofu.org/docs/intro/install/standalone/](https://opentofu.org/docs/intro/install/standalone/)

## Start instances

Tofu configuration assume the existence of a ``public`` network, if you do not have it you create it using the following commands
```bash
openstack network create public --disable-port-security --provider-network-type=vrack --provider-segment=0
openstack subnet create --no-dhcp --gateway none --subnet-range 192.168.0.0/24 --network public --dns-nameserver 0.0.0.0 192.168.0.0/24
```

Open the tofu folder and apply the config

```bash
cd tofu/
tofu init
tofu apply
```

This will create 6 instances:

* k8s-0
* compute-0
* compute-1
* network-0
* network-1


`tofu` is used to deploy all nodes, and a cloud-init postinstall script is then executed to install everything.

Welcome to my lazy world!

The postinstall scripts may take some time to run (around 5 minutes).
You can check if the scripts are finished by checking the ``/var/log/postinstall.log`` (the last line must be a "done").

The scripts are the equivalent of the following sections up to this [one](#populate-your-openstack-with-default-values)

You can take a look at what is done on the servers by throwing an eye in [tofu/userdata](/tofu/userdata)

## SSH into instances

Grab your instances:

```bash
tofu output
```

You should be able to ssh both instances using the `zob` key:
```bash
chmod 600 ../ansible/files/zob
ssh-add ../ansible/files/zob
ssh root@ip             # replace ip with the real server IP
```

# k8s-0

> NOTE: if not specified, all commands must be run as root: `sudo su -`

## k3s

 On the `k8s-0` instance, you will have `k3s` and few other tools to have a full `kubernetes` cluster.
 See https://k3s.io/ for more info.

You can take a look at kube resources using:

```bash
k get all
```

## k9s

You may want to use k9s in the future, let's install it now
```bash
k9s
```

## plik
`plik` is a tool to upload files to a remote URL.
It's useful to easily transfer files a from a system to another.

```bash
plik -h
```

## config.yaml

You should have a `config.yaml` file:

```bash
# Review config, eventually amend it if you want
# but remember that any change here may need to be also done on compute/network nodes
cat bootstrap-openstack-k8s/config/config.yaml
```

## frep
`frep` is a tool to generate files from templates. Its re-using the `go` templating language.

We will use `frep` to transform k8s templates into manifests.

I did not wanted to use `helm` for this because it's heavy and more difficult to understand.

`frep` is much more simpler.

```bash
frep -h
# We will use frep more a little bit later
```

More info here: https://github.com/subchen/frep

Here are few commands that you may need to rely on if you modify the kubernetes templates.

> Note that you do not need to execute any of this for now, because it's already done by cloud-init :)

```bash
cd bootstrap-openstack-k8s
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=keystone | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=nova | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=placement | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=neutron | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=glance | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=skyline | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=mistral | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=octavia | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=barbican | kubectl apply -f -
frep k8s/mysql.yaml.in:- --load config/config.yaml --env db_name=designate | kubectl apply -f -
frep k8s/mysql-populate.yaml.in:- --load config/config.yaml | kubectl apply -f -
frep k8s/rabbit.yaml.in:- --load config/config.yaml | kubectl apply -f -
frep k8s/keystone.yaml.in:- --load config/config.yaml | kubectl apply -f -
frep k8s/glance.yaml.in:- --load config/config.yaml | kubectl apply -f -
frep k8s/placement.yaml.in:- --load config/config.yaml | kubectl apply -f -
frep k8s/neutron.yaml.in:- --load config/config.yaml | kubectl apply -f -
frep k8s/nova.yaml.in:- --load config/config.yaml | kubectl apply -f -
frep k8s/skyline.yaml.in:- --load config/config.yaml | kubectl apply -f -
frep k8s/mistral.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

# compute-x and network-x

## logs
You should not have anything to do on the compute or network node, but you can take a look at the agents logs:

```bash
lnav /var/log/nova-compute.log
lnav /var/log/neutron-openvswitch-agent.log
lnav /var/log/neutron-l3-agent.log
lnav /var/log/neutron-metadata-agent.log
lnav /var/log/neutron-dhcp-agent.log
```

## playbook

All `OpenStack` services running on the compute are going to be executed outside of `kubernetes` (`kubernetes` is installed only on `k8s-0` node, not on the `compute-0`).

To install them, we rely on a playbook.

You can re-run the playbook if needed:

```bash
cd bootstrap-openstack-k8s
ansible-playbook ansible/bootstrap-compute.yaml
# or
ansible-playbook ansible/bootstrap-network.yaml
```

# Test your OpenStack deployment
## openrc_admin

You should have an `openrc_admin` file to access your `OpenStack` cluster as an administrator.
Source this file:
```bash
source /root/openrc_admin
```

Now try each element of your `OpenStack`

## Keystone
```bash
openstack token issue
```
Which should give you something like:
```bash
# This command is doing an API call against `keystone` and should give you something like:
+------------+----------------------------------------+
| Field      | Value                                  |
+------------+----------------------------------------+
| expires    | 2021-11-05T21:35:40+0000               |
| id         | gAAAAABhhZWc-f-TGVV2NNqN03KXLpgIDmBD2f |
| project_id | 966629a3e2f34ad996d0ec8d57f6a1bd       |
| user_id    | fd6a41322bdc4941ae74354697fcc2db       |
+------------+----------------------------------------+
```
If you have your token, it means `keystone` is good!

## Glance
```bash
openstack image list
# This will do an API call against `glance` API
```
If this is answering an empty line, you're good! (you don't have any image yet)

## Neutron

```bash
openstack network list
# This will do an API call against `neutron` API
```
If this is answering an empty line, you're good! (you don't have any network yet)

## Nova

```bash
openstack server list
# This will do an API call against `nova` API
```
If this is answering an empty line, you're good! (you don't have any instance yet)

## Skyline

Skyline is a web interface, so you should browse the page.

http://skyline.${ip}.xip.opensteak.fr

> Note that you can grab your skyline URI by listing the kube ingress: `k get ingress`

## In case of error - debugging

If something failed, this is perhaps due to a race condition during deployment.

So you can rollout restart some services.

Most of the issue will appear on nova side:

```bash
k rollout restart deployment/nova-api
k rollout restart deployment/nova-metadata-api
```

You may also have to re-execute some jobs, such as `nova init`.

You can either do it from nova-api pod, or delete and recreate the related job.

To make sure that this is the root cause of your issue, you can connect on the DB:

```bash
k exec -it mysql-89d76b8-qtx2j -- mysql -u root -p
```

You can also check the logs:

```bash
k logs nova-api-b6995b597-xmvfm    # replace nova-api-b6995b597-xmvfm with your pod name, you can get it with: k get pods | grep nova
```

One of the most common race condition is the failure on nova db sync.

You can restart it by deleting the jobs and do it again
```bash
k get jobs | grep nova
k delete job nova-init

# And then apply again the mysql-populate
frep k8s/mysql-populate.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

## Collect and centralize logs

If you want to collect and analyze `OpenStack` logs in a centralized way, I created a `alloy`/`loki`/`grafana` stack that can be deployed with:

```bash
frep k8s/loki.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

# Populate your OpenStack with default values

Back on your `k8s-0` node, as root:
```sh
# Be root if not already done
sudo su -
# Source helper functions
source /root/helper

# Following actions are done as admin
source /root/openrc_admin
create_flavors
create_image_cirros
create_image_debian
# Before running this one, adjust the parameters with your network settings
# If you need to buy an IPFO block, check the tool in order-ipfo/ folder
# For VeryTechTrip event, you should have received a START and END values
create_network_public START END

# Following actions are done as demo
source /root/openrc_demo
create_network_private
create_rules
create_key
create_server_public

# After creating your first public server, you can grab it's ip with:
openstack server list

# To login:
ssh cirros@ip_of_server         # password is gocubsgo

# If you dont have a real public IP, you can reach the console using the serial and osconsole
openstack console url show p1 --serial
osconsole 'ws://xyz'
```

# Notes

If you decide to add more `k8s-x` and `compute-x` nodes, this is very easy, just edit the ``tofu/main.tf`` file and run ``tofu apply`` again.

To let k3s on other nodes join the first one, just use something like this:

```
export K3S_TOKEN='xxxyyyy'    # retrieve from master node with: cat /var/lib/rancher/k3s/server/node-token
export K3S_URL='https://ip_first_node:6443'
curl -sfL https://get.k3s.io | sh -
```

> Note that you may need to tweak a little bit the postinstall to avoid the new `k8s` nodes to start a complete new `OpenStack` (e.g. disable the `user-data`)
