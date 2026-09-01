# K3s Control-Plane Drain Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing Terraform drain/apply workflow recognize K3s control-plane nodes and reliably restore scheduling after transient Kubernetes API outages.

**Architecture:** Keep orchestration inside the existing `.github/workflows/apply.yml`. Correct its node-role predicate, then make post-apply recovery wait for the API, uncordon all nodes, and only then wait for Ready so a readiness failure cannot leave nodes cordoned.

**Tech Stack:** GitHub Actions YAML, POSIX shell, `kubectl`, Terraform CI, GitHub CLI.

## Global Constraints

- Change only `.github/workflows/apply.yml` plus the design and plan documents already committed on this branch.
- Recognize both `node-role.kubernetes.io/master` and `node-role.kubernetes.io/control-plane`.
- Preserve worker-first, control-plane-last drain order.
- Bound Kubernetes API recovery to 60 attempts at five-second intervals.
- Uncordon nodes before the final Ready wait.
- Keep saved-plan, Terraform apply, Ansible dispatch, and cleanup behavior unchanged.
- Do not change Terraform resources, routes, OPNsense, Ansible, Kubernetes workloads, or application manifests.
- The PR plan must remain `0 add, 3 change, 0 destroy`, changing only the approved `ipconfig0` and `ipconfig1` values.

---

### Task 1: Correct drain classification and recovery

**Files:**
- Modify: `.github/workflows/apply.yml:122-153`
- Modify: `.github/workflows/apply.yml:249-276`
- Test temporarily: `/home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-workflow.sh`

**Interfaces:**
- Consumes: Kubernetes node labels returned by `kubectl get node`, and the existing `post-apply` job.
- Produces: Correct worker/control-plane drain ordering and bounded post-apply scheduling recovery.

- [ ] **Step 1: Write the failing workflow check**

Create `/home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-workflow.sh` with:

```sh
#!/bin/sh
set -eu

workflow=${1:-.github/workflows/apply.yml}
pattern='"node-role.kubernetes.io/(master|control-plane)"'

grep -Fq 'grep -qE' "$workflow"
grep -Fq 'node-role.kubernetes.io/(master|control-plane)' "$workflow"

printf '%s\n' '{"node-role.kubernetes.io/control-plane":"true"}' | grep -qE "$pattern"
printf '%s\n' '{"node-role.kubernetes.io/master":"true"}' | grep -qE "$pattern"
if printf '%s\n' '{"node-role.kubernetes.io/worker":"true"}' | grep -qE "$pattern"; then
  exit 1
fi

api_line=$(grep -n 'name: Wait for Kubernetes API' "$workflow" | cut -d: -f1)
uncordon_line=$(grep -n 'name: Uncordon all nodes' "$workflow" | cut -d: -f1)
ready_line=$(grep -n 'name: Wait for nodes to be ready' "$workflow" | cut -d: -f1)

test "$api_line" -lt "$uncordon_line"
test "$uncordon_line" -lt "$ready_line"
grep -Fq 'until kubectl get nodes >/dev/null 2>&1; do' "$workflow"
grep -Fq 'if [ "$attempts" -ge 60 ]; then' "$workflow"

echo "drain workflow checks passed"
```

- [ ] **Step 2: Run the check and confirm the current workflow fails**

Run:

```bash
cd /home/ben/Developer/homelab/terraform/.worktrees/k3s-main-egress
sh /home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-workflow.sh
```

Expected: exit code `1` because the current workflow has no combined `master|control-plane` matcher or API-recovery step.

- [ ] **Step 3: Implement the minimal workflow change**

Replace the node-role predicate with:

```sh
if kubectl get node "$node" -o jsonpath='{.metadata.labels}' | grep -qE '"node-role.kubernetes.io/(master|control-plane)"'; then
```

Replace the current post-apply Ready-wait and uncordon ordering with:

```yaml
      - name: Wait for Kubernetes API
        run: |
          attempts=0
          until kubectl get nodes >/dev/null 2>&1; do
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 60 ]; then
              echo "Kubernetes API did not recover within 300 seconds."
              exit 1
            fi
            sleep 5
          done

      - name: Uncordon all nodes
        run: |
          for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
            echo "✅ Uncordoning $node..."
            kubectl uncordon "$node"
          done

      - name: Wait for nodes to be ready
        run: kubectl wait --for=condition=Ready nodes --all --timeout=300s
```

- [ ] **Step 4: Run the workflow check and confirm it passes**

Run:

```bash
cd /home/ben/Developer/homelab/terraform/.worktrees/k3s-main-egress
sh /home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-workflow.sh
git diff --check
```

Expected:

```text
drain workflow checks passed
```

Both commands must exit `0`.

- [ ] **Step 5: Review the exact diff**

Run:

```bash
git diff -- .github/workflows/apply.yml
git status --short
```

Expected: only `.github/workflows/apply.yml` is modified beyond the already committed design and plan documents.

- [ ] **Step 6: Commit the workflow fix**

Run:

```bash
git add .github/workflows/apply.yml
git commit \
  -m "fix: handle k3s control-plane drain" \
  -m "Recognize current K3s control-plane labels and recover scheduling after transient API outages." \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Expected: one commit modifying only `.github/workflows/apply.yml`.

### Task 2: Review and publish the retry PR

**Files:**
- Review: `.github/workflows/apply.yml`
- Review: `docs/superpowers/specs/2026-09-01-k3s-control-plane-drain-design.md`
- Review: `docs/superpowers/plans/2026-09-01-k3s-control-plane-drain.md`

**Interfaces:**
- Consumes: Task 1's committed workflow fix.
- Produces: A follow-up PR whose saved Terraform plan can safely retry the pending route change.

- [ ] **Step 1: Run repository checks**

Run:

```bash
terraform fmt -check -recursive
git diff --check origin/main...HEAD
sh /home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-workflow.sh
```

Expected: all commands exit `0` and the workflow check prints `drain workflow checks passed`.

- [ ] **Step 2: Request a read-only review**

Review `origin/main...HEAD` against the design. Reject any suggestion that adds a new workflow, script abstraction, dependency, or manual infrastructure step without an observed need.

Expected: no unresolved Critical or Important issue.

- [ ] **Step 3: Push and create the PR**

Run:

```bash
git push -u origin fix/k3s-control-plane-drain
gh pr create \
  --repo Starktastic-Homelab/terraform \
  --base main \
  --head fix/k3s-control-plane-drain \
  --title "Fix K3s control-plane drain recovery" \
  --body "$(printf '%s\n' \
    '## Summary' \
    '' \
    '- Recognize both current and legacy Kubernetes control-plane labels.' \
    '- Wait for the Kubernetes API, uncordon all nodes, then wait for Ready.' \
    '- Retry the still-pending MAIN gateway rollout through the existing saved-plan workflow.' \
    '' \
    '## Required plan gate' \
    '' \
    '- Exactly three in-place `proxmox_vm_qemu` updates.' \
    '- `ipconfig0` loses `gw=10.9.9.1` and `ipconfig1` gains `gw=10.9.8.1` on each node.' \
    '- `0 add, 3 change, 0 destroy`; no replacement or unrelated drift.' \
    '' \
    '## Rollback' \
    '' \
    'If pre-apply fails, the recovery job uncordons nodes after API recovery. If routing applies incorrectly, revert the gateway PR through this corrected workflow.' \
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

- [ ] **Step 4: Enforce the CI plan gate**

Run:

```bash
PR_NUMBER=$(gh pr list \
  --repo Starktastic-Homelab/terraform \
  --head fix/k3s-control-plane-drain \
  --state open \
  --json number \
  --jq '.[0].number')
gh pr checks "$PR_NUMBER" --repo Starktastic-Homelab/terraform --watch --fail-fast
gh pr view "$PR_NUMBER" --repo Starktastic-Homelab/terraform --comments
```

Expected: all checks pass; the plan shows only the three approved in-place `ipconfig0`/`ipconfig1` updates and `Plan: 0 to add, 3 to change, 0 to destroy.`

- [ ] **Step 5: Remove the temporary workflow check**

Delete:

```text
/home/ben/.copilot/session-state/a8ee7658-df01-4917-a62e-dea480359efd/files/test-drain-workflow.sh
```

Expected: the session artifact is removed; no repository file changes.

### Task 3: Verify the corrected rollout after merge

**Files:**
- Read-only runtime verification; no repository changes.

**Interfaces:**
- Consumes: The user's merge of the follow-up PR.
- Produces: Evidence that the route change applied and qBittorrent now exits through MAIN.

- [ ] **Step 1: Monitor the Terraform apply workflow**

Run:

```bash
gh run list --repo Starktastic-Homelab/terraform --workflow apply.yml --limit 5
RUN_ID=$(gh run list \
  --repo Starktastic-Homelab/terraform \
  --workflow apply.yml \
  --event pull_request_target \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')
gh run watch "$RUN_ID" --repo Starktastic-Homelab/terraform --exit-status
```

Expected drain order: `kube-worker-01`, `kube-worker-02`, then `kube-master-01`. Expected Terraform result: three in-place updates and no replacement or destroy.

- [ ] **Step 2: Verify cluster recovery**

Run:

```bash
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl get nodes -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,SCHEDULING_DISABLED:.spec.unschedulable'
kubectl -n media get pods -l 'app.kubernetes.io/name in (qbittorrent,qbittorrent-ru)' -o wide
```

Expected: all nodes are Ready and schedulable; both qBittorrent pods are Running.

- [ ] **Step 3: Verify host default routes**

Use each node's running Falco pod to enter `/host/proc/1/ns/net` and read the host routing table.

Expected on every node:

```text
default via 10.9.8.1 dev eth1
```

- [ ] **Step 4: Verify qBittorrent egress identity**

Capture a new normal-qBittorrent peer flow, then correlate it with OPNsense PF state data.

Expected:

```text
pod 10.42.x.x -> scheduled worker MAIN 10.9.8.51 or 10.9.8.52 -> OPNsense MAIN rule -> WAN_BALANCE
```

Derive the worker from the live pod placement. At least one active PF state must show that worker's MAIN source identity; the existing dual-WAN proof remains separate.
