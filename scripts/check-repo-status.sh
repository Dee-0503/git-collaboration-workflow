#!/bin/bash
# Git Collaboration Workflow — Session Start Repository Status Check
# Outputs JSON with systemMessage for Claude to present recommendations to user.
# Each recommendation includes a REASON and requires human approval.

set -euo pipefail

# Exit silently if not in a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
RECS=""
COUNT=0

# 1. Check if on a protected branch (main/integration)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "integration" ]; then
  COUNT=$((COUNT + 1))
  RECS="${RECS}${COUNT}. RECOMMEND: Create a feature branch via /start-feature before making any changes. REASON: You are on protected branch '${BRANCH}' — direct commits and pushes will be blocked by hooks. "
fi

# 2. Check for detached HEAD state
if [ "$BRANCH" = "HEAD" ]; then
  COUNT=$((COUNT + 1))
  RECS="${RECS}${COUNT}. RECOMMEND: Create a feature branch via /start-feature. REASON: You are in detached HEAD state — commits made here can be permanently lost. "
fi

# 3. Check for uncommitted changes
CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$CHANGES" -gt 0 ]; then
  COUNT=$((COUNT + 1))
  RECS="${RECS}${COUNT}. RECOMMEND: Commit or stash ${CHANGES} uncommitted change(s) before starting new work. REASON: Uncommitted changes may cause conflicts during branch operations like rebase or checkout. "
fi

# 4. Check if feature branch is behind integration
if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "integration" ] && [ "$BRANCH" != "HEAD" ]; then
  if git rev-parse --verify origin/integration >/dev/null 2>&1; then
    BEHIND=$(git rev-list --count HEAD..origin/integration 2>/dev/null || echo "0")
    if [ "$BEHIND" -gt 0 ]; then
      COUNT=$((COUNT + 1))
      RECS="${RECS}${COUNT}. RECOMMEND: Run /sync-branch to rebase onto latest integration. REASON: Your branch is ${BEHIND} commit(s) behind integration — the longer you wait, the higher the merge conflict risk. "
    fi
  fi
fi

# 5. Check for local commits not pushed to remote
if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "integration" ] && [ "$BRANCH" != "HEAD" ]; then
  AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "skip")
  if [ "$AHEAD" != "skip" ] && [ "$AHEAD" -gt 0 ]; then
    COUNT=$((COUNT + 1))
    RECS="${RECS}${COUNT}. RECOMMEND: Push ${AHEAD} local commit(s) to remote via git push. REASON: Unpushed commits exist only on your local machine — not backed up and not visible to collaborators. "
  fi
fi

# 6. Check if integration branch exists
if ! git rev-parse --verify origin/integration >/dev/null 2>&1; then
  COUNT=$((COUNT + 1))
  RECS="${RECS}${COUNT}. RECOMMEND: Create the integration branch (git checkout -b integration && git push -u origin integration). REASON: The Git Collaboration Workflow requires an integration branch as the staging area between feature branches and main. "
fi

# 7. Multi-instance worktree isolation check
WORKTREE_COUNT=$(git worktree list 2>/dev/null | wc -l | tr -d ' ')
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null)
IS_WORKTREE="false"
if [ "$GIT_DIR" != "$GIT_COMMON" ]; then
  IS_WORKTREE="true"
fi

# If on main repo (not a worktree) and no other worktrees exist, recommend worktree for parallel work
if [ "$IS_WORKTREE" = "false" ] && [ "$WORKTREE_COUNT" -le 1 ]; then
  # Check if there are signs of multi-instance usage (e.g., git lock files)
  LOCK_FILES=$(find "$GIT_DIR" -name "*.lock" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$LOCK_FILES" -gt 0 ]; then
    COUNT=$((COUNT + 1))
    RECS="${RECS}${COUNT}. RECOMMEND: Use git worktree for parallel development. Run Claude Code's built-in worktree command or use superpowers:using-git-worktrees skill. REASON: Detected active git lock files — another process may be operating on this repository. Without worktree isolation, two instances sharing one working directory will silently corrupt each other's work. "
  fi
fi

# Append worktree status info for all cases
WORKTREE_INFO="worktree_count:${WORKTREE_COUNT},is_worktree:${IS_WORKTREE}"

# Output
if [ "$COUNT" -gt 0 ]; then
  printf '{"systemMessage": "[Git Collaboration Workflow] Branch: %s | %d issue(s) detected. %sWorktree: %s. ACTION REQUIRED: Present each numbered recommendation to the user with its reason. Ask for explicit approval before executing any recommended action. Do not auto-execute."}\n' "$BRANCH" "$COUNT" "$RECS" "$WORKTREE_INFO"
else
  printf '{"systemMessage": "[Git Collaboration Workflow] Branch: %s | Status: OK. Worktree: %s. No issues detected. Ready to work."}\n' "$BRANCH" "$WORKTREE_INFO"
fi
