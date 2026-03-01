#!/usr/bin/env bash
set -euo pipefail

# PM Morning Triage
# Schedule: Daily at 9:00 AM
# Cron: 0 9 * * * /Users/austin/Git_Repos/claude-ops/jobs/pm-triage.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${SCRIPT_DIR}/scripts/dispatch.sh" \
  --role product-manager \
  --target claude-agent-protocol \
  --task "Morning triage: Review all open GitHub issues. For each issue:
1. If it has the 'needs_refinement' label, run /explore to understand the context, then enhance the issue with acceptance criteria, affected files, and implementation notes. Remove 'needs_refinement' and add 'ready_for_dev'.
2. If it's a new issue without labels, categorize it (bug/feature), add priority label (priority:high/medium/low), and add 'needs_refinement' if it lacks detail.
3. Check for stale issues (no activity in 14+ days) — comment asking if still relevant.
4. Summarize: list issues triaged, labels applied, and any that need human attention."
