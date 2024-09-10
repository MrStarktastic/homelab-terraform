locals {
  cluster_vip_host_number = parseint(regex("(\\d+)\\/", var.cluster_vip)[0], 10)
  all_configs = concat(
    [for i in range(var.master_count) : merge({ name = "master-${format("%02s", i + 1)}" }, var.master_config)],
    [for i in range(var.worker_count) : merge({ name = "worker-${format("%02s", i + 1)}" }, var.worker_config)]
  )
}

resource "proxmox_vm_qemu" "kube_nodes" {
  count = var.master_count + var.worker_count

  vmid = var.vm_id_start + count.index
  name = "${var.name_prefix}-${local.all_configs[count.index].name}"
  desc = "Ubuntu-based k3s node"

  target_node = var.proxmox_target_node
  onboot      = true
  agent       = 1
  clone       = var.base_vm_name

  scsihw = var.scsi_controller

  os_type   = "cloud-init"
  ciuser    = var.username
  sshkeys   = sensitive(var.ssh_pub_key)
  ipconfig0 = "ip=${replace(var.cluster_vip, "/\\d+\\//", "${local.cluster_vip_host_number + count.index * 2 + 1}/")},gw=${var.gateway_ip}"
  ipconfig1 = "ip=${replace(var.cluster_vip, "/\\d+\\//", "${local.cluster_vip_host_number + count.index * 2 + 2}/")},gw=${var.gateway_ip}"

  cpu    = var.cpu
  cores  = local.all_configs[count.index].cores
  memory = local.all_configs[count.index].memory

  dynamic "network" {
    for_each = var.network_bridges

    content {
      model  = "virtio"
      bridge = network.value
    }
  }

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.cloudinit_storage
        }
      }
    }

    virtio {
      virtio0 {
        disk {
          format   = "qcow2"
          size     = var.os_disk_size
          storage  = var.os_storage
          iothread = true
        }
      }
    }
  }

  tags = "k3s"
}
