terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0.0"
    }
  }
}

provider "openstack" {

}

variable "openstack_version" {
  type        = string
  description = "Openstack version to deploy the cluster, it used to reference branch of bootstrap-openstack-k8s openstack-docker repos and as the tag of the os services images to pull"
  default     = "2025.1"
}

variable "compute_count" {
  description = "Number of compute nodes"
  type = number
  default = 2
}

variable "network_count" {
  description = "Number of network node"
  type = number
  default = 2
}

resource "random_password" "password" {
  length  = 16
  special = false
}

data "openstack_networking_network_v2" "public" {
  name = "public"
}

resource "openstack_networking_port_v2" "public_port" {
  count = var.compute_count + var.network_count
  name = "${terraform.workspace}-public-port-${count.index}"
  network_id = data.openstack_networking_network_v2.public.id
  admin_state_up = "true"
}

resource "openstack_networking_network_v2" "octavia_mgmt" {
  name = "${terraform.workspace}-octavia-mgmt"
  port_security_enabled = false
  value_specs = {
    "provider:network_type" = "vrack"
  }
}

resource "openstack_networking_port_v2" "octavia_port" {
  count = var.compute_count + var.network_count + 1
  name = "${terraform.workspace}-octavia-port-${count.index}"
  network_id = openstack_networking_network_v2.octavia_mgmt.id
  admin_state_up = "true"
}

resource "openstack_compute_keypair_v2" "zob" {
  name       = "${terraform.workspace}-zob"
  public_key = file("${path.module}/../ansible/files/zob.pub")
}

resource "openstack_compute_instance_v2" "k8s" {
  count = 1

  name        = "${terraform.workspace}-k8s-${count.index}"
  image_name  = "Debian 12"
  flavor_name = "r3-64"
  user_data = templatefile("${path.module}/userdata/k8s.tftpl",
    {
      path_module = path.module,
      password    = random_password.password.result
      os_version  = var.openstack_version
    }
  )
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }
}

resource "openstack_compute_interface_attach_v2" "attach_octavia_k8s" {
  count = 1
  instance_id = openstack_compute_instance_v2.k8s[count.index].id
  port_id = openstack_networking_port_v2.octavia_port[count.index].id
}

resource "openstack_compute_instance_v2" "computes" {
  count = var.compute_count

  name        = "${terraform.workspace}-compute-${count.index}"
  image_name  = "Debian 12"
  flavor_name = "r3-64"
  user_data = templatefile("${path.module}/userdata/compute.tftpl",
    {
      path_module = path.module,
      password    = random_password.password.result
      k8s_ip      = openstack_compute_instance_v2.k8s[0].access_ip_v4
      os_version  = var.openstack_version
      hostname    = "compute-${count.index}"
    }
  )
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }
}

resource "openstack_compute_interface_attach_v2" "attach_public_computes" {
  count = var.compute_count
  instance_id = openstack_compute_instance_v2.computes[count.index].id
  port_id = openstack_networking_port_v2.public_port[count.index].id
}

resource "openstack_compute_interface_attach_v2" "attach_octavia_computes" {
  count = var.compute_count
  instance_id = openstack_compute_instance_v2.computes[count.index].id
  port_id = openstack_networking_port_v2.octavia_port[count.index + 1].id
}

resource "openstack_compute_instance_v2" "networks" {
  count = var.network_count

  name        = "${terraform.workspace}-network-${count.index}"
  image_name  = "Debian 12"
  flavor_name = "r3-64"
  user_data = templatefile("${path.module}/userdata/network.tftpl",
    {
      path_module = path.module,
      password    = random_password.password.result
      k8s_ip      = openstack_compute_instance_v2.k8s[0].access_ip_v4
      os_version  = var.openstack_version
      hostname    = "network-${count.index}"
    }
  )
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }
}

resource "openstack_compute_interface_attach_v2" "attach_public_networks" {
  count = var.network_count
  instance_id = openstack_compute_instance_v2.networks[count.index].id
  port_id = openstack_networking_port_v2.public_port[count.index + var.compute_count].id
}

resource "openstack_compute_interface_attach_v2" "attach_octavia_networks" {
  count = var.network_count
  instance_id = openstack_compute_instance_v2.networks[count.index].id
  port_id = openstack_networking_port_v2.octavia_port[count.index + 1 + var.compute_count].id
}

output "ssh_commands" {
  value = merge(
    { for idx, instance in openstack_compute_instance_v2.k8s : instance.name => "ssh root@${instance.access_ip_v4}" },
    { for idx, instance in openstack_compute_instance_v2.computes : instance.name => "ssh root@${instance.access_ip_v4}" },
    { for idx, instance in openstack_compute_instance_v2.networks : instance.name => "ssh root@${instance.access_ip_v4}" }
  )
  description = "SSH commands (make sure you loaded the 'zob' key in your ssh-agent)"
}
