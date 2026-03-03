---
name: create-pr
description: This skill should be used when the user asks to "create a PR", "open a pull request", "submit my changes", "merge my feature", or when feature work is ready for review. Creates a PR to integration with SemVer labeling, file-level conflict detection, and cloud review tracking with review-watcher teammate for PRs targeting main.
user_invocable: true
---

# /create-pr — Create Pull Request

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Create a well-structured Pull Request targeting `integration`, with automated
conflict detection, SemVer labeling, and scope validation.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`
2. Check `gh` CLI: run `which gh`. If missing, block with install instructions.

## Steps

### Step 1 — Run Pre-flight Script

Execute the backing script to collect all PR-relevant data:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/create-pr-preflight.sh"
```

Parse the JSON output:

| Field | Description |
|-------|-------------|
| `status` | `ok` or `error` |
| `branch` | Current branch name |
| `commits_ahead` | Number of commits ahead of integration |
| `changed_files` | Count of changed files |
| `file_list` | Array of changed file paths |
| `semver_suggestion` | Suggested SemVer level (patch/minor/major) |
| `pr_conflicts` | Array of conflicting PRs with overlapping files |
| `scope_warning` | Boolean — true if >20 files changed |

### Step 2 — Sync If Needed

Check if the branch is behind integration. If so, suggest running `/sync-branch`
first.

### Step 3 — Display Pre-flight Results

Show the user:
- Files changed: list and count
- SemVer suggestion with rationale
- Any conflict warnings with open PRs
- Scope warning if >20 files

### Step 4 — Handle Conflicts

For each entry in `pr_conflicts`:
- "⚠️ Potential conflict with PR #[number] '[title]' — both modify: [files]"
- Warn but do not block

### Step 5 — Collect PR Metadata

Prompt the user for or auto-generate:
- **Title**: In Conventional Commit format (e.g., `feat(auth): add OAuth2 login`)
- **Summary**: What this PR does and why
- **Testing Plan**: How to verify the changes
- **Risk & Rollback**: What could go wrong and how to revert
- **Impacted Areas**: Which parts of the codebase are affected

### Step 6 — Create PR

```bash
gh pr create --base integration --title "<title>" --body "<formatted body>"
```

### Step 7 — Apply SemVer Label

Use the `semver_suggestion` from the script (or user override):

```bash
gh pr edit <pr-number> --add-label "semver:<level>"
```

If label doesn't exist, create it first.

### Step 8 — Display Result

Show:
- PR URL
- SemVer label applied
- Any conflict warnings from pre-flight
- "PR created successfully. It will be reviewed and merged via the merge queue."

### Step 9 — Register in Review Tracker (PRs targeting main only)

If the PR targets `main` (cloud code review will be triggered):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-tracker.sh" register <pr_number> <branch_name>
```

Inform the user: "PR registered for cloud review tracking."

### Step 10 — Spawn review-watcher Teammate

Offer to start automated review monitoring:

"Cloud code review will run on GitHub Actions (typically 5-15 minutes).
I can spawn a review-watcher teammate to monitor the review and auto-fix code-level issues.
You can continue working on other tasks while it monitors."

If user agrees, use the Agent tool to spawn the review-watcher:
- subagent_type: `git-collaboration-workflow:review-watcher`
- name: `review-watcher`
- prompt: "Monitor PR #<number> on branch <branch>. Poll review status every 60 seconds. When review completes, fetch comments, auto-fix code-level issues, and SendMessage logic-level issues to the main controller."
- run_in_background: true

Inform the user:
- "review-watcher teammate spawned. It will notify you when the review completes."
- "Run `/check-review` anytime to manually check status."
- "Continue working — you'll receive a message when review results are ready."

## Error Handling

- If `gh pr create` fails due to authentication, guide user through `gh auth login`
- If no commits ahead of integration, abort with message
- If on protected branch, abort with guidance to switch to feature branch
