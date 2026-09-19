#!/usr/bin/env bash
# Phase 2 step 1: apply Halium hybris-patches to the synced tree.
# These add the Halium build glue (e.g. build/target/product/halium.mk) + hybris hooks across
# build/, bionic, system/core, frameworks, etc. Uses `git am` (--mb) so each lands as a commit.
# Needs a git identity (set in 20-repo-init.sh).  wsl -e bash -c "tr -d '\r' < <this> | bash -s"
set -uo pipefail
cd "$HOME/halium/halium-9.0" || exit 1
LOG=/tmp/apply-patches.log
echo "=== apply-patches --mb START $(date -u) ==="
if ./hybris-patches/apply-patches.sh --mb > "$LOG" 2>&1; then
  echo "apply-patches: SUCCESS"
  rc=0
else
  rc=$?
  echo "apply-patches: FAILED (rc=$rc) — see tail below"
fi
echo "--- patches applied (Applying: lines): $(grep -c '^Applying:' "$LOG" 2>/dev/null || echo 0) ---"
echo "--- tail 40 ---"
tail -40 "$LOG"
exit $rc
