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

variable "os_version" {
  type = string
  description = "Branch used to deploy the cluster"
  default = "2025.1"
}

resource "random_password" "password" {
  length = 16
  special = false
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
  user_data = templatefile("${path.module}/userdata/k8s.tftpl",
    {
      path_module = path.module,
      password = random_password.password.result
    }
  )
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }
}

resource "openstack_compute_instance_v2" "computes" {
  count = 2

  name = "compute-${count.index}"
  image_name = "Debian 12"
  flavor_name = "r3-64"
  user_data = templatefile("${path.module}/userdata/compute.tftpl",
    {
      path_module = path.module,
      password = random_password.password.result
      k8s_ip = openstack_compute_instance_v2.k8s[0].access_ip_v4
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

  name = "network-${count.index}"
  image_name = "Debian 12"
  flavor_name = "r3-64"
  user_data = templatefile("${path.module}/userdata/network.tftpl",
    {
      path_module = path.module,
      password = random_password.password.result
      k8s_ip = openstack_compute_instance_v2.k8s[0].access_ip_v4
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

# resource "local_file" "test" {
#   content = templatefile("${path.module}/userdata/compute.tftpl",
#     {
#       path_module = path.module,
#       password = random_password.password.result
#       k8s_ip = openstack_compute_instance_v2.k8s[0].access_ip_v4
#     }
#     )

#   filename = "${path.module}/testfile"
# }
