---
name: sync-branch
description: This skill should be used when the user asks to "sync my branch", "rebase onto integration", "update my branch", "pull latest changes", or when a branch is behind integration. Rebases the current feature branch onto latest integration with conflict resolution guidance.
user_invocable: true
---

# /sync-branch — Sync Feature Branch

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Rebase the current feature branch onto the latest `integration` to minimize
merge conflicts and keep the branch up to date.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`

## Steps

### Step 1 — Run Sync Script

Determine if auto-stash is appropriate (if working tree is dirty, ask user
whether to auto-stash or manually handle changes first).

Execute the backing script:

```bash
# Without auto-stash (will error if dirty)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-branch.sh"

# With auto-stash (stashes uncommitted changes, rebases, restores)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-branch.sh" --auto-stash
```

Parse the JSON output:

| Field | Description |
|-------|-------------|
| `status` | `ok`, `error`, or `conflict` |
| `branch` | Current branch name |
| `rebased_onto` | Base ref rebased onto |
| `commits_applied` | Number of commits rebased |
| `head` | New HEAD commit hash |
| `push` | `pushed` or `push_failed` |
| `stash_restored` | Whether stash was restored |
| `conflict_count` | Number of conflicting files (if status=conflict) |
| `conflict_files` | Comma-separated conflicting file paths |

### Step 2 — Handle Result

**If `status` is `ok`**:
- Display success:
  - Branch name
  - Number of commits rebased
  - Push status
  - Stash restoration status
  - "Branch synced with integration successfully."

**If `status` is `conflict`**:
1. List conflicting files
2. For each conflicting file:
   - Read and show both sides of the conflict
   - Assist the user in choosing the correct resolution
   - After resolution: `git add <resolved-file>`
3. Continue rebase: `git rebase --continue`
4. If too complex: offer `git rebase --abort`

**If `status` is `error`**:
- Display the error message
- Suggest appropriate next steps

### Step 3 — Post-Sync Verification

Display:
- Current branch name
- Number of commits ahead/behind integration
- Push status (success or needs retry)

## Error Handling

- If the script is not found, fall back to running git commands directly
- If `--force-with-lease` is rejected, explain someone else may have pushed
- If `git fetch` fails, suggest checking network connectivity
