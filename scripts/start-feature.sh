#!/bin/bash
# start-feature.sh — Create a feature branch from integration
# Usage: start-feature.sh <contributor-id> <feature-slug>
# Output: JSON with status and branch info
set -euo pipefail

ID="${1:-}"
SLUG="${2:-}"

if [ -z "$ID" ] || [ -z "$SLUG" ]; then
  echo '{"status":"error","message":"Usage: start-feature.sh <contributor-id> <feature-slug>"}'
  exit 1
fi

BRANCH="feature/${ID}-${SLUG}"

# Validate branch name
if ! echo "$BRANCH" | grep -qE '^(feature|phase|hotfix|release)/[a-z0-9][a-z0-9._-]*$'; then
  printf '{"status":"error","message":"Invalid branch name: %s. Use lowercase letters, digits, dots, underscores, hyphens."}' "$BRANCH"
  exit 1
fi

# Check for uncommitted changes (record for inclusion in final output)
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
UNCOMMITTED_WARNING=""
if [ "$DIRTY" -gt 0 ]; then
  UNCOMMITTED_WARNING="You have ${DIRTY} uncommitted change(s). Consider committing or stashing first."
fi

# Fetch and switch to integration
if ! git fetch origin 2>/dev/null; then
  echo '{"status":"error","message":"Failed to fetch from origin. Check remote configuration."}'
  exit 1
fi

if ! git rev-parse --verify origin/integration >/dev/null 2>&1; then
  echo '{"status":"error","message":"Branch origin/integration does not exist. Create it first: git checkout -b integration && git push -u origin integration"}'
  exit 1
fi

# Check if branch already exists
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1 || git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
  printf '{"status":"error","message":"Branch %s already exists locally or on remote."}' "$BRANCH"
  exit 1
fi

# Create branch from integration HEAD
git checkout origin/integration -b "$BRANCH" 2>/dev/null
if [ $? -ne 0 ]; then
  printf '{"status":"error","message":"Failed to create branch %s from origin/integration."}' "$BRANCH"
  exit 1
fi

# Push with tracking
git push -u origin "$BRANCH" 2>/dev/null
if [ $? -ne 0 ]; then
  printf '{"status":"error","message":"Branch created locally but failed to push to remote. Run: git push -u origin %s"}' "$BRANCH"
  exit 1
fi

HEAD=$(git rev-parse --short HEAD)

# Detect worktree environment for multi-instance recommendation
WORKTREE_COUNT=$(git worktree list 2>/dev/null | wc -l | tr -d ' ')
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null)
IS_WORKTREE="false"
WORKTREE_RECOMMENDATION="none"
if [ "$GIT_DIR" != "$GIT_COMMON" ]; then
  IS_WORKTREE="true"
fi

# Recommend worktree if: main repo (not worktree), no other worktrees, and other feature branches exist
if [ "$IS_WORKTREE" = "false" ]; then
  OTHER_FEATURES=$(git branch -r 2>/dev/null | grep -c 'origin/feature/' || echo "0")
  OTHER_FEATURES=$(echo "$OTHER_FEATURES" | tr -d ' ')
  if [ "$OTHER_FEATURES" -gt 0 ] && [ "$WORKTREE_COUNT" -le 1 ]; then
    WORKTREE_RECOMMENDATION="suggested"
  fi
fi

# Scan open PRs for potential file conflicts (early warning)
ACTIVE_PR_WARNINGS="[]"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  OPEN_PRS=$(gh pr list --base integration --json number,title,headRefName,files --limit 50 2>/dev/null || echo "[]")
  if [ "$OPEN_PRS" != "[]" ] && [ -n "$OPEN_PRS" ]; then
    ACTIVE_PR_WARNINGS=$(python3 -c "
import json
prs = json.loads('''$OPEN_PRS''')
warnings = []
for pr in prs:
    files = [f.get('path','') for f in pr.get('files',[])]
    if files:
        warnings.append({
            'pr': pr['number'],
            'title': pr['title'],
            'branch': pr['headRefName'],
            'files': files[:20],
            'file_count': len(files)
        })
print(json.dumps(warnings))
" 2>/dev/null || echo "[]")
  fi
fi

printf '{"status":"ok","branch":"%s","base":"origin/integration","head":"%s","tracking":"origin/%s","uncommitted":%s,"uncommitted_warning":"%s","is_worktree":%s,"worktree_count":%s,"worktree_recommendation":"%s","active_prs":%s}' \
  "$BRANCH" "$HEAD" "$BRANCH" "$DIRTY" "$UNCOMMITTED_WARNING" "$IS_WORKTREE" "$WORKTREE_COUNT" "$WORKTREE_RECOMMENDATION" "$ACTIVE_PR_WARNINGS"
