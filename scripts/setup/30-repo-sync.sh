#!/usr/bin/env bash
# Long background job: shallow sync of the Halium 9.0 tree (397 repos) + clover device/kernel/vendor.
# RESUMABLE — if it dies (flaky link), just re-run this; repo picks up where it left off.
# Run as the normal user:  wsl -e bash -c "tr -d '\r' < <this> | bash -s [JOBS]"
set -uo pipefail
cd "$HOME/halium/halium-9.0"
export PATH="$HOME/.bin:$PATH"
JOBS="${1:-6}"
LOG="$HOME/halium/halium-9.0/sync.log"
{
  echo "=== repo sync START $(date -u) (jobs=$JOBS) ==="
  "$HOME/.bin/repo" sync -c --no-tags --optimized-fetch --prune --force-sync --retry-fetches=3 -j"$JOBS"
  rc=$?
  echo "=== repo sync EXIT rc=$rc $(date -u) ==="
} 2>&1 | tee "$LOG"
