# claude-ops

Autonomous agent orchestration system. Schedules and coordinates Claude Code CLI invocations across roles (PM, Developer, QA, Tech Lead) targeting repos that have the godmode protocol installed.

## Architecture

```
claude-ops/
├── config.json              # Target repos, budgets, notification settings
├── roles/                   # Agent persona definitions (prompt + tool restrictions)
│   ├── product-manager.md   # Read-only: triage, issues, roadmaps
│   ├── developer.md         # Read-write: implement, test, PR
│   ├── qa-engineer.md       # Read-only: review, test, report
│   └── tech-lead.md         # Read-only: architecture, plans, ADRs
├── jobs/                    # Cron job scripts (thin wrappers around dispatch.sh)
│   ├── pm-triage.sh         # Daily 9am: triage open issues
│   ├── pm-explore.sh        # Monday 10am: explore for opportunities
│   ├── dev-implement.sh     # Daily 11am: implement next ready issue
│   ├── qa-review-prs.sh     # Daily 2pm: review open PRs
│   └── tech-lead-review.sh  # Friday 3pm: architecture review
├── schedules/
│   └── crontab              # Master cron schedule
├── scripts/
│   ├── dispatch.sh          # Core dispatcher: loads role, invokes claude -p
│   ├── status.sh            # Dashboard: budget, locks, recent runs
│   └── log-cleanup.sh       # Weekly cleanup of old logs
├── state/                   # Runtime state (gitignored)
│   ├── budget-YYYY-MM-DD.json
│   ├── invocations.jsonl
│   └── locks/
└── logs/                    # Run logs (gitignored)
```

## Usage

```bash
# Manual dispatch
./scripts/dispatch.sh --role product-manager --target claude-agent-protocol --task "triage issues"

# Dry run (see prompt without invoking)
./scripts/dispatch.sh --role developer --target claude-agent-protocol --task "implement issue #5" --dry-run

# Check status
./scripts/status.sh

# Install cron schedule
crontab schedules/crontab

# Run a specific job manually
./jobs/pm-triage.sh
```

## Safety

- Per-target locking prevents concurrent agents on the same repo
- Daily invocation cap (configurable, default 20/day)
- Read-only roles (PM, QA, Tech Lead) cannot modify code
- Developer role cannot merge PRs or push to main
- All output logged for audit
- Stale lock detection with PID validation
