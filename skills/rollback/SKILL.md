---
name: rollback
description: This skill should be used when the user asks to "rollback", "revert the release", "undo the deployment", "roll back production", or when the latest release needs to be reverted. Safely reverts the latest release on main via git revert with risk assessment.
user_invocable: true
---

# /rollback — Production Rollback

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Safely revert the latest production release using `git revert` (not force push).
Collects release data, presents risk assessment, and guides the full rollback
with user confirmation at each step.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`
2. Check `gh` CLI: run `which gh`. If missing, block with install instructions.
3. Confirm with user: "This will revert the latest release on main. This is a production-impacting action. Continue?"

## Steps

### Step 1 — Collect Rollback Data

Execute the backing script to gather release information:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/rollback-preflight.sh"
```

Parse the JSON output:

| Field | Description |
|-------|-------------|
| `status` | `ok` or `error` |
| `latest_release` | Current release tag (e.g., `v1.3.0`) |
| `previous_release` | Tag to roll back to (e.g., `v1.2.0`) |
| `main_head` | Short hash of main HEAD |
| `release_commit` | Object with `message`, `date`, `author` |
| `release_stats` | Object with `commits`, `files_changed`, `commits_after_tag` |
| `revert_complexity` | `simple` or `complex` |
| `release_pr` | PR number and title (if found) |
| `rollback_target` | Version being restored |

### Step 2 — Present Risk Assessment

Display to the user:
- Release being reverted: version, date, author
- Release scope: N commits, N files changed
- Rollback target: previous version
- Complexity: simple (direct revert) or complex (post-release commits exist)
- "Rolling back release `<latest>` to restore `<previous>`. Proceed?"

### Step 3 — Execute Rollback

```bash
git checkout main && git pull origin main
git revert HEAD --no-edit
git commit --amend -m "revert: rollback release <version>"
```

### Step 4 — Push via PR (if branch protection)

```bash
git checkout -b rollback/<version>
git push -u origin rollback/<version>
gh pr create --base main --title "revert: rollback release <version>" \
  --body "## Rollback\n\nReverting release <version>.\n\n## Verification\n- [ ] Production monitoring shows no regression\n- [ ] Previous version functionality restored"
```

### Step 5 — After Merge — Verify

```bash
git checkout main && git pull origin main
git describe --tags origin/main
```

### Step 6 — Optionally Revert on Integration

Ask user: "Do you also want to revert the corresponding feature on integration?"

### Step 7 — Confirm

Display:
- Release reverted
- New patch version tag
- Integration status
- "Rollback complete. Previous stable version restored."

## Error Handling

- If `git revert` conflicts, assist with resolution
- If no tags exist, abort: "No release tags found on main."
- Never use `git reset --hard` or force push. Always use `git revert`
- If script not found, fall back to running git commands directly
