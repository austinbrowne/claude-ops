#!/usr/bin/env bash
set -euo pipefail

# Tech Lead: Weekly architecture review
# Schedule: Friday at 3:00 PM
# Cron: 0 15 * * 5 /Users/austin/Git_Repos/claude-ops/jobs/tech-lead-review.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${SCRIPT_DIR}/scripts/dispatch.sh" \
  --role tech-lead \
  --target claude-agent-protocol \
  --timeout 900 \
  --task "Weekly architecture review.
1. Review all commits from the past week: git log --oneline --since='7 days ago'
2. Check for architectural concerns:
   a. New dependencies added? Review justification
   b. New patterns introduced? Are they consistent with existing conventions?
   c. Growing complexity? Any files over 500 lines that should be split?
   d. Test coverage gaps? New code without tests?
3. Review any open plans in docs/plans/ — comment on architectural risks
4. Check docs/solutions/ for recurring problems that suggest architectural issues
5. If you identify architectural concerns, comment on relevant PRs or file issues with 'architecture' and 'tech-debt' labels
6. Summarize: what's good, what's concerning, and any recommended actions"
