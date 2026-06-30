# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Tooling to bootstrap a small **OpenStack-over-OpenStack** deployment inside an OVH public cloud project. OpenTofu provisions a handful of VMs; cloud-init then turns them into a working OpenStack cluster with **zero further manual steps** in the happy path. The OpenStack control plane runs as containers on k3s; the data plane runs as native systemd services on separate nodes.

Read `README.md` first — it is a detailed, step-by-step walkthrough of the whole flow including manual recovery commands.

## Architecture

Three node roles, all with public IPs:

- **k8s-0** (control plane): runs k3s. All OpenStack *API* services (keystone, glance, nova-api, neutron-server, placement, skyline, mistral, octavia, barbican, cinder), plus mysql, rabbitmq, and redis, run as k8s Deployments/StatefulSets here. This node also acts as the operator workstation (kubectl, ansible, openstack CLI all run from here).
- **compute-N** (data plane): runs `nova-compute` and neutron OVS/L3/metadata agents as **systemd services, not in k8s**. Configured by Ansible. Has an extra interface on the public vRack (vlan 0).
- **network-N** (data plane): runs neutron agents for `dvr_snat` + DHCP (OpenStack can't do DVR-with-SNAT on computes — see README for the upstream bug link). Also Ansible-configured.

An `octavia` management network connects all nodes (172.21.0.0/16) for Octavia amphora communication.

### The deployment flow (the single most important thing to understand)

1. `tofu/main.tf` creates the VMs and wires per-node `user_data` from the `tofu/userdata/*.tftpl` templates (each prepends the shared `tofu/userdata/generic` snippet).
2. **`tofu/userdata/k8s.tftpl` is the master orchestration script.** On first boot of k8s-0 it: installs k3s/docker/tooling, clones this repo + `arnaudmorin/openstack-docker`, renders every k8s manifest, brings services up in dependency order (mysql → redis → rabbit → keystone → everything else → octavia), bootstraps keystone, and pre-populates flavors/images/networks. When editing the bring-up sequence or service config, **this file is usually where you work.** Its final log line is `done`; postinstall progress lands in `/var/log/postinstall.log` on the node.
3. `compute.tftpl` / `network.tftpl` join k3s is *not* installed there — instead they run the Ansible playbooks to set up the data plane.

### Templating: frep, not Helm

Kubernetes manifests are **not** Helm charts. They are `k8s/*.yaml.in` templates rendered by [`frep`](https://github.com/subchen/frep) (Go text/template syntax, `{{ .password }}` etc.), fed from `config/config.yaml`. The canonical render-and-apply idiom is:

```bash
frep k8s/<service>.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

`mysql.yaml.in` is rendered once per database via `--env db_name=<name>`. On k8s-0 there are `frep-<service>` shell aliases (defined in `k8s.tftpl`) wrapping these. Service config (e.g. `keystone.conf`) lives **inline inside the `.yaml.in` files as ConfigMaps** — to change OpenStack service settings, edit the relevant `k8s/*.yaml.in`, not a separate config file.

### Config

`config/config.yaml` is generated on the node from `config/config.yaml.sample` (it is gitignored). cloud-init substitutes the domain (`<ip>.xip.opensteak.fr`), password, and OpenStack version into it. The `amp_*` Octavia placeholders are filled in later in the k8s.tftpl flow once the amphora flavor/network/secgroup exist.

## Versioning convention

**Git branches are OpenStack release names** (`2024.2`, `2025.1`, `2025.2`, `2026.1`). The branch name is the OpenStack version: `var.openstack_version` in `tofu/main.tf` defaults to the current branch's release and is used to (a) check out the matching branch of this repo and of `openstack-docker` on the node, and (b) tag the container images pulled. PRs target `2026.1` (the current release branch) unless working a release-specific change. Keep `openstack_version` and the branch consistent.

## Common commands

Provisioning (run locally, with an OpenStack `openrc` sourced):

```bash
cd tofu/
tofu init
tofu workspace select <name>   # state is per-workspace (see tofu/terraform.tfstate.d/)
tofu apply
tofu output                    # prints ssh commands for all nodes
```

SSH uses the committed, unencrypted `ansible/files/zob` key (intentionally insecure — demo only):

```bash
chmod 600 ansible/files/zob && ssh-add ansible/files/zob
ssh root@<ip>
```

On a node (everything below runs **as root**, from `/root/bootstrap-openstack-k8s`):

```bash
k get all                                  # alias: k=kubectl, l=stern, os=openstack
ansible-playbook ansible/bootstrap-compute.yaml   # (re)configure a compute node
ansible-playbook ansible/bootstrap-network.yaml   # (re)configure a network node
source /root/helper                        # load create_flavors / create_network_public / ... functions
source /root/openrc_admin                  # admin creds; openrc_demo / openrc_octavia also exist
```

Re-rendering a single manifest after editing its template:

```bash
frep k8s/keystone.yaml.in:- --load config/config.yaml | kubectl apply -f -
```

## Other directories

- `ansible/` — data-plane playbooks (`bootstrap-compute.yaml`, `bootstrap-network.yaml`) and the systemd unit files / ssh key in `ansible/files/`.
- `keystone-bootstrap/` — a Python tool (`keystone-bootstrap`) that creates keystone projects/users/roles/endpoints from a frep-rendered `keystone-settings.yaml`.
- `files/` — `helper` (the `create_*` bash functions for populating OpenStack) and `openrc.in`.
- `extra/` — `add-project.sh` / `clean-project.sh` for managing tenant projects post-deploy.
- `order-ipfo/` — standalone Python tool (own venv) to order an OVH failover-IP block via the OVH API.

## Conventions when editing

- Keep code comments in the existing `# NOTE(arnaud) ...` style used across the templates and playbooks.
- The bring-up order in `k8s.tftpl` matters and is guarded by `kubectl wait` calls — preserve dependency ordering (redis/rabbit/mysql before keystone, keystone before the rest). Race conditions on first boot are expected; README documents the `rollout restart` / job-delete recovery steps.
- `config/config.yaml`, `keystone-settings.yaml`, tfstate, `*.qcow2`, and the per-tool venvs are gitignored — don't commit them.
