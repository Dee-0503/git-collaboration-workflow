#!/bin/bash
# post-merge-cleanup.sh — Detect completed merge and suggest branch cleanup
# Called as PostToolUse hook on Bash commands
# Input: tool_input JSON on stdin (contains the command that was executed)
#
# NOTE: The hooks API only supports tool-name-level matching ("Bash"), so this
# script is invoked for every Bash command. The grep pre-check on line ~18
# ensures a fast exit (<5ms) for non-merge commands, keeping overhead minimal.
#
# NOTE: -e is intentionally omitted. This hook must never abort mid-execution —
# individual command failures (git ls-remote, gh pr view, jq) are handled via
# explicit exit-code checks and || fallbacks throughout the script.
set -uo pipefail

# Read tool input from stdin with timeout to avoid blocking
INPUT=$(timeout 2 cat 2>/dev/null || echo "")
if [ -z "$INPUT" ]; then
  exit 0
fi

# Quick pre-check: skip python3 if input doesn't mention gh pr merge
if ! printf '%s' "$INPUT" | grep -q 'gh pr merge'; then
  exit 0
fi

# Extract the command that was executed
# NOTE: 2>/dev/null || echo "" is intentional — this hook fires on every Bash command,
# so python3 parse errors must fail silently to avoid disrupting normal operations.
COMMAND=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('command', data.get('input', {}).get('command', '')))
" 2>/dev/null || echo "")

# Only act on gh pr merge commands (git merge is out of scope — no PR context available)
if ! echo "$COMMAND" | grep -q 'gh pr merge'; then
  exit 0
fi

# Extract PR number — explicit (gh pr merge 42) or inferred from current branch
# Strip --flag=value and --flag non-numeric-value patterns to avoid extracting digits from
# flag values (e.g., --timeout=30, --repo org123/repo)
MERGED_PR=$(echo "$COMMAND" | sed -n 's/.*gh pr merge[[:space:]]\{1,\}//p' | sed 's/--[a-zA-Z_-]*=[^ ]*//g; s/--[a-zA-Z_-]* [^ ]*[^0-9 ][^ ]*//g' | grep -oE '[0-9]+' | head -1)
if [ -z "$MERGED_PR" ]; then
  # No explicit number: gh pr merge --squash (infers current branch)
  MERGED_PR=$(gh pr view --json number --jq '.number' 2>/dev/null || echo "")
fi
if [ -z "$MERGED_PR" ]; then
  exit 0
fi

PR_DATA=$(gh pr view "$MERGED_PR" --json headRefName,state --jq '[.headRefName, .state] | @tsv' 2>/dev/null || echo "")
MERGED_BRANCH=""
MERGE_STATE=""
if [ -n "$PR_DATA" ]; then
  MERGED_BRANCH=$(printf '%s' "$PR_DATA" | cut -f1)
  MERGE_STATE=$(printf '%s' "$PR_DATA" | cut -f2)
fi
if [ "$MERGE_STATE" != "MERGED" ] || [ -z "$MERGED_BRANCH" ]; then
  exit 0
fi

CLEANUP_ITEMS=()
CLEANUP_COUNT=0

# Use --exit-code for reliable remote branch detection
if git ls-remote --exit-code --heads origin "$MERGED_BRANCH" >/dev/null 2>&1; then
  CLEANUP_COUNT=$((CLEANUP_COUNT + 1))
  CLEANUP_ITEMS+=("remote branch 'origin/${MERGED_BRANCH}' (git push origin --delete ${MERGED_BRANCH})")
fi

if git rev-parse --verify "refs/heads/$MERGED_BRANCH" >/dev/null 2>&1; then
  CLEANUP_COUNT=$((CLEANUP_COUNT + 1))
  CLEANUP_ITEMS+=("local branch '${MERGED_BRANCH}' (git branch -d ${MERGED_BRANCH})")
fi

# Use --porcelain for unambiguous parsing (handles paths with spaces, exact branch match)
WORKTREE_PATH=$(git worktree list --porcelain 2>/dev/null | awk -v branch="refs/heads/$MERGED_BRANCH" '
  /^worktree / { path = substr($0, 10) }
  $0 == "branch " branch { print path; exit }
')
if [ -n "$WORKTREE_PATH" ]; then
  CLEANUP_COUNT=$((CLEANUP_COUNT + 1))
  CLEANUP_ITEMS+=("worktree at '${WORKTREE_PATH}' (git worktree remove ${WORKTREE_PATH})")
fi

if [ "$CLEANUP_COUNT" -eq 0 ]; then
  exit 0
fi

# Update review tracker (MERGED_PR is guaranteed non-empty — guarded by exit at line 47-49)
# Only call update if PR is registered; unregistered PRs (hotfix, integration merges) are expected
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if bash "$SCRIPT_DIR/review-tracker.sh" status "$MERGED_PR" >/dev/null 2>&1; then
  bash "$SCRIPT_DIR/review-tracker.sh" update "$MERGED_PR" "closed" "0" >/dev/null 2>&1 || echo "warning: failed to update review-tracker for PR #$MERGED_PR" >&2
fi

# Build JSON output safely via jq — $ARGS.positional creates a proper JSON array
# preventing branch-name injection and ensuring valid JSON structure
if ! command -v jq >/dev/null 2>&1; then
  echo "warning: jq not found, skipping cleanup suggestion output" >&2
  exit 0
fi
jq -n --arg pr "$MERGED_PR" --arg branch "$MERGED_BRANCH" \
      --argjson count "$CLEANUP_COUNT" \
  '{systemMessage: ("PR #" + $pr + " merged successfully. Branch \u0027" + $branch + "\u0027 can be cleaned up. Found " + ($count|tostring) + " item(s) to clean: " + ($ARGS.positional | join(", ")) + ". RECOMMEND: Ask user for approval before deleting. Run /cleanup-branches for a comprehensive cleanup.")}' \
  --args "${CLEANUP_ITEMS[@]}"
