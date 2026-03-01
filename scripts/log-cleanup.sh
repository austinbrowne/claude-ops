#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# log-cleanup.sh — Remove old logs and budget files
#
# Schedule: Weekly (Sunday midnight)
# Cron: 0 0 * * 0 /Users/austin/Git_Repos/claude-ops/scripts/log-cleanup.sh
# ============================================================================

OPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${OPS_ROOT}/config.json"
STATE_DIR="${OPS_ROOT}/state"
LOG_DIR="${OPS_ROOT}/logs"

retention_days=$(jq -r '.defaults.log_retention_days // 7' "$CONFIG")

echo "[cleanup] Removing logs older than ${retention_days} days..."

# Clean old log files
find "$LOG_DIR" -name "*.log" -mtime "+${retention_days}" -delete 2>/dev/null || true
find "$LOG_DIR" -name "*.stderr" -mtime "+${retention_days}" -delete 2>/dev/null || true

# Clean old budget files (keep last 30 days regardless)
find "$STATE_DIR" -name "budget-*.json" -mtime +30 -delete 2>/dev/null || true

echo "[cleanup] Done."
