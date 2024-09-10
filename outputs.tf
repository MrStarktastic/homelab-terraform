output "server_private_ips" {
  value = [for i in range(var.master_count) : proxmox_vm_qemu.kube_nodes[i].ssh_host]
}

output "agent_private_ips" {
  value = [for i in range(var.master_count, var.master_count + var.worker_count) : proxmox_vm_qemu.kube_nodes[i].ssh_host]
}
