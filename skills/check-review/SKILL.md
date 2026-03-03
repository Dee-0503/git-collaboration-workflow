---
name: check-review
description: This skill should be used when the user asks to "check review status", "what did the review say", "check my PR review", "review results", or wants to see cloud code review feedback. Queries PR review status from GitHub and local tracker DB, displays inline comments grouped by file, and can re-spawn the review-watcher teammate.
user_invocable: true
---

# /check-review — Check Cloud Review Status

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Query the cloud code review status for the current branch's PR, display
review comments locally, and optionally re-spawn the review-watcher teammate
for automated monitoring and fixing.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`
2. Check `gh` CLI: run `which gh`. If missing, block with install instructions.

## Steps

### Step 1 — Determine PR Number

Find the PR for the current branch:

```bash
gh pr view --json number,state,title,url --jq '{number, state, title, url}'
```

If no PR exists, inform the user and exit.

### Step 2 — Check Tracker DB Status

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-tracker.sh" status <pr_number>
```

Parse the JSON output. Display:
- Current status (pending_review / review_done / fixing / passed / closed)
- Current round number
- Last check timestamp

### Step 3 — Check Actions Status

```bash
gh pr checks <pr_number>
```

Display whether the review action is still running, completed, or failed.

### Step 4 — Fetch Review Comments

If the review action has completed:

```bash
# Inline comments
OWNER_REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api "repos/$OWNER_REPO/pulls/<pr_number>/comments" \
  --jq '.[] | {path, line, body, created_at}'

# Review-level comments
gh api "repos/$OWNER_REPO/pulls/<pr_number>/reviews" \
  --jq '.[] | select(.body != "" and .body != null) | {state, body}'
```

### Step 5 — Display Results

Group inline comments by file path:

```
scripts/setup-github-repo.sh
  L196: "check_api_secret checks wrong secret name..."
  L338: "Heredoc delimiter style inconsistency..."

hooks/hooks.json
  (no comments)
```

For each comment, categorize as:
- **Code-level** (syntax, formatting, variables): "Can be auto-fixed"
- **Logic-level** (architecture, design): "Needs human decision"

### Step 6 — Offer Actions

Present options to the user:
1. **Start review-watcher** — Spawn a review-watcher teammate to auto-monitor and fix
2. **Fix manually** — User will fix issues themselves
3. **Dismiss** — Do nothing now, check again later

### Step 7 — Spawn Teammate (if chosen)

If user chooses to start review-watcher:

1. Update tracker DB:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-tracker.sh" update <pr_number> "pending_review" <comment_count>
   ```

2. Use the Agent tool to spawn a `review-watcher` teammate:
   - subagent_type: `git-collaboration-workflow:review-watcher`
   - prompt: "Monitor PR #<number> on branch <branch>. Poll review status and handle fixes."
   - run_in_background: true

## Error Handling

- If `gh` CLI not authenticated: guide through `gh auth login`
- If no PR for current branch: suggest `/create-pr` first
- If Actions still running: show progress and suggest waiting
- If review-watcher already running: inform user, no duplicate spawn
