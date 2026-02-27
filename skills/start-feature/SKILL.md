---
name: start-feature
description: This skill should be used when the user asks to "start a feature", "create a branch", "new feature branch", "begin working on a new feature", or mentions starting new development work on a feature branch. Creates a validated feature branch from integration with remote tracking, worktree isolation guidance, and active PR conflict early warning.
user_invocable: true
---

# /start-feature — Create Feature Branch

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Create a properly named feature branch from the latest `integration` branch,
with remote tracking configured.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`
2. Verify `git` is available.

## Steps

### Step 1 — Collect Input

Ask the user for:

- **Contributor ID** (e.g., alice, bob, agent-1)
- **Feature slug** (short kebab-case description, e.g., login-page, api-refactor)

### Step 2 — Run Setup Script

Execute the backing script to handle all git operations atomically:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/start-feature.sh" "<contributor-id>" "<feature-slug>"
```

Parse the JSON output:

| Field | Description |
|-------|-------------|
| `status` | `ok` or `error` |
| `branch` | Created branch name (e.g., `feature/alice-login`) |
| `base` | Base branch (`origin/integration`) |
| `head` | Short commit hash of branch HEAD |
| `tracking` | Remote tracking branch |
| `message` | Error description (if status is error) |
| `uncommitted` | Number of uncommitted changes (0 if clean) |
| `uncommitted_warning` | Warning message if uncommitted changes exist, empty string if clean |
| `is_worktree` | Whether current directory is a git worktree |
| `worktree_count` | Number of active worktrees for this repository |
| `worktree_recommendation` | `none` or `suggested` — whether worktree isolation is recommended |
| `active_prs` | Array of open PRs with their file lists (for conflict early warning) |

### Step 3 — Handle Result

**If `status` is `error`**:
- Display the error message to the user
- If branch name validation failed, show valid examples:
  `feature/alice-login`, `feature/bob-api-refactor`
- Ask the user to provide corrected components

**If `status` is `ok` and `uncommitted` > 0**:
- Show the `uncommitted_warning` message
- Ask user if they want to continue, stash, or commit first
- Branch was already created — if user wants to go back, provide
  `git checkout - && git branch -d <branch>` to undo

**If `status` is `ok` and `uncommitted` is 0**:
- Display success confirmation:
  - Branch name created
  - Base branch (integration at commit SHA)
  - Remote tracking status

### Step 4 — Worktree Isolation Recommendation

If `worktree_recommendation` is `suggested`, present this to the user **before**
the PR conflict warning:

```
💡 Multi-instance isolation recommended
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Other feature branches are active on this repository. If another Claude instance
or developer is working simultaneously in this same directory, both will silently
corrupt each other's working files (checkout overwrites the working directory).

Recommended solutions (choose one):
1. Use Claude Code's built-in worktree — say "start a worktree" or invoke
   superpowers:using-git-worktrees skill (creates isolated working directory)
2. Use a separate git clone for each parallel instance
3. Continue in current directory (safe only if working alone)
```

If the user chooses option 1, guide them to invoke Claude Code's `EnterWorktree`
tool — do NOT create worktrees directly. The built-in tool handles directory
creation, branch association, and cleanup on session exit.

If `is_worktree` is `true`, display a brief confirmation:
- "You're working in a git worktree — branch isolation is active."

### Step 5 — Active PR Conflict Early Warning

If `active_prs` is non-empty, display a file landscape of all open PRs:

```
⚠️ Active PRs on integration — watch for file overlaps:
  PR #42 "feat(auth): add OAuth2 login" (feature/alice-oauth)
     → src/auth.ts, src/middleware/auth.ts, src/config.ts (3 files)
  PR #58 "refactor: extract utils" (feature/bob-utils)
     → src/utils/index.ts, src/helpers.ts (2 files)
```

Then advise:
- "If your feature will modify any of these files, coordinate with the PR author
  to avoid merge conflicts."
- "Use `/review-pr <number>` to inspect a specific PR's changes."
- "You're ready to start development. Use `/sync-branch` to stay updated with integration."

## Error Handling

- If the script is not found, fall back to running git commands directly:
  1. `git fetch origin`
  2. `git checkout origin/integration -b feature/<id>-<slug>`
  3. `git push -u origin feature/<id>-<slug>`
- If the branch name already exists, suggest a different name
- If `origin/integration` doesn't exist, guide user to create it
