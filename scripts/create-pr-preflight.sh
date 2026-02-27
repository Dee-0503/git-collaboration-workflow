#!/bin/bash
# create-pr-preflight.sh — Pre-flight checks and conflict detection for PR creation
# Usage: create-pr-preflight.sh
# Output: JSON with changed files, conflicts with open PRs, suggested semver label
set -euo pipefail

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Validate branch
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "integration" ] || [ "$BRANCH" = "HEAD" ]; then
  printf '{"status":"error","message":"Cannot create PR from %s. Switch to a feature branch."}' "$BRANCH"
  exit 1
fi

# Check gh CLI
if ! command -v gh >/dev/null 2>&1; then
  echo '{"status":"error","message":"GitHub CLI (gh) not found. Install: https://cli.github.com/"}'
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo '{"status":"error","message":"GitHub CLI not authenticated. Run: gh auth login"}'
  exit 1
fi

# Check commits ahead of integration
AHEAD=$(git rev-list --count origin/integration..HEAD 2>/dev/null || echo "0")
if [ "$AHEAD" = "0" ]; then
  echo '{"status":"error","message":"No commits ahead of integration. Nothing to create a PR for."}'
  exit 1
fi

# Get changed files
CHANGED_FILES=$(git diff --name-only origin/integration...HEAD 2>/dev/null)
FILE_COUNT=$(echo "$CHANGED_FILES" | grep -c . || echo "0")

# Determine semver label from commit types
COMMITS=$(git log --oneline origin/integration..HEAD --format="%s" 2>/dev/null)
SEMVER="patch"
if echo "$COMMITS" | grep -qE '^feat(\(.+\))?!?:'; then
  SEMVER="minor"
fi
if echo "$COMMITS" | grep -qE '!:' || echo "$COMMITS" | grep -qiE 'BREAKING'; then
  SEMVER="major"
fi

# Check for open PR conflicts
CONFLICTS=""
if command -v gh >/dev/null 2>&1; then
  OPEN_PRS=$(gh pr list --base integration --json number,title,files --limit 50 2>/dev/null || echo "[]")

  if [ "$OPEN_PRS" != "[]" ] && [ -n "$OPEN_PRS" ]; then
    # Compare file lists using python3
    CONFLICTS=$(python3 -c "
import json, sys
our_files = set('''$CHANGED_FILES'''.strip().split('\n'))
our_files.discard('')
prs = json.loads('''$OPEN_PRS''')
conflicts = []
for pr in prs:
    pr_files = set(f.get('path','') for f in pr.get('files',[]))
    overlap = our_files & pr_files
    if overlap:
        conflicts.append({'pr': pr['number'], 'title': pr['title'], 'overlapping_files': list(overlap)})
print(json.dumps(conflicts))
" 2>/dev/null || echo "[]")
  fi
fi

# Get repo info for merge queue check
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "")
QUEUE_CONFLICTS="[]"
if [ -n "$REPO" ]; then
  QUEUE_DATA=$(gh api "repos/$REPO/pulls?state=open&base=integration" --jq '[.[] | select(.merge_commit_sha != null) | {number: .number, title: .title}]' 2>/dev/null || echo "[]")
  # Queue conflict detection would need file-level comparison similar to above
fi

# Build output
printf '{"status":"ok","branch":"%s","commits_ahead":%s,"changed_files":%s,"file_list":%s,"semver_suggestion":"%s","pr_conflicts":%s,"scope_warning":%s}' \
  "$BRANCH" \
  "$AHEAD" \
  "$FILE_COUNT" \
  "$(echo "$CHANGED_FILES" | python3 -c 'import json,sys; print(json.dumps([l for l in sys.stdin.read().strip().split("\n") if l]))' 2>/dev/null || echo '[]')" \
  "$SEMVER" \
  "${CONFLICTS:-[]}" \
  "$([ "$FILE_COUNT" -gt 20 ] && echo 'true' || echo 'false')"
