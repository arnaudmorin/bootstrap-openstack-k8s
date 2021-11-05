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
bootstrap.sh

# List instances
nova list
```

## SSH into instances
At the end, you should be able to ssh both instances using the `zob` key:
```bash
chmod 600 ansible/files/zob
ssh debian@ip -i ansible/files/zob		# replace ip with the real server IP
```

# k3s
 On the k8s-1 instance, we will install k3s.
 See https://k3s.io/ for more info.

## Installation
```bash
curl -sfL https://get.k3s.io | sh -
```

## Configuration
Alias
```
alias k='kubectl'
```

Test
```
k get all
```


# Install frep

```
curl -fSL https://github.com/subchen/frep/releases/download/v1.3.12/frep-1.3.12-linux-amd64 -o /usr/local/bin/frep
chmod +x /usr/local/bin/frep
```

More info here: https://github.com/subchen/frep

# Install plik
TODO

# Install ansible
```
$ apt-get install ansible
```

# Clone bootstrap-openstack-k8s

Clone
```
git clone xxx
```

Mysql
```
cd bootstrap-openstack-k8s
frep k8s/mysql.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

Rabbit
```
frep k8s/rabbit.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

Keystone
```
frep k8s/keystone.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

Run the playbook
```
ansible-playbook ansible/bootstrap-keystone.yaml
```

Glance
```
frep k8s/glance.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

Placement
```
frep k8s/placement.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

Neutron
```
frep k8s/neutron.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

Nova
```
frep k8s/nova.yaml.in:- --load config/config.yaml | kubectl apply -f -
```




bootstrap-compute
```
ansible-playbook ansible/bootstrap-compute.yaml
```
