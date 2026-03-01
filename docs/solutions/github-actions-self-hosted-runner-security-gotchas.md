---
title: "GitHub Actions self-hosted runner security gotchas"
date: 2026-03-01
category: security
tags: [github-actions, self-hosted-runner, workflow-dispatch, contains, toJSON, fork-pr, defense-in-depth]
severity: high
confidence: high
---

# GitHub Actions Self-Hosted Runner Security Gotchas

Three gotchas discovered during implementation and fresh-eyes review of GitHub Actions workflows for self-hosted Claude Code automation.

## Gotcha 1: toJSON() + contains() Is Substring Matching

### Problem

`contains(toJSON(github.event.issue.labels.*.name), 'needs_refinement')` performs **substring matching**, not exact matching. A label named `needs_refinement_v2` would also match, bypassing the intended guard.

### Root Cause

`toJSON()` serializes the labels array to a JSON string like `["needs_refinement","ready_for_dev"]`. `contains()` then performs a substring search on that string. The string `'needs_refinement'` is a substring of `'needs_refinement_v2'`.

### Fix

Embed quotes in the search string to match the JSON-serialized exact value:

```yaml
# BROKEN — substring match
if: >-
  !contains(toJSON(github.event.issue.labels.*.name), 'needs_refinement')

# FIXED — exact match via embedded quotes
if: >-
  !contains(toJSON(github.event.issue.labels.*.name), '"needs_refinement"')
```

The embedded `"` characters match the JSON-serialized format exactly: `"needs_refinement"` as a complete JSON string element.

### Caveat

This relies on `toJSON()` producing compact JSON without whitespace. GitHub currently does this, but it's not formally guaranteed. For truly robust matching, consider a dedicated step that iterates labels via `github.event.issue.labels` array.

---

## Gotcha 2: Fork PRs on Self-Hosted Runners

### Problem

`pull_request` trigger on a self-hosted runner allows fork-based PRs to execute arbitrary code on the runner machine. Even with a private repo (where forks are restricted), this is a defense-in-depth concern because repo visibility can change.

### Fix

Add a fork check to the job condition:

```yaml
jobs:
  review:
    if: >-
      github.event.pull_request.draft == false &&
      github.event.pull_request.head.repo.fork == false
```

### Why Even for Private Repos

The plan mandates a private-repo hard gate, but:
- Someone could change repo visibility to public later
- API-created repos might default differently
- A single `if:` line costs nothing and prevents a catastrophic RCE scenario

---

## Gotcha 3: workflow_dispatch `required: true` Only Enforced in UI

### Problem

`workflow_dispatch` inputs with `required: true` are validated in the GitHub UI but **not enforced via the REST API** (`POST /repos/.../actions/workflows/.../dispatches`). API callers can omit required fields or send empty/whitespace-only values.

### Fix

Always validate inputs in workflow steps, even if marked `required: true`:

```yaml
steps:
  - name: Validate inputs
    env:
      TASK_INPUT: ${{ github.event.inputs.task }}
    run: |
      TASK_TRIMMED=$(echo "$TASK_INPUT" | xargs)
      if [ -z "$TASK_TRIMMED" ]; then
        echo "ERROR: task description is empty or whitespace-only"
        exit 1
      fi
```

### Additional Notes

- `type: choice` inputs ARE validated even via API (server rejects unknown values)
- Numeric range validation (e.g., timeout 60-3600) must also be done in steps
- All inputs should be passed via `env:` variables, never direct `${{ }}` in `run:` blocks (shell injection vector)

---

## Applicability

Any GitHub Actions setup using self-hosted runners, especially for autonomous CI/CD, LLM orchestration, or headless automation where security boundaries are critical.
