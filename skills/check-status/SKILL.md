---
name: check-status
description: This skill should be used when the user asks to "check status", "what's my repo status", "am I ready to commit", "check my branch", or wants a health check of the repository state. Performs comprehensive repository health check with actionable recommendations requiring user approval.
user_invocable: true
---

# /check-status — Repository Health Check

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Perform a comprehensive repository health check and present actionable
recommendations. Each recommendation includes a clear reason and requires
explicit user approval before execution.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`
   - If not a git repo: report and stop.

## Steps

### Step 1 — Gather Repository State

Execute the backing script for initial data collection:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-repo-status.sh"
```

The SessionStart hook also runs this script automatically. Parse the
`systemMessage` JSON for initial state in either case.

Then run additional checks not covered by the script:

```bash
# Check if current branch has an open PR (requires gh CLI)
gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --json number,state --jq '.[0].number' 2>/dev/null

# Last commit date on current branch
git log -1 --format="%cr" 2>/dev/null

# Stash count
git stash list 2>/dev/null | wc -l

# Check if current branch has remote tracking
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "no-tracking"
```

### Step 2 — Analyze and Present Status Report

Present a formatted status report:

```
Repository Health Check
=======================
Branch:          <current branch>
Last commit:     <relative time>
Uncommitted:     <N file(s)> or "clean"
Remote tracking: <tracking branch> or "not set"
Behind integration: <N commit(s)> or "up to date"
Unpushed commits: <N> or "all pushed"
Open PR:         #<number> or "none"
Stashed changes: <N>
```

### Step 3 — Generate Recommendations

For EACH issue detected, present a recommendation:

```
[N] Recommendation: <what to do>
    Reason:         <why this matters>
    Action:         <exact command or skill>
    Approve? (y/n)
```

Apply these detection rules:

| Condition | Recommendation | Reason |
|-----------|---------------|--------|
| On `main` or `integration` | Create feature branch via `/start-feature` | Direct changes on protected branches are blocked by hooks |
| Detached HEAD | Create feature branch via `/start-feature` | Commits on detached HEAD can be permanently lost |
| Uncommitted changes (> 0) | Commit or stash | May cause conflicts during branch operations |
| Behind integration (> 0) | Sync via `/sync-branch` | Stale branches increase merge conflict risk |
| No remote tracking | Push with tracking: `git push -u origin <branch>` | Remote tracking enables collaboration and backup |
| No integration branch | Create integration branch | Required by the branching model |
| Unpushed commits (> 0) | Push to remote: `git push` | Unpushed commits are not backed up |
| Pushed but no PR | Create PR via `/create-pr` | Changes won't reach integration without a PR |
| Last commit > 7 days ago | Sync via `/sync-branch` | Long-idle branches accumulate drift |
| Stashed changes (> 0) | Review stash: `git stash list` | Forgotten stashes may contain important work |
| Not in worktree & git lock files detected | Create worktree for parallel work | Concurrent git operations detected — two instances sharing one working directory will silently corrupt each other's files |

#### Worktree Isolation Recommendation

When the script reports `worktree_count:1` (no worktrees) and `is_worktree:false`
(main repo), check if multiple feature branches or collaborators are active.

If multi-instance risk is detected, present this recommendation:

```
[N] Recommendation: Use git worktree for branch isolation
    Reason:         Multiple feature branches are active on this repo. If another
                    Claude instance or developer checks out a different branch in
                    this same directory, both instances will silently corrupt each
                    other's working files.
    Solution:       Use Claude Code's built-in worktree capability:
                    • Say "start a worktree" to Claude Code (triggers EnterWorktree)
                    • Or use the superpowers:using-git-worktrees skill
                    These will create an isolated working directory with its own
                    branch checkout, sharing the same .git repository.
    Approve? (y/n)
```

If the user approves, guide them to invoke Claude Code's `EnterWorktree` tool
or the `superpowers:using-git-worktrees` skill — do NOT implement worktree
management directly, delegate to the built-in capability.

### Step 4 — Execute Approved Actions

For each recommendation the user approves:
1. Execute the recommended action
2. Report the result
3. If the action fails, explain why and suggest alternatives

### Step 5 — Summary

```
Status Check Complete
=====================
Issues found:    <N>
Actions taken:   <N>
Actions skipped: <N>
Current status:  <OK or remaining issues>
```

## Behavior Rules

- **Never auto-execute**: Every recommendation requires explicit user approval
- **Present all recommendations at once**: Let user review full list
- **Accept batch approvals**: User can say "approve all" or "approve 1, 3"
- **No false urgency**: Present facts objectively
- **Graceful with missing tools**: If `gh` CLI unavailable, skip GitHub checks
