# Rescheduling-Safe K3s Drain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent full-cluster Terraform maintenance drains from repeatedly rescheduling workloads and overloading the single-node K3s control plane.

**Architecture:** Extend the existing drain step rather than adding another workflow or script. Cordon every node first, then drain workers and the control-plane sequentially with direct pod deletion so workloads remain Pending until the existing recovery job uncordons the cluster.

**Tech Stack:** GitHub Actions YAML, POSIX shell, `kubectl`, Terraform CI, GitHub CLI.

## Global Constraints

- Change only `.github/workflows/apply.yml` plus the design and plan documents committed on this branch.
- Keep the existing worker/control-plane classification.
- Cordon every worker and control-plane node before the first drain.
- Preserve worker-first, control-plane-last drain order.
- Add `--disable-eviction` to both drain commands because all nodes are intentionally unschedulable and live PDBs cannot preserve availability during a full-cluster reboot.
- Keep the existing 120-second per-node drain timeout.
- Keep API wait, uncordon, Ready wait, saved-plan apply, Ansible dispatch, and cleanup behavior unchanged.
- Do not change Terraform resources, K3s tuning, OPNsense, Ansible, Kubernetes workloads, or application manifests.
- The PR plan must remain exactly three in-place `ipconfig0` and `ipconfig1` gateway updates with `0 add, 3 change, 0 destroy`.

---

### Task 1: Prevent drain-time rescheduling

**Files:**
- Modify: `.github/workflows/apply.yml:135-159`
- Test temporarily: `/home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-rescheduling.sh`

**Interfaces:**
- Consumes: Existing `WORKERS` and `MASTERS` node lists from the drain step.
- Produces: A fully cordoned cluster before any pod deletion and sequential deletion-based drains.

- [ ] **Step 1: Write the failing workflow check**

Create `/home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-rescheduling.sh` with:

```sh
#!/bin/sh
set -eu

workflow=${1:-.github/workflows/apply.yml}

grep -Fq 'for node in $WORKERS $MASTERS; do' "$workflow"
grep -Fq 'kubectl cordon "$node"' "$workflow"

cordon_line=$(grep -n 'kubectl cordon "$node"' "$workflow" | cut -d: -f1)
worker_line=$(grep -n 'echo "🔄 Draining worker $node..."' "$workflow" | cut -d: -f1)
master_line=$(grep -n 'echo "🔄 Draining master $node..."' "$workflow" | cut -d: -f1)

test "$cordon_line" -lt "$worker_line"
test "$worker_line" -lt "$master_line"
test "$(grep -c -- '--disable-eviction' "$workflow")" -eq 2

echo "rescheduling-safe drain checks passed"
```

- [ ] **Step 2: Run the check and confirm the current workflow fails**

Run:

```bash
cd /home/ben/Developer/homelab/terraform/.worktrees/k3s-main-egress
sh /home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-rescheduling.sh
```

Expected: exit code `1` because the workflow does not yet cordon all nodes before draining.

- [ ] **Step 3: Implement the minimal workflow change**

Insert this block after node classification and before the worker drain loop:

```sh
          for node in $WORKERS $MASTERS; do
            echo "⏸️ Cordoning $node..."
            kubectl cordon "$node"
          done
```

Change both drain commands to:

```sh
kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --disable-eviction --timeout=120s
```

- [ ] **Step 4: Run the workflow check and whitespace validation**

Run:

```bash
cd /home/ben/Developer/homelab/terraform/.worktrees/k3s-main-egress
sh /home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-rescheduling.sh
terraform fmt -check -recursive
git diff --check
```

Expected:

```text
rescheduling-safe drain checks passed
```

All commands must exit `0`.

- [ ] **Step 5: Review and commit the exact change**

Run:

```bash
git diff -- .github/workflows/apply.yml
git status --short
git add .github/workflows/apply.yml
git commit \
  -m "fix: prevent k3s drain rescheduling" \
  -m "Cordon the full cluster before deletion-based maintenance drains so workloads cannot bounce between nodes and overload etcd." \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected: one commit modifying only `.github/workflows/apply.yml`.

### Task 2: Review and publish the final retry PR

**Files:**
- Review: `.github/workflows/apply.yml`
- Review: `docs/superpowers/specs/2026-09-01-k3s-drain-rescheduling-design.md`
- Review: `docs/superpowers/plans/2026-09-01-k3s-drain-rescheduling.md`

**Interfaces:**
- Consumes: Task 1's committed maintenance-drain change.
- Produces: A follow-up PR carrying a saved Terraform plan for the still-pending route update.

- [ ] **Step 1: Run final branch checks**

Run:

```bash
cd /home/ben/Developer/homelab/terraform/.worktrees/k3s-main-egress
terraform fmt -check -recursive
git diff --check origin/main...HEAD
sh /home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-rescheduling.sh
```

Expected: all commands exit `0`; the workflow check prints `rescheduling-safe drain checks passed`.

- [ ] **Step 2: Request a read-only review**

Review `origin/main...HEAD` against the design. The review must verify pre-cordon ordering, both `--disable-eviction` flags, unchanged recovery/apply behavior, and the absence of unrelated configuration changes.

Expected: no unresolved Critical or Important issue.

- [ ] **Step 3: Push and create the PR**

Run:

```bash
git push -u origin fix/k3s-drain-rescheduling
gh pr create \
  --repo Starktastic-Homelab/terraform \
  --base main \
  --head fix/k3s-drain-rescheduling \
  --title "Prevent K3s drain rescheduling storm" \
  --body "$(printf '%s\n' \
    '## Summary' \
    '' \
    '- Cordon every K3s node before the first maintenance drain.' \
    '- Use deletion-based drain so PDBs do not deadlock an intentionally full-cluster reboot.' \
    '- Keep worker-first/control-plane-last ordering and the existing recovery path.' \
    '' \
    '## Evidence' \
    '' \
    'The prior run scheduled 61 replacement pods while moving from worker-01 to worker-02, then evicted them again. Embedded etcd reads stalled for 19.7 seconds and K3s exited after losing leadership.' \
    '' \
    '## Required plan gate' \
    '' \
    '- Exactly three in-place `proxmox_vm_qemu` updates.' \
    '- `ipconfig0` loses `gw=10.9.9.1` and `ipconfig1` gains `gw=10.9.8.1` on each node.' \
    '- `0 add, 3 change, 0 destroy`; no replacement or unrelated drift.' \
    '' \
    '## Rollback' \
    '' \
    'Any pre-apply failure uses the existing API-aware uncordon recovery. Revert this PR to restore eviction-based draining.' \
    '' \
    '## Pre-apply actions' \
    '' \
    '> [!WARNING]' \
    '> Selecting a destructive action requires checking the confirmation box.' \
    '> Drain and destroy are mutually exclusive.' \
    '' \
    '- [x] Drain cluster nodes before apply' \
    '- [ ] Destroy and recreate infrastructure before apply' \
    '- [x] I confirm the destructive action selected above')"
```

Expected: a new PR URL in `Starktastic-Homelab/terraform`.

- [ ] **Step 4: Enforce checks and the Terraform plan gate**

Run:

```bash
PR_NUMBER=$(gh pr list \
  --repo Starktastic-Homelab/terraform \
  --head fix/k3s-drain-rescheduling \
  --state open \
  --json number \
  --jq '.[0].number')
gh pr checks "$PR_NUMBER" --repo Starktastic-Homelab/terraform --watch --fail-fast
gh api "repos/Starktastic-Homelab/terraform/issues/$PR_NUMBER/comments" \
  --paginate \
  --jq '[.[] | select(.user.login == "github-actions[bot]" and (.body | contains("Plan:")))] | last | .body'
```

Expected: all checks pass; the plan contains only three in-place gateway updates and `Plan: 0 to add, 3 to change, 0 to destroy.`

- [ ] **Step 5: Remove the temporary workflow check**

Delete `/home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-rescheduling.sh`.

Expected: the session artifact is absent and the repository remains clean.

### Task 3: Verify the corrected maintenance rollout

**Files:**
- Read-only runtime verification; no repository changes.

**Interfaces:**
- Consumes: The user's merge of the follow-up PR.
- Produces: Evidence that the maintenance drain avoids scheduling churn and the route update reaches every node.

- [ ] **Step 1: Monitor the merged apply workflow**

Run:

```bash
RUN_ID=$(gh run list \
  --repo Starktastic-Homelab/terraform \
  --workflow apply.yml \
  --event pull_request_target \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')
gh run watch "$RUN_ID" --repo Starktastic-Homelab/terraform --exit-status
```

Expected: all nodes are cordoned before `kube-worker-01` drains; drain order is worker-01, worker-02, control-plane; Terraform apply and recovery succeed.

- [ ] **Step 2: Confirm drain produced no replacement scheduling**

Run:

```bash
gh run view "$RUN_ID" --repo Starktastic-Homelab/terraform --log > /tmp/k3s-maintenance-run.log
CORDONED_AT=$(awk -F '\t' '/Cordoning / { timestamp=$3 } END { print timestamp }' /tmp/k3s-maintenance-run.log)
APPLY_AT=$(awk -F '\t' '$1 == "Terraform apply" { print $3; exit }' /tmp/k3s-maintenance-run.log)
kubectl get events -A -o json | jq \
  --arg start "$CORDONED_AT" \
  --arg end "$APPLY_AT" \
  '[.items[]
    | (.eventTime // .lastTimestamp // .metadata.creationTimestamp) as $timestamp
    | select(.reason == "Scheduled" and $timestamp >= $start and $timestamp < $end)
    | {
        timestamp: $timestamp,
        namespace: .metadata.namespace,
        pod: .involvedObject.name,
        message: .message
      }
  ] | {count: length, events: .}'
rm -f /tmp/k3s-maintenance-run.log
```

Expected:

```json
{
  "count": 0,
  "events": []
}
```

No workloads may be scheduled after the last initial cordon and before Terraform apply begins.

- [ ] **Step 3: Verify cluster health and routes**

Run:

```bash
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,SCHEDULING_DISABLED:.spec.unschedulable'
kubectl -n media get pods -l 'app.kubernetes.io/name in (qbittorrent,qbittorrent-ru)' -o wide
```

Expected: every node is Ready and schedulable; both qBittorrent pods are Running. Host network namespaces must show:

```text
default via 10.9.8.1 dev eth1
```

- [ ] **Step 4: Verify qBittorrent uses MAIN egress**

Derive the normal qBittorrent pod's current worker and MAIN IP, capture a live peer connection, and correlate it to OPNsense PF state data.

Expected: the flow is SNATed to `10.9.8.51` or `10.9.8.52` according to live placement and matches OPNsense's MAIN `WAN_BALANCE` policy.
