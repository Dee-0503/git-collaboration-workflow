---
name: setup-repo
description: This skill should be used when the user asks to "setup repo", "set up repository", "configure github", "protect branches", "setup github repository", "create github repo", "enable branch protection", "configure merge settings", "initialize repo settings", or wants to apply Git Collaboration Architecture best practices to a GitHub repository. Detects missing or misconfigured settings and applies them with user approval.
user_invocable: true
---

# /setup-repo — GitHub Repository Best-Practice Setup

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Detect and configure GitHub repository settings to match the Git Collaboration
Architecture best practices: squash-only merges, branch protection on `main`
and `integration`, SemVer labels, and auto-delete of merged branches.

## Automatic Triggering

This skill is **automatically invoked** by the SessionStart hook when:
- No GitHub remote is detected (instant check, no API call)
- The SessionStart `systemMessage` contains `autoInvokeSkill: "setup-repo"`

When auto-invoked, follow the same steps below but skip the pre-flight (the
SessionStart hook has already confirmed the git repo context). Start directly
at Step 1 — Check Current State.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`
2. Verify `gh` CLI is installed and authenticated: `gh auth status`

## Steps

### Step 1 — Check Current State

Execute the backing script in check mode:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-github-repo.sh" check
```

Parse the JSON output:

| Field | Description |
|-------|-------------|
| `status` | `ok`, `needs_setup`, `no_remote`, or `error` |
| `has_remote` | Whether a GitHub remote exists |
| `repo` | GitHub owner/repo identifier |
| `repo_url` | Full GitHub repository URL |
| `finding_count` | Number of issues detected |
| `findings` | Array of issues with id, category, description, current/expected values |
| `message` | Error or status description |

### Step 2 — Handle No Remote

**If `status` is `no_remote`**:

Present this to the user:

```
No GitHub remote detected
========================
This repository has no GitHub remote configured. A GitHub repository is needed
for pull requests, code review, branch protection, and merge queue.

Options:
1. Create a new GitHub repository (public)
2. Create a new GitHub repository (private)
3. Add an existing remote manually: git remote add origin <url>
```

If the user chooses option 1 or 2, run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-github-repo.sh" create-and-apply <visibility>
```

Where `<visibility>` is `public` or `private` based on user choice.

If the user chooses option 3, guide them to add the remote and re-run
`/setup-repo` afterward.

### Step 3 — Present Findings

**If `status` is `ok`**: Report all settings match best practices. No action needed.

**If `status` is `needs_setup`**: Present a formatted report:

```
GitHub Repository Health Check
==============================
Repository:  <repo_url>
Issues:      <finding_count>

Findings:
  [1] <category>: <description>
      Current: <current>  Expected: <expected>
  [2] ...
```

Group findings by category:
- **repo**: Repository-level merge settings
- **branch**: Missing branches
- **protection**: Branch protection rules
- **labels**: Missing SemVer labels
- **workflow**: Claude Code GitHub Actions workflow files and API key secret

### Step 4 — Apply Fixes

Ask the user for approval before applying:

```
Apply all recommended GitHub settings? This will:
- Set squash-only merge strategy (disable merge commits and rebase)
- Enable auto-delete of merged branches
- Add branch protection to main (require 1 PR review, enforce admins, linear history)
- Add branch protection to integration (require PR, enforce admins)
- Create SemVer labels (semver:patch, semver:minor, semver:major)
- Create Claude Code workflow files for @claude interaction and auto PR review

Approve? (y/n)
```

On approval, execute:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-github-repo.sh" apply
```

Parse the JSON output:

| Field | Description |
|-------|-------------|
| `status` | `ok` or `partial` |
| `action_count` | Number of settings applied |
| `actions` | Array of actions taken |
| `error_count` | Number of failures (if partial) |
| `errors` | Array of error descriptions |
| `manual_steps` | Array of steps requiring manual GitHub UI action |

### Step 5 — Report Results

Present applied actions and remaining manual steps:

```
Setup Complete
==============
Actions taken:   <action_count>
  - <action 1>
  - <action 2>

Manual steps remaining:
  1. Enable merge queue in GitHub Settings > Branches > integration rule
  2. Add required status checks after CI is configured
  3. Create CODEOWNERS file for code review routing
```

If any errors occurred (`status` is `partial`), present them separately with
troubleshooting guidance.

## Error Handling

- If `gh` CLI is not installed, provide installation instructions for the
  user's platform (macOS: `brew install gh`, Linux: `sudo apt install gh`)
- If `gh` is not authenticated, guide: `gh auth login`
- If branch protection fails on integration with 0 reviews, the script
  automatically retries with 1 review (free GitHub plan limitation)
- If the script is not found, fall back to running `gh api` commands directly

## Behavior Rules

- **Never auto-apply**: All changes require explicit user approval
- **Present all findings at once**: Let user review the full picture
- **Graceful degradation**: If a setting cannot be applied, continue with others
- **Report manual steps**: Some settings (merge queue, status checks) require
  GitHub UI and cannot be automated via API
