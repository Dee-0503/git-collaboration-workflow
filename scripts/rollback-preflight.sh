#!/bin/bash
# rollback-preflight.sh — Collect data for production rollback decision
# Usage: rollback-preflight.sh
# Output: JSON with release info, revert target, and risk assessment
set -euo pipefail

# Fetch latest
git fetch origin main 2>/dev/null || true

# Check for tags on main
LATEST_TAG=$(git describe --tags --abbrev=0 origin/main 2>/dev/null || echo "")
if [ -z "$LATEST_TAG" ]; then
  echo '{"status":"error","message":"No release tags found on main. Nothing to rollback."}'
  exit 1
fi

LATEST_TAG_COMMIT=$(git rev-parse "$LATEST_TAG" 2>/dev/null)
MAIN_HEAD=$(git rev-parse origin/main 2>/dev/null)
MAIN_HEAD_SHORT=$(git rev-parse --short origin/main 2>/dev/null)

# Get the previous tag (what we'd be rolling back to)
PREVIOUS_TAG=$(git describe --tags --abbrev=0 "${LATEST_TAG}^" 2>/dev/null || echo "none")

# Get the release commit details
RELEASE_COMMIT_MSG=$(git log -1 --format="%s" "$MAIN_HEAD" 2>/dev/null || echo "unknown")
RELEASE_COMMIT_DATE=$(git log -1 --format="%ci" "$MAIN_HEAD" 2>/dev/null || echo "unknown")
RELEASE_COMMIT_AUTHOR=$(git log -1 --format="%aN" "$MAIN_HEAD" 2>/dev/null || echo "unknown")

# Count commits in the release (between previous tag and latest tag)
if [ "$PREVIOUS_TAG" != "none" ]; then
  RELEASE_COMMITS=$(git rev-list --count "${PREVIOUS_TAG}..${LATEST_TAG}" 2>/dev/null || echo "0")
else
  RELEASE_COMMITS=$(git rev-list --count "$LATEST_TAG" 2>/dev/null || echo "0")
fi

# List files changed in the release
if [ "$PREVIOUS_TAG" != "none" ]; then
  CHANGED_FILES=$(git diff --name-only "${PREVIOUS_TAG}..${LATEST_TAG}" 2>/dev/null | wc -l | tr -d ' ')
else
  CHANGED_FILES="unknown"
fi

# Check if main HEAD is the same as the tag (no post-release commits)
COMMITS_AFTER_TAG=$(git rev-list --count "${LATEST_TAG}..origin/main" 2>/dev/null || echo "0")

# Check gh CLI for PR info
HAS_GH=false
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  HAS_GH=true
fi

# Get release PR info if available
RELEASE_PR=""
if [ "$HAS_GH" = true ]; then
  RELEASE_PR=$(gh pr list --base main --state merged --limit 1 --json number,title --jq '.[0] | "\(.number)|\(.title)"' 2>/dev/null || echo "")
fi

# Determine if revert is straightforward or complex
REVERT_COMPLEXITY="simple"
if [ "$COMMITS_AFTER_TAG" -gt 0 ]; then
  REVERT_COMPLEXITY="complex"
fi

# Build output
python3 -c "
import json
result = {
    'status': 'ok',
    'latest_release': '$LATEST_TAG',
    'previous_release': '$PREVIOUS_TAG',
    'main_head': '$MAIN_HEAD_SHORT',
    'release_commit': {
        'message': '''$RELEASE_COMMIT_MSG''',
        'date': '$RELEASE_COMMIT_DATE',
        'author': '$RELEASE_COMMIT_AUTHOR'
    },
    'release_stats': {
        'commits': $RELEASE_COMMITS,
        'files_changed': $CHANGED_FILES,
        'commits_after_tag': $COMMITS_AFTER_TAG
    },
    'revert_complexity': '$REVERT_COMPLEXITY',
    'release_pr': '$RELEASE_PR' if '$RELEASE_PR' else None,
    'rollback_target': '$PREVIOUS_TAG' if '$PREVIOUS_TAG' != 'none' else None
}
print(json.dumps(result))
" 2>/dev/null || printf '{"status":"ok","latest_release":"%s","previous_release":"%s","revert_complexity":"%s"}' \
  "$LATEST_TAG" "$PREVIOUS_TAG" "$REVERT_COMPLEXITY"
