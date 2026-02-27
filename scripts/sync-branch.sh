#!/bin/bash
# sync-branch.sh — Rebase current feature branch onto latest integration
# Usage: sync-branch.sh [--auto-stash]
# Output: JSON with status, conflicts if any
set -euo pipefail

AUTO_STASH=false
[ "${1:-}" = "--auto-stash" ] && AUTO_STASH=true

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Validate: not on protected branch
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "integration" ]; then
  printf '{"status":"error","message":"Cannot sync a protected branch (%s). Switch to a feature branch first."}' "$BRANCH"
  exit 1
fi

if [ "$BRANCH" = "HEAD" ]; then
  echo '{"status":"error","message":"Detached HEAD state. Create or checkout a feature branch first."}'
  exit 1
fi

# Check integration exists
if ! git rev-parse --verify origin/integration >/dev/null 2>&1; then
  echo '{"status":"error","message":"origin/integration not found. Cannot sync."}'
  exit 1
fi

# Stash if dirty
STASHED=false
DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$DIRTY" -gt 0 ]; then
  if [ "$AUTO_STASH" = true ]; then
    git stash push -m "sync-branch auto-stash" 2>/dev/null
    STASHED=true
  else
    printf '{"status":"error","message":"Working tree has %s uncommitted change(s). Pass --auto-stash or commit/stash manually.","uncommitted":%s}' "$DIRTY" "$DIRTY"
    exit 1
  fi
fi

# Fetch latest
git fetch origin integration 2>/dev/null

# Check if already up to date
BEHIND=$(git rev-list --count HEAD..origin/integration 2>/dev/null || echo "0")
if [ "$BEHIND" = "0" ]; then
  if [ "$STASHED" = true ]; then
    git stash pop 2>/dev/null || true
  fi
  printf '{"status":"ok","message":"Already up to date with integration.","branch":"%s","behind":0}' "$BRANCH"
  exit 0
fi

# Attempt rebase
if git rebase origin/integration 2>/dev/null; then
  # Rebase succeeded — push
  if git push --force-with-lease 2>/dev/null; then
    PUSH_STATUS="pushed"
  else
    PUSH_STATUS="push_failed"
  fi

  if [ "$STASHED" = true ]; then
    git stash pop 2>/dev/null || true
  fi

  HEAD=$(git rev-parse --short HEAD)
  printf '{"status":"ok","branch":"%s","rebased_onto":"origin/integration","commits_applied":%s,"head":"%s","push":"%s","stash_restored":%s}' \
    "$BRANCH" "$BEHIND" "$HEAD" "$PUSH_STATUS" "$STASHED"
else
  # Rebase has conflicts
  CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  CONFLICT_COUNT=$(echo "$CONFLICT_FILES" | tr ',' '\n' | grep -c . || echo "0")

  printf '{"status":"conflict","branch":"%s","conflict_count":%s,"conflict_files":"%s","stashed":%s,"instructions":"Resolve conflicts, then: git add <files> && git rebase --continue. Or abort: git rebase --abort"}' \
    "$BRANCH" "$CONFLICT_COUNT" "$CONFLICT_FILES" "$STASHED"
fi
