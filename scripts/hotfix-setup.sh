#!/bin/bash
# hotfix-setup.sh — Create hotfix branch from main for emergency fixes
# Usage: hotfix-setup.sh <hotfix-slug>
# Output: JSON with branch info and next steps
set -euo pipefail

SLUG="${1:-}"

if [ -z "$SLUG" ]; then
  echo '{"status":"error","message":"Usage: hotfix-setup.sh <hotfix-slug> (e.g., fix-auth-crash)"}'
  exit 1
fi

BRANCH="hotfix/${SLUG}"

# Validate branch name
if ! echo "$BRANCH" | grep -qE '^hotfix/[a-z0-9][a-z0-9._-]*$'; then
  printf '{"status":"error","message":"Invalid hotfix name: %s. Use lowercase letters, digits, dots, underscores, hyphens."}' "$SLUG"
  exit 1
fi

# Check for uncommitted changes
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$DIRTY" -gt 0 ]; then
  printf '{"status":"warning","message":"You have %s uncommitted change(s). Consider committing or stashing first.","uncommitted":%s}' "$DIRTY" "$DIRTY"
fi

# Fetch latest
if ! git fetch origin 2>/dev/null; then
  echo '{"status":"error","message":"Failed to fetch from origin. Check remote configuration."}'
  exit 1
fi

# Verify main exists
if ! git rev-parse --verify origin/main >/dev/null 2>&1; then
  echo '{"status":"error","message":"origin/main not found. Cannot create hotfix without main branch."}'
  exit 1
fi

# Check if branch already exists
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1 || git rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
  printf '{"status":"error","message":"Branch %s already exists locally or on remote."}' "$BRANCH"
  exit 1
fi

# Get current version on main
CURRENT_TAG=$(git describe --tags --abbrev=0 origin/main 2>/dev/null || echo "v0.0.0")

# Create branch from main HEAD
git checkout origin/main -b "$BRANCH" 2>/dev/null
if [ $? -ne 0 ]; then
  printf '{"status":"error","message":"Failed to create branch %s from origin/main."}' "$BRANCH"
  exit 1
fi

# Push with tracking
git push -u origin "$BRANCH" 2>/dev/null
if [ $? -ne 0 ]; then
  printf '{"status":"error","message":"Branch created locally but failed to push to remote. Run: git push -u origin %s"}' "$BRANCH"
  exit 1
fi

HEAD=$(git rev-parse --short HEAD)
printf '{"status":"ok","branch":"%s","base":"origin/main","base_version":"%s","head":"%s","tracking":"origin/%s","next_steps":["Make the minimal fix needed","Use fix: commit prefix","Run /create-pr when ready"]}' \
  "$BRANCH" "$CURRENT_TAG" "$HEAD" "$BRANCH"
