#!/bin/bash
# post-merge-cleanup.sh — Detect completed merge and suggest branch cleanup
# Called as PostToolUse hook on Bash commands
# Input: tool_input JSON on stdin (contains the command that was executed)
set -euo pipefail

# Read tool input from stdin
INPUT=$(cat)

# Extract the command that was executed
COMMAND=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('command', data.get('input', {}).get('command', '')))
" 2>/dev/null || echo "")

# Only act on merge-related commands
if ! echo "$COMMAND" | grep -qE '(gh pr merge|git merge)'; then
  exit 0
fi

# Check if a PR was just merged
MERGED_BRANCH=""
MERGED_PR=""

if echo "$COMMAND" | grep -q 'gh pr merge'; then
  MERGED_PR=$(echo "$COMMAND" | grep -oE '[0-9]+' | head -1)
  if [ -n "$MERGED_PR" ]; then
    MERGED_BRANCH=$(gh pr view "$MERGED_PR" --json headRefName --jq '.headRefName' 2>/dev/null || echo "")
    MERGE_STATE=$(gh pr view "$MERGED_PR" --json state --jq '.state' 2>/dev/null || echo "")
    if [ "$MERGE_STATE" != "MERGED" ]; then
      exit 0
    fi
  fi
fi

if [ -z "$MERGED_BRANCH" ]; then
  exit 0
fi

CLEANUP_ITEMS=""
CLEANUP_COUNT=0

if git ls-remote --heads origin "$MERGED_BRANCH" 2>/dev/null | grep -q "$MERGED_BRANCH"; then
  CLEANUP_COUNT=$((CLEANUP_COUNT + 1))
  CLEANUP_ITEMS="${CLEANUP_ITEMS}\"remote branch 'origin/${MERGED_BRANCH}' (git push origin --delete ${MERGED_BRANCH})\","
fi

if git rev-parse --verify "$MERGED_BRANCH" >/dev/null 2>&1; then
  CLEANUP_COUNT=$((CLEANUP_COUNT + 1))
  CLEANUP_ITEMS="${CLEANUP_ITEMS}\"local branch '${MERGED_BRANCH}' (git branch -d ${MERGED_BRANCH})\","
fi

WORKTREE_PATH=$(git worktree list 2>/dev/null | grep "$MERGED_BRANCH" | awk '{print $1}')
if [ -n "$WORKTREE_PATH" ]; then
  CLEANUP_COUNT=$((CLEANUP_COUNT + 1))
  CLEANUP_ITEMS="${CLEANUP_ITEMS}\"worktree at '${WORKTREE_PATH}' (git worktree remove ${WORKTREE_PATH})\","
fi

if [ "$CLEANUP_COUNT" -eq 0 ]; then
  exit 0
fi

CLEANUP_ITEMS="${CLEANUP_ITEMS%,}"

# Update review tracker if applicable
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "$MERGED_PR" ]; then
  bash "$SCRIPT_DIR/review-tracker.sh" update "$MERGED_PR" "closed" "0" >/dev/null 2>&1 || true
fi

printf '{"systemMessage":"PR #%s merged successfully. Branch '\''%s'\'' can be cleaned up. Found %d item(s) to clean: [%s]. RECOMMEND: Ask user for approval before deleting. Run /cleanup-branches for a comprehensive cleanup."}\n' \
  "$MERGED_PR" "$MERGED_BRANCH" "$CLEANUP_COUNT" "$CLEANUP_ITEMS"
