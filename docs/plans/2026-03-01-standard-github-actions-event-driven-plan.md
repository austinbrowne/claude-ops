---
title: GitHub Actions Event-Driven Integration (Self-Hosted Runner)
tier: standard
status: approved
date: 2026-03-01
risk: HIGH
tags: [github-actions, event-driven, self-hosted-runner, automation, reactive]
---

# Plan: GitHub Actions Event-Driven Integration (Self-Hosted Runner)

## Problem

claude-ops relies entirely on cron-based scheduling. An issue labeled `ready_for_dev` at 11:01 waits until 15:00 for the next developer slot. The feedback loop is hours, not minutes. The infrastructure (Mac Mini, dispatch.sh, roles, budget tracking) is solid — only the triggering mechanism is wasteful.

## Goals

- React to GitHub events within minutes via GitHub Actions triggers
- Reuse the entire existing dispatch.sh infrastructure unchanged
- Mac Mini becomes an event-driven agent server, not just a cron server
- Unified budget/locking/logging across both trigger mechanisms
- No API credits required — same Max subscription

## Solution

Install a **GitHub Actions self-hosted runner** on the Mac Mini. Create workflow files in the target repository (claude-agent-protocol) that trigger on GitHub events and execute the existing job scripts on the Mac Mini. Cron schedules are reduced to low-frequency catch-up only.

### Architecture

```
GitHub Event (issue opened, PR created, label added)
  → GitHub Actions workflow fires
  → Runs on self-hosted runner (Mac Mini)
  → Calls existing jobs/*.sh script
  → dispatch.sh handles everything: role loading, locking, budget, claude -p, logging
  → Same state/invocations.jsonl, same state/budget-*.json, same logs/
```

### Why Self-Hosted

| Concern | Self-Hosted (Mac Mini) | GitHub-Hosted |
|---------|----------------------|---------------|
| Dispatch.sh reuse | Full — runs as-is | Must reimplement or ship |
| State persistence | Native — same filesystem | None — ephemeral |
| Cold start | None — claude already installed | ~2 min setup per run |
| Minutes quota | Unlimited (no consumption) | 2000 free/month |
| Authentication | Already authenticated | Needs secrets setup |
| Budget tracking | Unified cron + events | Separate tracking needed |
| Cost | $0.002/min platform fee (private repos only) | $0.008/min after free tier |

### Self-Hosted Runner Setup

1. Install the GitHub Actions runner on the Mac Mini following GitHub docs
2. Configure as a service (`./svc.sh install && ./svc.sh start`) so it survives reboots
3. Add labels: `claude-ops`, `macos`, `arm64`
4. Runner working directory: `~/actions-runner`

### Workflow-to-Job Mapping

| GitHub Event | Workflow File | Existing Job Script | Trigger |
|-------------|--------------|-------------------|---------|
| Issue opened | `claude-triage.yml` | `jobs/pm-triage.sh` | `issues: [opened]` |
| Issue labeled `needs_refinement` | `claude-enhance.yml` | `jobs/pm-enhance.sh` | `issues: [labeled]` + filter |
| Issue labeled `ready_for_dev` | `claude-implement.yml` | `jobs/dev-implement.sh` | `issues: [labeled]` + filter |
| PR opened/synchronized | `claude-review.yml` | `jobs/dev-review-prs.sh` | `pull_request: [opened, synchronize]` |
| Weekly (Fri 15:00) | `claude-tech-review.yml` | `jobs/tech-lead-review.sh` | `schedule` |
| Manual trigger | `claude-dispatch.yml` | `scripts/dispatch.sh` | `workflow_dispatch` with inputs |

### Concurrency Controls

Each workflow uses GitHub Actions `concurrency` groups:

```yaml
concurrency:
  group: claude-${{ github.workflow }}
  cancel-in-progress: false
```

**Important:** `cancel-in-progress: false` does NOT provide a true FIFO queue. GitHub Actions places additional runs in a "waiting" state, but execution order is not guaranteed and there is a platform limit on pending runs per concurrency group. This is acceptable because:
- Each job script uses polling guards that process ALL matching work (not just the triggering event)
- dispatch.sh's per-target mkdir locking provides the actual serialization guarantee
- If a run fires out of order, the polling guard still finds and processes the right work

**Concurrency roles:**
- **GitHub Actions concurrency groups** — prevent GitHub from dispatching multiple workflow runs simultaneously (platform-level)
- **dispatch.sh mkdir locking** — prevent parallel execution if the runner somehow runs two jobs (defense-in-depth)

### Cron Fallback Schedule (Reduced)

| Job | Current Schedule | Fallback Schedule | Rationale |
|-----|-----------------|-------------------|-----------|
| pm-triage | Daily 09:00 | Daily 09:00 | Catch issues without events (email/API-created) |
| pm-enhance | Daily 10:00 | Daily 22:00 | Evening catch-up for missed labels |
| dev-implement | 3x daily | Daily 22:00 | Evening catch-up only |
| dev-review | 3x daily | Daily 22:00 | Evening catch-up only |
| pm-explore | Mon 08:00 | Mon 08:00 | No change (no event trigger) |
| tech-lead-review | Fri 15:00 | Fri 15:00 | No change (schedule-only) |

Polling guards handle deduplication — if Actions processed the work, cron finds nothing and skips.

### Workflow Template

```yaml
name: "Claude: Triage New Issue"
on:
  issues:
    types: [opened]

concurrency:
  group: claude-pm-triage
  cancel-in-progress: false

permissions:
  contents: read
  issues: write

jobs:
  triage:
    runs-on: [self-hosted, claude-ops]
    timeout-minutes: 45
    steps:
      - name: Run PM Triage
        run: /Users/austin/Git_Repos/claude-ops/jobs/pm-triage.sh
        env:
          HOME: /Users/austin
          PATH: /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
      - name: Notify on failure
        if: failure()
        run: |
          echo "::error::Claude job failed: pm-triage on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
          echo "### Failed: PM Triage" >> "$GITHUB_STEP_SUMMARY"
          echo "Check workflow run logs for details." >> "$GITHUB_STEP_SUMMARY"
```

### Label-Filtered Workflows

```yaml
# claude-enhance.yml — triggers on needs_refinement label
jobs:
  enhance:
    runs-on: [self-hosted, claude-ops]
    if: github.event.label.name == 'needs_refinement'
    timeout-minutes: 45
    steps:
      - name: Run PM Enhance
        run: /Users/austin/Git_Repos/claude-ops/jobs/pm-enhance.sh
        env:
          HOME: /Users/austin
          PATH: /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
      - name: Notify on failure
        if: failure()
        run: echo "::error::Claude job failed: pm-enhance on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

```yaml
# claude-implement.yml — triggers on ready_for_dev label
# Skips if needs_refinement label is also present (enhancement not complete)
jobs:
  implement:
    runs-on: [self-hosted, claude-ops]
    if: >-
      github.event.label.name == 'ready_for_dev' &&
      !contains(toJSON(github.event.issue.labels.*.name), 'needs_refinement')
    timeout-minutes: 45
    steps:
      - name: Run Dev Implement
        run: /Users/austin/Git_Repos/claude-ops/jobs/dev-implement.sh
        env:
          HOME: /Users/austin
          PATH: /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
      - name: Notify on failure
        if: failure()
        run: echo "::error::Claude job failed: dev-implement on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

### Manual Dispatch Workflow

**Security note:** All `workflow_dispatch` inputs MUST be passed via `env:` variables, never directly in `${{ }}` expressions inside `run:` blocks. Direct `${{ }}` interpolation in `run:` is a shell injection vector — GitHub evaluates the expression before the shell runs, allowing arbitrary command injection via crafted input values.

```yaml
name: "Claude: Manual Dispatch"
on:
  workflow_dispatch:
    inputs:
      role:
        description: "Role to dispatch"
        required: true
        type: choice
        options: [product-manager, developer, code-reviewer, tech-lead]
      task:
        description: "Task description"
        required: true
        type: string
      timeout:
        description: "Timeout in seconds"
        required: false
        default: "600"
        type: string

jobs:
  dispatch:
    runs-on: [self-hosted, claude-ops]
    steps:
      - name: Validate timeout
        env:
          TIMEOUT_INPUT: ${{ github.event.inputs.timeout }}
        run: |
          if ! [[ "$TIMEOUT_INPUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT_INPUT" -lt 60 ] || [ "$TIMEOUT_INPUT" -gt 3600 ]; then
            echo "ERROR: timeout must be an integer between 60 and 3600"
            exit 1
          fi
      - name: Run Dispatch
        env:
          DISPATCH_ROLE: ${{ github.event.inputs.role }}
          DISPATCH_TASK: ${{ github.event.inputs.task }}
          DISPATCH_TIMEOUT: ${{ github.event.inputs.timeout }}
          HOME: /Users/austin
          PATH: /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
        run: |
          /Users/austin/Git_Repos/claude-ops/scripts/dispatch.sh \
            --role "$DISPATCH_ROLE" \
            --target claude-agent-protocol \
            --timeout "$DISPATCH_TIMEOUT" \
            --task "$DISPATCH_TASK"
```

## Implementation Steps

1. **Verify repo is private:** `gh repo view austinbrowne/claude-agent-protocol --json visibility` — ABORT if public
2. Install GitHub Actions self-hosted runner on Mac Mini
3. Configure runner as a launchd service (survives reboots)
4. Add runner labels: `self-hosted`, `claude-ops`
5. Create `.github/workflows/claude-triage.yml` in target repo
6. Create `.github/workflows/claude-enhance.yml` with label filter
7. Create `.github/workflows/claude-implement.yml` with label filter + `needs_refinement` guard
8. Create `.github/workflows/claude-review.yml` for PR events
9. Create `.github/workflows/claude-tech-review.yml` for weekly schedule
10. Create `.github/workflows/claude-dispatch.yml` for manual triggers (env var pattern, timeout validation)
11. Add `failure()` notification step to all workflows
12. Update `schedules/crontab` in claude-ops with reduced fallback frequency
13. Update `CLAUDE.md` to document the hybrid cron + Actions architecture
14. Test each workflow with real GitHub events (see Test Strategy)

## Affected Files

| File | Repository | Change |
|------|-----------|--------|
| `.github/workflows/claude-triage.yml` | claude-agent-protocol | NEW |
| `.github/workflows/claude-enhance.yml` | claude-agent-protocol | NEW |
| `.github/workflows/claude-implement.yml` | claude-agent-protocol | NEW |
| `.github/workflows/claude-review.yml` | claude-agent-protocol | NEW |
| `.github/workflows/claude-tech-review.yml` | claude-agent-protocol | NEW |
| `.github/workflows/claude-dispatch.yml` | claude-agent-protocol | NEW |
| `schedules/crontab` | claude-ops | MODIFY — reduced fallback frequency |
| `scripts/install.sh` | claude-ops | MODIFY — document hybrid setup |
| `CLAUDE.md` | claude-ops | MODIFY — document architecture |

## Acceptance Criteria

- [ ] Target repo verified as private before runner installation (`gh repo view --json visibility`)
- [ ] Self-hosted runner installed and running as a launchd service on Mac Mini
- [ ] Issue opened in target repo triggers triage workflow on Mac Mini
- [ ] Issue labeled `needs_refinement` triggers enhance workflow
- [ ] Issue labeled `ready_for_dev` triggers implement workflow
- [ ] Implement workflow skips if issue also has `needs_refinement` label
- [ ] PR opened triggers review workflow
- [ ] Weekly schedule triggers tech lead review
- [ ] Manual dispatch works with role selection and custom task
- [ ] Manual dispatch inputs pass through env vars (not direct `${{ }}` interpolation)
- [ ] Manual dispatch timeout validated as integer 60-3600
- [ ] Concurrency groups prevent parallel runs of the same role
- [ ] dispatch.sh locking works correctly when triggered by Actions
- [ ] Budget tracking counts both cron and Actions invocations in the same file
- [ ] Budget exhaustion causes clean failure (non-zero exit, logged)
- [ ] Each workflow has `failure()` notification step
- [ ] Per-workflow permissions match the Per-Workflow Permissions table
- [ ] Cron fallback runs at reduced frequency and skips when no work remains
- [ ] Runner survives Mac Mini reboot (launchd service)

## Test Strategy

**Core flows:**
- Create a test issue → verify triage workflow fires on Mac Mini
- Label issue `needs_refinement` → verify enhance fires
- Label issue `ready_for_dev` → verify implement fires
- Open PR → verify review fires
- Trigger manual dispatch via GitHub UI → verify correct role/task

**Concurrency and locking:**
- Open two issues simultaneously → verify concurrency serialization
- Trigger manual dispatch with invalid timeout ("abc", "99999") → verify validation rejects

**Resilience:**
- Reboot Mac Mini → verify runner restarts automatically via launchd
- Kill runner during job → verify dispatch.sh lock is cleaned up
- Force a job script to exit non-zero → verify failure notification step runs
- Run cron after Actions processed work → verify polling guard skips

**Edge cases:**
- Label issue with both `needs_refinement` and `ready_for_dev` → verify implement skips
- Check `state/invocations.jsonl` after Actions run → verify entries logged
- Trigger workflow when budget is exhausted → verify clean failure and log message

**Security:**
- Verify repo is private: `gh repo view --json visibility`
- Verify manual dispatch inputs do not appear in `run:` `${{ }}` expressions

## Security Review

### Hard Gates (must be true before installation)

- **Repo MUST be private.** Self-hosted runners execute code on the Mac Mini with full filesystem access. If the repo is public, any GitHub user can trigger `pull_request` events that run arbitrary code. Verify with `gh repo view --json visibility` before installing the runner. Add a cron check that alerts if visibility changes.
- **All `workflow_dispatch` inputs passed via `env:` variables** — never via direct `${{ }}` interpolation in `run:` blocks (shell injection vector).

### Accepted Security Model

- Runner executes on trusted hardware (Mac Mini) as the local user (`/Users/austin`)
- **No filesystem isolation** between runner and dispatch.sh state — the runner has full read/write access to `state/`, `logs/`, and the entire home directory. This is an accepted risk for a single-user, private-repo setup. If job scripts misbehave (bugs, prompt injection), they can read/modify any file the user owns.
- No API keys in workflow files — authentication handled by local `claude` CLI installation
- `--disallowedTools` (denylist) enforced by dispatch.sh. **Limitation:** denylist does not cover new tools added in future Claude Code versions. Review denylist when upgrading Claude Code.
- GitHub Actions `permissions` scoped to minimum per workflow (see Per-Workflow Permissions table below)
- Manual dispatch input (`task`) passes through dispatch.sh's XML-fenced prompt builder. **Limitation:** XML delimiting is defense-in-depth, not a complete prompt injection solution. Additional mitigations: `workflow_dispatch` task input is limited to 65535 characters by GitHub, and only repo collaborators can trigger it.
- **Workflow logs are uploaded to GitHub.** If job scripts output sensitive information (file paths, error messages, API responses), this data is stored on GitHub's servers. For a private repo this is acceptable, but be aware that `dispatch.sh` and Claude CLI output goes to workflow logs.

### Per-Workflow Permissions

| Workflow | Permissions Needed |
|----------|-------------------|
| claude-triage.yml | `contents: read`, `issues: write` |
| claude-enhance.yml | `contents: read`, `issues: write` |
| claude-implement.yml | `contents: write`, `issues: write`, `pull-requests: write` |
| claude-review.yml | `contents: read`, `pull-requests: write` |
| claude-tech-review.yml | `contents: read`, `issues: write` |
| claude-dispatch.yml | `contents: write`, `issues: write`, `pull-requests: write` |

## Past Learnings Applied

- **Prompt injection** — dispatch.sh wraps task text in `<task>` XML delimiters (defense-in-depth, not complete mitigation)
- **Git add -A risks** — dev-implement.sh task instructions specify `git add` on changed files only
- **disallowedTools** — dispatch.sh uses the working denylist approach, not the broken `--allowedTools` whitelist (GitHub issue #12232). Denylist limitation: new tools added in future Claude Code versions are allowed by default.
- **Shell injection in GitHub Actions** — all `workflow_dispatch` inputs passed via `env:` variables, never interpolated directly in `run:` blocks
- **Cross-validate parsed config** — read-only roles with empty disallowedTools abort to prevent silent privilege escalation

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Mac Mini offline > 24h → events dropped | Low | GitHub drops pending self-hosted runner jobs after 24 hours. Events permanently lost. | UPS + launchd auto-restart. Cron fallback catches remaining work when back online. Monitor runner uptime. |
| Mac Mini offline < 24h → burst on reconnect | Medium | All queued jobs fire at once, competing for locks | dispatch.sh locking serializes execution. First job wins lock, others exit with "locked" log. |
| Runner job hangs → blocks concurrency group | Low | Other events queue indefinitely | dispatch.sh timeout kills jobs; set `timeout-minutes` in each workflow |
| Label event storm (bulk labeling) | Low | Many jobs queue, each consuming budget | Concurrency groups serialize. dispatch.sh budget check exits non-zero when exhausted — remaining queued jobs fail and log "budget exceeded." |
| Workflow failure goes unnoticed | Medium | Failed event-driven job not retried until cron catch-up (up to 13h gap) | Add failure notification step to each workflow (see Failure Handling section) |
| Self-hosted runner security (public repo) | HIGH | Anyone can trigger workflows on your machine | **Hard gate:** repo MUST be private. Verify before installation. Add visibility change alerting. |
| Platform fee ($0.002/min) | Low | ~$0.06/30min job, negligible | Monitor; switch to public repo if costs matter |
| Runner path/env differs from user shell | Medium | Scripts fail due to missing tools | Set PATH/HOME explicitly in workflow env |
| `--disallowedTools` denylist gaps | Low | Future Claude Code tool additions allowed by default | Review denylist when upgrading Claude Code versions |

## Spec-Flow Analysis

### Flow 1: Issue Opened → Triage

```
Issue opened → GitHub event → Concurrency check (claude-pm-triage)
  → IF pending: wait (not a true FIFO queue) → IF free: proceed
  → Run pm-triage.sh → Polling guard checks open issues
    → Success: labels applied
    → Failure: workflow fails → failure notification step posts to logs
      → Cron catch-up at 09:00 retries
    → Timeout: dispatch.sh timeout kills agent → workflow fails
```

### Flow 2: Label Added → Enhance

```
Issue labeled needs_refinement → Filter: is label == needs_refinement?
  → IF no: skip (exit 0) → IF yes: proceed
  → Concurrency check (claude-enhance) → Run pm-enhance.sh
  → Polling guard checks for needs_refinement issues
    → Success: issue enhanced, labels updated
    → Failure: workflow fails → failure notification step logs error
      → Issue retains needs_refinement label (unchanged)
      → Cron catch-up at 22:00 retries (same polling guard finds it)
      → No ambiguous state — label unchanged means "still needs work"
```

### Flow 3: Label Added → Implement

```
Issue labeled ready_for_dev → Filter: is label == ready_for_dev?
  → IF no: skip (exit 0) → IF yes: proceed
  → Pre-check: IF issue also has needs_refinement label → skip (enhancement not complete)
  → Concurrency check (claude-implement) → Run dev-implement.sh
  → Polling guard verifies ready_for_dev issues exist
  → Creates branch, implements, self-reviews, creates PR
    → Success: PR created, branch pushed
    → Failure mid-implementation:
      → dispatch.sh timeout or error kills agent
      → Orphaned branch may exist (partial implementation)
      → Failure notification step logs which issue/branch was affected
      → Cron catch-up at 22:00: dev-implement.sh polling guard finds
        ready_for_dev issue still open, retries on a new branch
      → Orphaned branches accumulate — add periodic cleanup (manual or scripted)
    → Budget exhaustion: dispatch.sh exits non-zero → workflow fails
      → Remaining queued implement jobs also fail with budget error
      → Cron catch-up next day retries with refreshed budget
```

### Flow 4: PR Opened → Review

```
PR opened/synchronized → Concurrency check (claude-review)
  → Run dev-review-prs.sh → Polling guard checks open PRs
  → Fresh-eyes review → Approve / Request changes / Comment
    → If changes requested: author pushes fix → synchronize event
      → New review triggered (independent, fresh context)
    → Each review is stateless — no memory of previous review findings
```

**Edge case**: PR synchronized while review running → concurrency group places new run in waiting state. Not a true FIFO queue, but acceptable — the review job polls ALL open PRs regardless of which event triggered it.

### Failure Handling Pattern

Every workflow includes a failure notification step:

```yaml
    - name: Notify on failure
      if: failure()
      run: |
        echo "::error::Claude job failed: ${{ github.workflow }} on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "### ❌ ${{ github.workflow }} Failed" >> "$GITHUB_STEP_SUMMARY"
        echo "Check workflow run logs for details." >> "$GITHUB_STEP_SUMMARY"
```

This ensures failed jobs are visible in the GitHub Actions UI and step summaries. For now, GitHub's built-in email notifications for failed workflow runs provide alerting. A dedicated Slack/webhook notification can be added later if needed.
