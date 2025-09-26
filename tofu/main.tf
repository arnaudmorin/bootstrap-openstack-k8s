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

resource "random_password" "password" {
  length  = 16
  special = false
}

resource "openstack_networking_network_v2" "public" {
  name                  = "${terraform.workspace}-public"
  port_security_enabled = false
  value_specs = {
    "provider:network_type"    = "vrack"
    "provider:segmentation_id" = 0
  }

}

resource "openstack_networking_subnet_v2" "public_subnet" {
  name            = "192.168.1.0/24"
  network_id      = openstack_networking_network_v2.public.id
  cidr            = "192.168.1.0/24"
  no_gateway      = true
  enable_dhcp     = false
  dns_nameservers = ["0.0.0.0"]
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
      workspace   = terraform.workspace
      name        = "k8s-${count.index}"
    }
  )
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }
}

resource "openstack_compute_instance_v2" "computes" {
  count = 2

  name        = "${terraform.workspace}-compute-${count.index}"
  image_name  = "Debian 12"
  flavor_name = "r3-64"
  user_data = templatefile("${path.module}/userdata/compute.tftpl",
    {
      path_module = path.module,
      password    = random_password.password.result
      k8s_ip      = openstack_compute_instance_v2.k8s[0].access_ip_v4
      os_version  = var.openstack_version
      workspace   = terraform.workspace
      hostname    = "compute-${count.index}"
    }
  )
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }

  network {
    name = openstack_networking_network_v2.public.name
  }
}

resource "openstack_compute_instance_v2" "networks" {
  count = 2

  name        = "${terraform.workspace}-network-${count.index}"
  image_name  = "Debian 12"
  flavor_name = "r3-64"
  user_data = templatefile("${path.module}/userdata/network.tftpl",
    {
      path_module = path.module,
      password    = random_password.password.result
      k8s_ip      = openstack_compute_instance_v2.k8s[0].access_ip_v4
      os_version  = var.openstack_version
      workspace   = terraform.workspace
      hostname    = "network-${count.index}"
    }
  )
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }

  network {
    name = openstack_networking_network_v2.public.name
  }
}

output "ssh_commands" {
  value = merge(
    { for idx, instance in openstack_compute_instance_v2.k8s : instance.name => "ssh root@${instance.access_ip_v4}" },
    { for idx, instance in openstack_compute_instance_v2.computes : instance.name => "ssh root@${instance.access_ip_v4}" },
    { for idx, instance in openstack_compute_instance_v2.networks : instance.name => "ssh root@${instance.access_ip_v4}" }
  )
  description = "SSH commands (make sure you loaded the 'zob' key in your ssh-agent)"
}
