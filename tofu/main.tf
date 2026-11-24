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


#
# Variables
#

variable "openstack_version" {
  type        = string
  description = "Openstack version to deploy the cluster, it used to reference branch of bootstrap-openstack-k8s openstack-docker repos and as the tag of the os services images to pull"
  default     = "2026.2"
}

variable "bootstrap_branch" {
  type        = string
  description = "Branch of bootstrap-openstack-k8s cloned on the nodes, to test changes before merging them (default: openstack_version)"
  default     = ""
}

variable "messaging" {
  type        = string
  description = "Messaging backend: rabbit (RabbitMQ) or bmq (BlazingMQ)"
  default     = "rabbit"
  validation {
    condition     = contains(["rabbit", "bmq"], var.messaging)
    error_message = "messaging must be rabbit or bmq."
  }
}

variable "compute_count" {
  description = "Number of compute nodes"
  type        = number
  default     = 2
}

variable "network_count" {
  description = "Number of network node"
  type        = number
  default     = 2
}

locals {
  baremetal = var.baremetal_count > 0 ? 1 : 0
}

resource "random_password" "password" {
  length  = 16
  special = false
}

# BlazingMQ TLS: a certificate authority, and the broker certificate signed by it
# NOTE(arnaud) the clients verify the broker certificate against the CA, not its name
resource "tls_private_key" "bmq_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "bmq_ca" {
  private_key_pem       = tls_private_key.bmq_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600
  allowed_uses          = ["cert_signing", "crl_signing"]
  subject {
    common_name = "blazingmq-ca"
  }
}

resource "tls_private_key" "bmq" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "bmq" {
  private_key_pem = tls_private_key.bmq.private_key_pem
  dns_names       = ["blazingmq", "*.xip.opensteak.fr"]
  subject {
    common_name = "blazingmq"
  }
}

resource "tls_locally_signed_cert" "bmq" {
  cert_request_pem      = tls_cert_request.bmq.cert_request_pem
  ca_private_key_pem    = tls_private_key.bmq_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.bmq_ca.cert_pem
  validity_period_hours = 87600
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth"]
}

data "openstack_networking_network_v2" "public" {
  name = "public"
}

#
# Ports
#
# NOTE(arnaud) we need to create ports in a separate way to have access to their mac_address

resource "openstack_networking_port_v2" "public_port" {
  count          = var.compute_count + var.network_count
  name           = "${terraform.workspace}-public-port-${count.index}"
  network_id     = data.openstack_networking_network_v2.public.id
  admin_state_up = "true"
  tags           = ["role=management"]
}

resource "openstack_networking_network_v2" "octavia_mgmt" {
  name                  = "${terraform.workspace}-octavia-mgmt"
  port_security_enabled = false
  value_specs = {
    "provider:network_type" = "vrack"
  }
}

resource "openstack_networking_port_v2" "octavia_port" {
  count          = var.compute_count + var.network_count + 1
  name           = "${terraform.workspace}-octavia-port-${count.index}"
  network_id     = openstack_networking_network_v2.octavia_mgmt.id
  admin_state_up = "true"
}

#
# Bare metal (Ironic)
#

resource "openstack_networking_network_v2" "baremetal" {
  count                 = local.baremetal
  name                  = "${terraform.workspace}-baremetal"
  port_security_enabled = false
  value_specs = {
    "provider:network_type" = "vrack"
  }
}

resource "openstack_networking_subnet_v2" "baremetal" {
  count       = local.baremetal
  name        = "${terraform.workspace}-baremetal"
  network_id  = openstack_networking_network_v2.baremetal[0].id
  cidr        = "10.255.0.0/16"
  enable_dhcp = false
  no_gateway  = true
}

# NOTE(aruan) one port for k8s-0 (ironic-conductor), then one per network node (dhcp agent)
resource "openstack_networking_port_v2" "baremetal_port" {
  count          = local.baremetal * (1 + var.network_count)
  name           = "${terraform.workspace}-baremetal-port-${count.index}"
  network_id     = openstack_networking_network_v2.baremetal[0].id
  admin_state_up = "true"
}

# NOTE(aruan) the ironic-python-agent ignores the MAC addresses starting with fa:,
# which neutron gives by default, so the nodes get their own. 52:54:00 is the
# locally administered prefix QEMU uses for VM NICs: no vendor owns it.
resource "openstack_networking_port_v2" "baremetal_node_port" {
  count          = var.baremetal_count
  name           = "${terraform.workspace}-baremetal-node-port-${count.index}"
  network_id     = openstack_networking_network_v2.baremetal[0].id
  mac_address    = format("52:54:00:00:%02x:%02x", floor(count.index / 256), count.index % 256)
  admin_state_up = "true"
  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.baremetal[0].id
  }
}

# NOTE(aruan) sushy-emulator boots a node in PXE by rescuing its instance with an iPXE
# disk image, and nova takes the firmware from that image: one image per firmware
resource "openstack_images_image_v2" "ipxe" {
  for_each         = local.baremetal == 1 ? toset(["bios", "uefi"]) : toset([])
  name             = "${terraform.workspace}-ipxe-${each.key}"
  image_source_url = "https://boot.ipxe.org/ipxe.usb"
  container_format = "bare"
  disk_format      = "raw"
  visibility       = "private"
  properties       = each.key == "uefi" ? { hw_firmware_type = "uefi" } : {}
}

# NOTE(aruan) the OVH APIs refuse the application credentials with access rules, so this
# one can act on every instance of the project: deploy in a dedicated project
resource "openstack_identity_application_credential_v3" "sushy" {
  count        = local.baremetal
  name         = "${terraform.workspace}-sushy"
  description  = "sushy-emulator of ${terraform.workspace}: power and rescue of the bare metal instances"
  unrestricted = false
  roles        = ["instances_operator", "observer"]
  expires_at   = var.baremetal_credential_expiry_days > 0 ? timeadd(timestamp(), "${var.baremetal_credential_expiry_days * 24}h") : null
  lifecycle {
    ignore_changes = [expires_at]
  }
}

locals {
  sushy_cloud = local.baremetal == 0 ? "" : yamlencode({
    clouds = {
      ovh = {
        auth_type   = "v3applicationcredential"
        region_name = openstack_identity_application_credential_v3.sushy[0].region
        auth = {
          auth_url                      = var.auth_url
          application_credential_id     = openstack_identity_application_credential_v3.sushy[0].id
          application_credential_secret = openstack_identity_application_credential_v3.sushy[0].secret
        }
      }
    }
  })
}


#
# Server group
#
resource "openstack_compute_servergroup_v2" "compute-server-group" {
  name     = "${terraform.workspace}-compute-server-group"
  policies = ["soft-anti-affinity"]
}

#
# Instances
#

resource "openstack_compute_keypair_v2" "zob" {
  name       = "${terraform.workspace}-zob"
  public_key = file("${path.module}/../ansible/files/zob.pub")
}

resource "openstack_compute_instance_v2" "k8s" {
  count = 1

  name        = "${terraform.workspace}-k8s-${count.index}"
  image_name  = "Debian 13"
  flavor_name = var.k8s_flavor
  user_data = templatefile("${path.module}/userdata/k8s.tftpl",
    {
      path_module        = path.module,
      password           = random_password.password.result
      os_version         = var.openstack_version
      branch             = coalesce(var.bootstrap_branch, var.openstack_version)
      messaging          = var.messaging
      bmq_ca_cert        = tls_self_signed_cert.bmq_ca.cert_pem
      bmq_cert           = tls_locally_signed_cert.bmq.cert_pem
      bmq_key            = tls_private_key.bmq.private_key_pem_pkcs8
      mac_octavia        = openstack_networking_port_v2.octavia_port[count.index].mac_address
      baremetal          = local.baremetal == 1
      mac_baremetal      = try(openstack_networking_port_v2.baremetal_port[0].mac_address, "")
      sushy_cloud        = local.sushy_cloud
      baremetal_prefix   = terraform.workspace
      baremetal_firmware = var.baremetal_firmware
    }
  )
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }
}

# NOTE(arnaud) we need to attach ports separately because they do not have
# any subnet
resource "openstack_compute_interface_attach_v2" "attach_octavia_k8s" {
  count       = 1
  instance_id = openstack_compute_instance_v2.k8s[count.index].id
  port_id     = openstack_networking_port_v2.octavia_port[count.index].id
}

resource "openstack_compute_interface_attach_v2" "attach_baremetal_k8s" {
  count       = local.baremetal
  instance_id = openstack_compute_instance_v2.k8s[0].id
  port_id     = openstack_networking_port_v2.baremetal_port[0].id
}

resource "openstack_compute_instance_v2" "computes" {
  count = var.compute_count

  name        = "${terraform.workspace}-compute-${count.index}"
  image_name  = "Debian 13"
  flavor_name = var.compute_flavor
  user_data = templatefile("${path.module}/userdata/compute.tftpl",
    {
      path_module = path.module,
      password    = random_password.password.result
      k8s_ip      = openstack_compute_instance_v2.k8s[0].access_ip_v4
      os_version  = var.openstack_version
      branch      = coalesce(var.bootstrap_branch, var.openstack_version)
      messaging   = var.messaging
      bmq_ca_cert = tls_self_signed_cert.bmq_ca.cert_pem
      hostname    = "compute-${count.index}"
      mac_public  = openstack_networking_port_v2.public_port[count.index].mac_address
      mac_octavia = openstack_networking_port_v2.octavia_port[count.index + 1].mac_address
    }
  )
  key_pair = openstack_compute_keypair_v2.zob.name
  scheduler_hints {
    group = openstack_compute_servergroup_v2.compute-server-group.id
  }
  network {
    name = "Ext-Net"
  }
}

resource "openstack_compute_interface_attach_v2" "attach_public_computes" {
  count       = var.compute_count
  instance_id = openstack_compute_instance_v2.computes[count.index].id
  port_id     = openstack_networking_port_v2.public_port[count.index].id
}

resource "openstack_compute_interface_attach_v2" "attach_octavia_computes" {
  count       = var.compute_count
  instance_id = openstack_compute_instance_v2.computes[count.index].id
  port_id     = openstack_networking_port_v2.octavia_port[count.index + 1].id
}

resource "openstack_compute_instance_v2" "networks" {
  count = var.network_count

  name        = "${terraform.workspace}-network-${count.index}"
  image_name  = "Debian 13"
  flavor_name = var.network_flavor
  user_data = templatefile("${path.module}/userdata/network.tftpl",
    {
      path_module   = path.module,
      password      = random_password.password.result
      k8s_ip        = openstack_compute_instance_v2.k8s[0].access_ip_v4
      os_version    = var.openstack_version
      branch        = coalesce(var.bootstrap_branch, var.openstack_version)
      messaging     = var.messaging
      bmq_ca_cert   = tls_self_signed_cert.bmq_ca.cert_pem
      hostname      = "network-${count.index}"
      mac_public    = openstack_networking_port_v2.public_port[count.index + var.compute_count].mac_address
      mac_octavia   = openstack_networking_port_v2.octavia_port[count.index + var.compute_count + 1].mac_address
      baremetal     = local.baremetal == 1
      mac_baremetal = try(openstack_networking_port_v2.baremetal_port[count.index + 1].mac_address, "")
    }
  )
  key_pair = openstack_compute_keypair_v2.zob.name
  network {
    name = "Ext-Net"
  }
}

resource "openstack_compute_interface_attach_v2" "attach_public_networks" {
  count       = var.network_count
  instance_id = openstack_compute_instance_v2.networks[count.index].id
  port_id     = openstack_networking_port_v2.public_port[count.index + var.compute_count].id
}

resource "openstack_compute_interface_attach_v2" "attach_octavia_networks" {
  count       = var.network_count
  instance_id = openstack_compute_instance_v2.networks[count.index].id
  port_id     = openstack_networking_port_v2.octavia_port[count.index + 1 + var.compute_count].id
}

resource "openstack_compute_interface_attach_v2" "attach_baremetal_networks" {
  count       = local.baremetal * var.network_count
  instance_id = openstack_compute_instance_v2.networks[count.index].id
  port_id     = openstack_networking_port_v2.baremetal_port[count.index + 1].id
}

# NOTE(aruan) Ironic deploys these instances: the image only sets their firmware, and
# tofu must not fight Ironic over their power state
resource "openstack_compute_instance_v2" "baremetal" {
  count       = var.baremetal_count
  name        = "${terraform.workspace}-baremetal-${count.index}"
  image_name  = var.baremetal_firmware == "uefi" ? "Debian 13 - UEFI" : "Debian 13"
  flavor_name = var.baremetal_flavor
  network {
    port = openstack_networking_port_v2.baremetal_node_port[count.index].id
  }
  lifecycle {
    ignore_changes = [power_state]
  }
}


#
# Outputs
#

output "ssh_commands" {
  value = merge(
    { for idx, instance in openstack_compute_instance_v2.k8s : instance.name => "ssh root@${instance.access_ip_v4}" },
    { for idx, instance in openstack_compute_instance_v2.computes : instance.name => "ssh root@${instance.access_ip_v4}" },
    { for idx, instance in openstack_compute_instance_v2.networks : instance.name => "ssh root@${instance.access_ip_v4}" }
  )
  description = "SSH commands (make sure you loaded the 'zob' key in your ssh-agent)"
}
