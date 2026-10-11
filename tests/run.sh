#!/usr/bin/env bash
# Runs the plugin against the fixtures and checks the output.
set -u
cd "$(dirname "$0")/.." || exit 1

PLUGIN=./restic-status.5m.sh
FIX=tests/fixtures
NOW=1791720000 # 2026-10-11T12:00:00Z
failures=0

run() {
  RESTIC_STATUS_CONFIG=/nonexistent RESTIC_DETECT_RUNNING=0 RESTIC_NOW=$NOW \
    RESTIC_STATUS_FILES="$1" "$PLUGIN"
}

expect() { # name, output, fixed string expected in output
  if printf '%s\n' "$2" | grep -qF -- "$3"; then
    echo "ok   $1: $3"
  else
    echo "FAIL $1: expected '$3'"; failures=$((failures + 1))
  fi
}

out=$(run "$FIX/ok.json")
expect ok "$out" " | sfimage=externaldrive.badge.checkmark"
expect ok "$out" "Backup OK"
expect ok "$out" "home — 10h ago"
expect ok "$out" "--Duration: 12m 34s"
expect ok "$out" "--Added: 282.8 MiB · Processed: 75.7 GiB"
expect ok "$out" "--check: OK · 2d ago"
expect ok "$out" 'param1=--run param2="home"'

out=$(run "$FIX/stale.json")
expect stale "$out" "sfimage=externaldrive.badge.exclamationmark"
expect stale "$out" "--Older than 26h"
out=$(RESTIC_MAX_AGE_HOURS=0 run "$FIX/stale.json")
expect stale-disabled "$out" "sfimage=externaldrive.badge.checkmark"
out=$(RESTIC_MAX_AGE_HOURS_old=300 run "$FIX/stale.json")
expect stale-override "$out" "sfimage=externaldrive.badge.checkmark"

out=$(run "$FIX/no-extended.json")
expect no-extended "$out" "basic — 4h ago"

out=$(run "$FIX/invalid.json")
expect invalid "$out" "sfimage=externaldrive.badge.xmark"
expect invalid "$out" "invalid.json — cannot parse"

out=$(run "$FIX/does-not-exist.json")
expect missing "$out" "does-not-exist.json — file not found"

out=$(RESTIC_SHOW_COUNT=1 run "$FIX/multi.json, $FIX/ok.json")
expect multi "$out" "3 | sfimage=externaldrive.badge.xmark"
expect multi "$out" "2 failed, 1 overdue (of 5)"
expect multi "$out" "nas — backup failed 10h ago"
expect multi "$out" "--Error: exit status 1"
expect multi "$out" "sftp:nas:/backup / test"
expect multi "$out" "documents — 6h ago"
expect multi "$out" "check-only — failed"
expect multi "$out" "home — 10h ago"

out=$(run "$FIX/empty.json")
expect empty "$out" "sfimage=externaldrive.badge.questionmark"
expect empty "$out" "No backups found"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"; exit 1
fi
echo "all tests passed"
