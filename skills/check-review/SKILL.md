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
- Current status (pending_review / fixing / passed / closed)
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
gh api --paginate "repos/$OWNER_REPO/pulls/<pr_number>/comments" \
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

2. Create a team and spawn the review-watcher as a teammate
   (TeamCreate, TaskCreate, and Agent are Claude Code built-in tools,
   available in the CLI environment — not part of the Claude Agent SDK):

   a. Use the **TeamCreate** tool:
      - team_name: `pr-<pr_number>-review`

   b. Use the **TaskCreate** tool:
      - subject: `Monitor PR #<pr_number> cloud review`
      - description: `Poll review status, auto-fix code-level issues, SendMessage logic-level issues`

   c. Use the **Agent** tool to spawn the review-watcher teammate:
      - subagent_type: `git-collaboration-workflow:review-watcher`
      - name: `review-watcher`
      - team_name: `pr-<pr_number>-review`
      - prompt: "Monitor PR #<pr_number> on branch <branch>. Poll review status and handle fixes. SendMessage findings to team lead."

## Error Handling

- If `gh` CLI not authenticated: guide through `gh auth login`
- If no PR for current branch: suggest `/create-pr` first
- If Actions still running: show progress and suggest waiting
- If review-watcher already running: inform user, no duplicate spawn
