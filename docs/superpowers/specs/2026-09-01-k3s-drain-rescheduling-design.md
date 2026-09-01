# Rescheduling-Safe K3s Drain Design

## Context

Terraform apply run `33494170275` used the corrected node-role classification and drained `kube-worker-01` first. Kubernetes immediately scheduled 61 replacement pods onto `kube-worker-02` and `kube-master-01`; normal qBittorrent moved from worker-01 to worker-02.

The workflow then drained worker-02, forcing those replacements through another eviction cycle. Embedded etcd reads stalled for up to 19.7 seconds, the cloud-controller-manager lease renewal exceeded its deadline, and K3s exited after `leaderelection lost`. K3s restarted twice, including a later `leaderelection lost for k3s-etcd`. Terraform did not run, while the recovery job successfully restored every node to schedulable.

The existing 60-second lease and 45-second renewal tuning is active. The master disk's known etcd latency remains the hardware limitation; this design removes the avoidable scheduling burst that triggered it.

## Considered Approaches

1. **Increase timeouts again:** rejected because controller tuning is already extended and does not prevent etcd overload or its own leadership loss.
2. **Apply without draining:** rejected because it bypasses the approved workload-safety step before rebooting every K3s VM.
3. **Cordon all nodes before draining:** selected because it prevents workloads from bouncing between nodes during an intentionally cluster-wide maintenance window.

## Design

Change only `.github/workflows/apply.yml`:

- Keep the existing worker/control-plane classification.
- Cordon every worker and control-plane node before the first drain.
- Drain workers first and the control-plane last, as today.
- Add `--disable-eviction` to each drain command. With every node cordoned, replacement pods cannot become healthy, so the live PodDisruptionBudgets would otherwise block the full-cluster drain. Availability cannot be preserved while every VM is intentionally rebooted.
- Keep the existing 120-second per-node drain timeout.
- Keep the existing API wait, uncordon, Ready wait, saved-plan apply, Ansible dispatch, and cleanup behavior unchanged.

No Terraform resources, K3s tuning, OPNsense settings, Ansible roles, Kubernetes workloads, or application manifests change.

## Error Handling

- Terraform apply remains blocked unless every drain succeeds.
- Any drain or apply failure enters the existing recovery job, which waits for the API and uncordons all nodes.
- If the API remains unavailable beyond the existing bounded retry, the workflow fails explicitly and operators can uncordon after recovery.

## Verification

- A pre-change check must fail because no cordon-all phase or `--disable-eviction` flags exist.
- A post-change check must prove the cordon-all phase appears before the first drain and both drain commands use `--disable-eviction`.
- The follow-up PR plan must remain exactly three in-place `ipconfig0`/`ipconfig1` updates with `0 add, 3 change, 0 destroy`.
- During the merged run, all nodes must be cordoned before worker-01 starts draining, and no replacement pods should be scheduled between node drains.
- After apply, all nodes must be Ready and schedulable with `default via 10.9.8.1 dev eth1`.
- New qBittorrent traffic must use its scheduled worker's MAIN address and OPNsense MAIN `WAN_BALANCE` policy.

## Rollback

Revert this workflow PR to restore eviction-based drain behavior. If routing applies but must be reversed, revert the gateway PR through the corrected maintenance workflow.
