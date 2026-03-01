#!/usr/bin/env bash
set -euo pipefail

# PM Weekly Exploration
# Schedule: Monday at 10:00 AM
# Cron: 0 10 * * 1 /Users/austin/Git_Repos/claude-ops/jobs/pm-explore.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${SCRIPT_DIR}/scripts/dispatch.sh" \
  --role product-manager \
  --target claude-agent-protocol \
  --task "Weekly exploration: Explore the codebase for improvement opportunities.
1. Run /explore to understand current state of the project
2. Review recent commits (last 7 days) for patterns and gaps
3. Check docs/plans/ for any stalled or incomplete plans
4. Check docs/solutions/ for recurring problem patterns
5. If you identify 2-3 high-value improvements, file them as GitHub issues with 'feature' and 'needs_refinement' labels
6. Focus on: developer experience, missing tests, documentation gaps, or workflow friction"
