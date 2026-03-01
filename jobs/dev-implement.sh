#!/usr/bin/env bash
set -euo pipefail

# Developer: Pick and implement next issue
# Schedule: Daily at 11:00 AM (after PM triage)
# Cron: 0 11 * * * /Users/austin/Git_Repos/claude-ops/jobs/dev-implement.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${SCRIPT_DIR}/scripts/dispatch.sh" \
  --role developer \
  --target claude-agent-protocol \
  --timeout 900 \
  --task "Implement the next ready issue.
1. List issues labeled 'ready_for_dev': gh issue list --label ready_for_dev --state open --json number,title,labels --limit 5
2. Pick the highest priority issue (priority:high > priority:medium > priority:low, then oldest first)
3. If no ready issues exist, output 'No ready issues. Waiting for PM triage.' and stop.
4. For the selected issue:
   a. Create a feature branch: git checkout -b feat/issue-<number>-<short-slug>
   b. Run /implement (start-issue) with the issue number
   c. Write tests for all code changes
   d. Run tests to verify they pass
   e. Commit with conventional message: feat: <description> (closes #<number>)
   f. Push the branch: git push -u origin <branch-name>
   g. Create a PR: gh pr create --title '<title>' --body '<body with issue link>'
   h. Add label 'needs_review' to the PR
5. Only implement ONE issue per run. Do not start a second issue."
