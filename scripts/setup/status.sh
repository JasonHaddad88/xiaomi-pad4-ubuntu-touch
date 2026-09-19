#!/usr/bin/env bash
# Read-only status of the background Halium repo sync.
#   wsl -e bash -c "tr -d '\r' < <this> | bash -s"
set -uo pipefail
T="$HOME/halium/halium-9.0"
cd "$T" 2>/dev/null || { echo "no tree yet"; exit 0; }
echo "=== $(date) ==="
echo "tree size : $(du -sh "$T" 2>/dev/null | cut -f1)"
echo "projects initialized (of ~397): $(find "$T/.repo/projects" -maxdepth 3 -name '*.git' 2>/dev/null | wc -l)"
if pgrep -fa 'repo/main.py' 2>/dev/null | grep -q -- 'sync'; then
  echo "sync: RUNNING (orchestrator alive)"
else
  echo "sync: NOT running (finished, died, or paused)"
fi
echo "active 'git fetch' workers: $(pgrep -fc 'git fetch' 2>/dev/null || echo 0)"
echo "--- sync.log tail ---"; tail -n 6 sync.log 2>/dev/null
grep -q 'EXIT rc=' sync.log 2>/dev/null && echo ">>> $(grep 'EXIT rc=' sync.log | tail -1)"
echo "(resume if stopped: wsl -e bash -c 'setsid bash ~/halium/run-sync.sh 4 >/dev/null 2>&1 </dev/null & wait')"
