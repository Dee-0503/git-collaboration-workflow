#!/bin/bash
# cleanup-branches.sh — List merged branches eligible for cleanup
# Usage: cleanup-branches.sh [--include-local]
# Output: JSON with merged branch candidates
set -euo pipefail

INCLUDE_LOCAL=false
[ "${1:-}" = "--include-local" ] && INCLUDE_LOCAL=true

# Fetch and prune
git fetch origin --prune 2>/dev/null || true

# Protected branches that should never be deleted
PROTECTED="main|integration|HEAD"

# List remote branches merged into integration
MERGED_REMOTE=$(git branch -r --merged origin/integration 2>/dev/null | \
  grep -vE "origin/($PROTECTED)" | \
  grep -E 'origin/(feature|phase|hotfix|release)/' | \
  sed 's/^[[:space:]]*//' | \
  sed 's|origin/||' || true)

REMOTE_COUNT=0
if [ -n "$MERGED_REMOTE" ]; then
  REMOTE_COUNT=$(echo "$MERGED_REMOTE" | grep -c . || echo "0")
fi

# List local branches merged into integration (if requested)
MERGED_LOCAL=""
LOCAL_COUNT=0
if [ "$INCLUDE_LOCAL" = true ]; then
  MERGED_LOCAL=$(git branch --merged integration 2>/dev/null | \
    grep -vE "^[*]?[[:space:]]*(main|integration)$" | \
    grep -E '(feature|phase|hotfix|release)/' | \
    sed 's/^[[:space:]]*//' || true)
  if [ -n "$MERGED_LOCAL" ]; then
    LOCAL_COUNT=$(echo "$MERGED_LOCAL" | grep -c . || echo "0")
  fi
fi

# List stale branches (no commits in 30+ days, not merged)
STALE_REMOTE=""
STALE_COUNT=0
THIRTY_DAYS_AGO=$(date -v-30d +%s 2>/dev/null || date -d '30 days ago' +%s 2>/dev/null || echo "0")
if [ "$THIRTY_DAYS_AGO" != "0" ]; then
  while IFS='|' read -r refname date_epoch; do
    [ -z "$refname" ] && continue
    branch="${refname#refs/remotes/origin/}"
    # Skip protected and already-merged branches
    echo "$branch" | grep -qE "^($PROTECTED)$" && continue
    echo "$branch" | grep -qvE '^(feature|phase|hotfix|release)/' && continue
    # Check if already in merged list
    echo "$MERGED_REMOTE" | grep -qF "$branch" && continue
    if [ "$date_epoch" -lt "$THIRTY_DAYS_AGO" ] 2>/dev/null; then
      STALE_REMOTE="${STALE_REMOTE}${branch}\n"
      STALE_COUNT=$((STALE_COUNT + 1))
    fi
  done < <(git for-each-ref --sort=-committerdate --format='%(refname)|%(committerdate:unix)' refs/remotes/origin/ 2>/dev/null)
fi

# Build JSON output
python3 -c "
import json

merged_remote = '''$MERGED_REMOTE'''.strip().split('\n') if '''$MERGED_REMOTE'''.strip() else []
merged_local = '''$MERGED_LOCAL'''.strip().split('\n') if '''$MERGED_LOCAL'''.strip() else []

result = {
    'status': 'ok',
    'merged_remote': [b for b in merged_remote if b],
    'merged_remote_count': $REMOTE_COUNT,
    'merged_local': [b for b in merged_local if b],
    'merged_local_count': $LOCAL_COUNT,
    'stale_count': $STALE_COUNT,
    'total_candidates': $REMOTE_COUNT + $LOCAL_COUNT + $STALE_COUNT,
    'include_local': $( [ "$INCLUDE_LOCAL" = true ] && echo 'True' || echo 'False' )
}
print(json.dumps(result))
" 2>/dev/null || printf '{"status":"ok","merged_remote_count":%s,"merged_local_count":%s,"stale_count":%s}' \
  "$REMOTE_COUNT" "$LOCAL_COUNT" "$STALE_COUNT"
