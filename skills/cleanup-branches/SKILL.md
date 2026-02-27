---
name: cleanup-branches
description: This skill should be used when the user asks to "clean up branches", "delete merged branches", "prune stale branches", "tidy up the repo", or when merged branches need removal. Identifies and deletes merged/stale branches from remote and local with user confirmation.
user_invocable: true
---

# /cleanup-branches — Branch Cleanup

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Identify merged and stale branches, present them for review, and delete
confirmed branches from both remote and local.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`
2. Verify git remote is configured: `git remote -v`

## Steps

### Step 1 — Collect Cleanup Data

Execute the backing script to find cleanup candidates:

```bash
# Remote branches only
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-branches.sh"

# Include local branches too
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-branches.sh" --include-local
```

Parse the JSON output:

| Field | Description |
|-------|-------------|
| `status` | `ok` |
| `merged_remote` | Array of merged remote branch names |
| `merged_remote_count` | Count of merged remote branches |
| `merged_local` | Array of merged local branch names |
| `merged_local_count` | Count of merged local branches |
| `stale_count` | Count of stale branches (>30 days, not merged) |
| `total_candidates` | Total cleanup candidates |

### Step 2 — Display Candidates

If `total_candidates` is 0:
- Report: "No stale branches found. Repository is clean."
- Stop.

Otherwise, show the list:

```
Merged branches ready for cleanup:
  1. feature/alice-login       (remote)
  2. feature/bob-api-refactor  (remote)
  3. hotfix/fix-auth           (remote + local)
  4. feature/old-experiment    (local only)
```

### Step 3 — Confirm Deletion

Ask user: "Delete all listed branches? Or specify numbers to delete selectively (e.g., '1,3' or 'all')."

### Step 4 — Delete Confirmed Branches

For each confirmed remote branch:
```bash
git push origin --delete <branch-name>
```

For each confirmed local branch:
```bash
git branch -d <branch-name>
```

### Step 5 — Prune Remote References

```bash
git remote prune origin
```

### Step 6 — Report

Display cleanup summary:
- N remote branches deleted
- N local branches deleted
- Any branches that could not be deleted (with reason)
- "Repository cleaned up. Only active branches remain."

## Error Handling

- If a branch deletion fails, use `git branch -d` (safe delete) and report
- Never use `-D` (force delete) without explicit user confirmation
- If script not found, fall back to running git commands directly
