variable "master_count" {
  type = number
}

variable "worker_count" {
  type = number
}

variable "vm_id_start" {
  default = 200
}

variable "name_prefix" {
  default = "kube"
}

variable "proxmox_target_node" {
  default = "pve"
}

variable "base_vm_name" {
  type        = string
  description = "Received from Packer's build manifest"
}

variable "cluster_vip" {
  type        = string
  description = "Example: 192.168.1.100/32. Increments of this will be assigned to nodes."
}

variable "gateway_ip" {
  type = string
}

variable "username" {
  default = "ubuntu"
}

variable "cpu" {
  default = "x86-64-v2-AES"
}

variable "master_config" {
  default = {
    cores  = 1,
    memory = 4 * 1024
  }
}

variable "worker_config" {
  default = {
    cores  = 4
    memory = 24 * 1024
  }
}

variable "scsi_controller" {
  default = "virtio-scsi-single"
}

variable "cloudinit_storage" {
  default = "vm-disk-2"
}

variable "os_storage" {
  default = "vm-disk-2"
}

variable "os_disk_size" {
  default = "32G"
}

variable "network_bridges" {
  default = ["vmbr0", "vmbr1"]
}

variable "ssh_pub_key" {
  type = string
}
