# K3s Control-Plane Drain Recovery Design

## Context

Terraform apply run `33491626964` stopped before Terraform because the drain workflow classified `kube-master-01` as a worker. K3s labels that node `node-role.kubernetes.io/control-plane` and `node-role.kubernetes.io/etcd`, while the workflow recognizes only the legacy `node-role.kubernetes.io/master` label.

Draining the control-plane node first made the Kubernetes API temporarily unavailable. The recovery job then ran a one-shot `kubectl wait`, failed immediately on `ServiceUnavailable`, and skipped uncordoning. Terraform was never applied; the cluster was restored manually and still routes through MGMT.

## Considered Approaches

1. **Retry the unchanged workflow:** rejected because it deterministically misclassifies the same node.
2. **Run Terraform without draining:** rejected because it bypasses the approved workload-safety step while rebooting all K3s VMs.
3. **Correct the existing workflow:** selected because it preserves the current PR-plan/apply process with the smallest persistent fix.

## Design

Change only `.github/workflows/apply.yml`:

- Treat either `node-role.kubernetes.io/master` or `node-role.kubernetes.io/control-plane` as a control-plane node.
- Keep the existing worker-first, control-plane-last drain order.
- In post-apply recovery, retry `kubectl get nodes` for up to five minutes while the API is unavailable.
- Once the API responds, uncordon every node before waiting for all nodes to become Ready. NotReady nodes are already unschedulable, while this ordering guarantees a later readiness timeout cannot leave healthy nodes cordoned.
- Keep the existing saved-plan, apply, Ansible-trigger, and cleanup behavior unchanged.

No Terraform resources, routes, OPNsense settings, Ansible roles, Kubernetes workloads, or application manifests change in this PR.

## Error Handling

- A drain or apply failure still enters the existing `always()` recovery job.
- If the API recovers within five minutes, all nodes are uncordoned and readiness is checked.
- If the API remains unavailable, the workflow fails explicitly after the bounded retry; operators can uncordon nodes after API recovery.
- Terraform apply remains blocked unless the drain completes successfully.

## Verification

- Reproduce that the old matcher rejects the live `control-plane` label.
- Verify the new matcher classifies both `master` and `control-plane` labels as control-plane nodes.
- Run the repository's existing formatting checks and workflow CI.
- Require the follow-up PR plan to remain `0 add, 3 change, 0 destroy`, with only the approved `ipconfig0` and `ipconfig1` updates.
- After merge, confirm workers drain before the control-plane node, all nodes return Ready and schedulable, and each host uses `default via 10.9.8.1 dev eth1`.
- Confirm new qBittorrent egress is SNATed from its scheduled worker's MAIN address (`10.9.8.51` or `10.9.8.52`) and matches OPNsense's MAIN `WAN_BALANCE` rule.

## Rollback

Revert the workflow PR if its orchestration changes are undesirable. If the route has already applied and must be reversed, revert the gateway PR through the corrected drain workflow.
