---
name: hotfix
description: This skill should be used when the user asks to "create a hotfix", "fix production issue", "emergency fix", "hotfix branch", or when there is a production bug requiring immediate patching. Creates a hotfix branch from main with guided fix, PR creation, and cherry-pick to integration.
user_invocable: true
---

# /hotfix — Emergency Hotfix

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Create and manage an emergency hotfix branch from `main` for production issues.
Handles branch creation, fix guidance, PR creation, and cherry-pick to integration.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`
2. Confirm with user: "This workflow creates a hotfix directly from main for emergency production issues. Continue?"

## Steps

### Step 1 — Collect Hotfix Name

Ask the user for a short hotfix description (e.g., `fix-auth-crash`).

### Step 2 — Run Setup Script

Execute the backing script to create the hotfix branch atomically:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/hotfix-setup.sh" "<hotfix-slug>"
```

Parse the JSON output:

| Field | Description |
|-------|-------------|
| `status` | `ok`, `error`, or `warning` |
| `branch` | Created branch name (e.g., `hotfix/fix-auth-crash`) |
| `base` | Base branch (`origin/main`) |
| `base_version` | Current release version on main |
| `head` | Short commit hash |
| `tracking` | Remote tracking branch |
| `next_steps` | Array of suggested actions |

### Step 3 — Handle Result

**If `status` is `error`**:
- Display the error and guide accordingly

**If `status` is `ok`**:
- Display branch info and instruct the user:
  - Make the minimal fix needed
  - Use `fix:` commit prefix: `git commit -m "fix: <description>"`
  - Keep changes focused — hotfixes should be small and targeted

### Step 4 — Guide the Fix

Wait for the user to make their fix. Assist if needed.

### Step 5 — Create PR to Main

After the fix is committed:

```bash
gh pr create --base main --title "fix: <description>" --body "<hotfix details>"
gh pr edit <pr-number> --add-label "semver:patch"
```

### Step 6 — After Merge — Verify Tag

Once the PR is merged:

```bash
git checkout main && git pull origin main
git describe --tags origin/main
```

### Step 7 — Cherry-pick to Integration

```bash
git checkout integration && git pull origin integration
git cherry-pick <merge-commit-sha>
git push origin integration
```

If cherry-pick conflicts, assist with resolution.

### Step 8 — Clean Up

```bash
git push origin --delete hotfix/<name>
git branch -d hotfix/<name>
```

### Step 9 — Confirm

Display:
- Hotfix merged to main
- New patch version tag
- Cherry-picked to integration
- Hotfix branch deleted
- "Emergency fix deployed. Monitor production for stability."

## Error Handling

- If cherry-pick to integration fails, guide manual conflict resolution
- If the hotfix branch already exists, suggest a different name
- If script not found, fall back to running git commands directly
