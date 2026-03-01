#!/usr/bin/env bash
set -euo pipefail

# QA Review Open PRs
# Schedule: Daily at 2:00 PM
# Cron: 0 14 * * * /Users/austin/Git_Repos/claude-ops/jobs/qa-review-prs.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${SCRIPT_DIR}/scripts/dispatch.sh" \
  --role qa-engineer \
  --target claude-agent-protocol \
  --timeout 900 \
  --task "Review all open PRs.
1. List open PRs: gh pr list --state open
2. For each open PR that does NOT already have a review comment from you:
   a. Read the PR diff: gh pr diff <number>
   b. Run a fresh-eyes review focusing on: edge cases, error handling, security, test coverage
   c. Run shellcheck on any .sh files in the diff
   d. Post your findings as a PR comment: gh pr comment <number> --body '...'
   e. Classify the PR: APPROVE (no issues), NEEDS_WORK (has findings), BLOCK (critical issues)
3. If you find a bug that isn't covered by the PR, file it as a separate issue with 'bug' label
4. Summarize all PRs reviewed and their status"
