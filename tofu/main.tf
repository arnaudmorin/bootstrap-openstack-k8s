terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
      version = "~> 3.0.0"
    }
  }
}

provider "openstack" {

}

resource "openstack_networking_network_v2" "public" {
  name = "public"
  port_security_enabled = false
  value_specs = {
    "provider:network_type"    = "vrack"
    "provider:segmentation_id" = 0
  }

}

resource "openstack_networking_subnet_v2" "public_subnet" {
  name = "192.168.1.0/24"
  network_id = openstack_networking_network_v2.public.id
  cidr = "192.168.1.0/24"
  no_gateway = true
  enable_dhcp = false
  dns_nameservers = [ "0.0.0.0" ]
}

resource "openstack_compute_keypair_v2" "zob" {
  name = "zob"
  public_key = file("${path.module}/../ansible/files/zob.pub")
}

resource "openstack_compute_instance_v2" "k8s" {
  count = 1
  
  name = "k8s-${count.index}"
  image_name = "Debian 12"
  flavor_name = "r3-64"
  user_data = file("${path.module}/../userdata/k8s")
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }
}

resource "openstack_compute_instance_v2" "computes" {
  count = 2

  name = "$compute-${count.index}"
  image_name = "Debian 12"
  flavor_name = "r3-64"
  user_data = file("../userdata/compute")
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

  name = "network-${count.index}"
  image_name = "Debian 12"
  flavor_name = "r3-64"
  user_data = file("../userdata/compute")
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }

  network {
    name = openstack_networking_network_v2.public.name
  }
}

resource "local_file" "inventory" {

  content = templatefile("${path.module}/inventory.tftpl",
    {
      k8s_instances = openstack_compute_instance_v2.k8s
      networks = openstack_compute_instance_v2.networks
      computes = openstack_compute_instance_v2.computes
    }
    )
  
  filename = "${path.module}/../ansible//inventory.yml"
  file_permission = "0655"
}
