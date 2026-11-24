variable "k8s_flavor" {
  description = "Flavor of the k8s node"
  type        = string
  default     = "r3-64"
}

variable "compute_flavor" {
  description = "Flavor of the compute nodes"
  type        = string
  default     = "r3-64"
}

variable "network_flavor" {
  description = "Flavor of the network nodes"
  type        = string
  default     = "r3-64"
}

variable "baremetal_count" {
  description = "Number of instances acting as Ironic bare metal nodes (0 disables the bare metal part)"
  type        = number
  default     = 0
}

variable "baremetal_flavor" {
  description = "Flavor of the bare metal nodes (the Ironic agent ramdisk needs at least 4GB of RAM)"
  type        = string
  default     = "r3-64"
}

variable "baremetal_firmware" {
  description = "Firmware of the bare metal nodes: bios or uefi, set by the image they are created from"
  type        = string
  default     = "uefi"
  validation {
    condition     = contains(["bios", "uefi"], var.baremetal_firmware)
    error_message = "baremetal_firmware must be bios or uefi."
  }
}

variable "baremetal_credential_expiry_days" {
  description = "Lifetime in days of the application credential used by sushy-emulator (0: no expiry, tofu destroy deletes it)"
  type        = number
  default     = 0
}

variable "auth_url" {
  description = "Keystone URL of the cloud hosting the cluster, given to sushy-emulator with its application credential"
  type        = string
  default     = "https://auth.cloud.ovh.net/v3"
}
