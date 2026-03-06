#!/bin/bash
# Git Collaboration Workflow — Session Start Repository Status Check
# Outputs JSON with systemMessage for Claude to present recommendations to user.
# Each recommendation includes a REASON and requires human approval.

set -euo pipefail

# Parse flags
FULL_CHECK=false
for arg in "$@"; do
  case "$arg" in
    --full) FULL_CHECK=true ;;
  esac
done

# Exit silently if not in a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
# JSON-safe branch name for embedding in printf-constructed JSON output
BRANCH_JSON=$(printf '%s' "$BRANCH" | sed 's/\\/\\\\/g; s/"/\\"/g')
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
RECS=""
COUNT=0

# 1. Check if on a protected branch (main/integration)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "integration" ]; then
  COUNT=$((COUNT + 1))
  RECS="${RECS}${COUNT}. RECOMMEND: Create a feature branch via /start-feature before making any changes. REASON: You are on protected branch '${BRANCH_JSON}' — direct commits and pushes will be blocked by hooks. "
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

# 5.5. Check for pending review comments in tracker DB
# Fast path: skip python3 chain entirely if tracker DB file doesn't exist
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
TRACKER_DB="${REPO_ROOT:+${REPO_ROOT}/.claude/review-tracker.json}"
if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/scripts/review-tracker.sh" ] && [ -n "$TRACKER_DB" ] && [ -f "$TRACKER_DB" ]; then
  TRACKER_OUTPUT=$(bash "$PLUGIN_ROOT/scripts/review-tracker.sh" list 2>/dev/null || echo "")
  if [ -n "$TRACKER_OUTPUT" ]; then
    ACTIVE_COUNT=$(printf '%s' "$TRACKER_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('active',0))" 2>/dev/null || echo "0")
    if [ "$ACTIVE_COUNT" -gt 0 ]; then
      ACTIVE_DETAILS=$(printf '%s' "$TRACKER_OUTPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
parts = []
for num, pr in d.get('prs', {}).items():
    if pr['status'] not in ('passed', 'closed'):
        parts.append(f\"PR #{num} ({pr['branch']}): {pr['status']}, round {pr.get('round',1)}\")
print('; '.join(parts))
" 2>/dev/null || echo "")
      # Escape for safe JSON embedding (branch names from tracker DB may contain special chars)
      ACTIVE_DETAILS=$(printf '%s' "$ACTIVE_DETAILS" | sed 's/\\/\\\\/g; s/"/\\"/g')
      COUNT=$((COUNT + 1))
      RECS="${RECS}${COUNT}. RECOMMEND: Run /check-review to view cloud code review results and optionally spawn a review-watcher teammate. REASON: ${ACTIVE_COUNT} PR(s) have pending review activity: ${ACTIVE_DETAILS}. "
    fi
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

# ─── GitHub configuration marker ──────────────────────────────────
# Marker tracks verified GitHub config. Written when all checks pass.
# Re-checked when: marker missing, remote URL changed, or --full flag.
# REPO_ROOT was computed at script top (line 22)
MARKER_FILE=""
SKIP_GITHUB_CHECK=false

if [ -n "$REPO_ROOT" ]; then
  MARKER_FILE="${REPO_ROOT}/.claude/.github-setup-verified"

  # --full ignores marker (force re-check)
  if [ "$FULL_CHECK" != "true" ] && [ -f "$MARKER_FILE" ]; then
    MARKER_URL=$(sed -n 's/.*"remote_url":"\([^"]*\)".*/\1/p' "$MARKER_FILE" 2>/dev/null || echo "")
    CURRENT_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$MARKER_URL" ] && [ "$MARKER_URL" = "$CURRENT_URL" ]; then
      SKIP_GITHUB_CHECK=true
    fi
  fi
fi

# 8. GitHub remote and protection check (skipped if marker valid)
GITHUB_SETUP_NEEDED=""
if [ "$SKIP_GITHUB_CHECK" = "false" ]; then
  REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")

  if [ -z "$REMOTE_URL" ]; then
    # No remote — need full setup
    COUNT=$((COUNT + 1))
    GITHUB_SETUP_NEEDED="no_remote"
    RECS="${RECS}${COUNT}. AUTO-SETUP: Run /setup-repo to create a GitHub repository and configure best-practice settings. REASON: No GitHub remote found — code is not backed up and PRs, code review, and merge queue are unavailable. "
  elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    # Remote exists — check main branch protection (single API call)
    OWNER_REPO=$(echo "$REMOTE_URL" | sed -E 's#^.+github\.com[:/]##' | sed -E 's#\.git$##')
    if [ -n "$OWNER_REPO" ]; then
      PROT_EXIT=0
      PROT_RESPONSE=$(gh api "repos/$OWNER_REPO/branches/main/protection" 2>&1) || PROT_EXIT=$?

      if [ "$PROT_EXIT" -ne 0 ]; then
        if echo "$PROT_RESPONSE" | grep -q "Not Found"; then
          # 404 = no protection rules
          COUNT=$((COUNT + 1))
          GITHUB_SETUP_NEEDED="no_protection"
          RECS="${RECS}${COUNT}. AUTO-SETUP: Run /setup-repo to configure GitHub branch protection and merge settings. REASON: The main branch has no protection rules — direct pushes and force-pushes are possible, bypassing code review. "
        fi
        # Other errors (rate limit, network): skip silently, don't write marker
      else
        # Protection exists — write marker (GitHub is configured)
        if [ -n "$MARKER_FILE" ]; then
          mkdir -p "$(dirname "$MARKER_FILE")"
          printf '{"verified_at":"%s","remote_url":"%s","repo":"%s"}\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$REMOTE_URL" "$OWNER_REPO" > "$MARKER_FILE"
        fi
      fi
    fi
  fi
  # If gh not installed/authed: can't verify, don't write marker, don't flag error
fi

# Append worktree status info for all cases
WORKTREE_INFO="worktree_count:${WORKTREE_COUNT},is_worktree:${IS_WORKTREE}"

# Output
if [ "$COUNT" -gt 0 ]; then
  if [ -n "$GITHUB_SETUP_NEEDED" ]; then
    printf '{"systemMessage": "[Git Collaboration Workflow] Branch: %s | %d issue(s) detected. %sWorktree: %s. CRITICAL SETUP: GitHub repository configuration is incomplete (%s). IMMEDIATELY invoke the /setup-repo skill to check and configure GitHub settings before proceeding with any other work. Present the setup-repo findings and ask for user approval to apply fixes.", "autoInvokeSkill": "setup-repo"}\n' "$BRANCH_JSON" "$COUNT" "$RECS" "$WORKTREE_INFO" "$GITHUB_SETUP_NEEDED"
  else
    printf '{"systemMessage": "[Git Collaboration Workflow] Branch: %s | %d issue(s) detected. %sWorktree: %s. ACTION REQUIRED: Present each numbered recommendation to the user with its reason. Ask for explicit approval before executing any recommended action. Do not auto-execute."}\n' "$BRANCH_JSON" "$COUNT" "$RECS" "$WORKTREE_INFO"
  fi
else
  printf '{"systemMessage": "[Git Collaboration Workflow] Branch: %s | Status: OK. Worktree: %s. No issues detected. Ready to work."}\n' "$BRANCH_JSON" "$WORKTREE_INFO"
fi
