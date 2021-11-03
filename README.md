# Start debian 11

# Install k3s


```
curl -sfL https://get.k3s.io | sh -
```

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

