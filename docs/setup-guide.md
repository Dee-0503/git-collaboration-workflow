# Git Collaboration Workflow Plugin — Complete Setup Guide

From zero to a fully configured Git collaboration environment.

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Repository Setup](#2-repository-setup)
3. [Plugin Installation](#3-plugin-installation)
4. [GitHub Configuration](#4-github-configuration)
5. [Team Onboarding](#5-team-onboarding)
6. [Plugin Reference](#6-plugin-reference)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Prerequisites

### Required

| Tool | Min Version | Purpose | Install |
|------|-------------|---------|---------|
| Git | 2.30+ | Version control | https://git-scm.com/ |
| Claude Code | Latest or previous major | AI coding assistant | https://claude.ai/download |
| GitHub CLI (`gh`) | 2.0+ | PR creation & merge queue | https://cli.github.com/ |

### Verify Installation

```bash
git --version        # >= 2.30
claude --version     # Latest or previous major
gh --version         # >= 2.0
gh auth status       # Must show "Logged in"
```

---

## 2. Repository Setup

### 2.1 Create the Branching Model

If starting from scratch:

```bash
# Initialize repository
git init my-project && cd my-project

# Create initial commit
echo "# My Project" > README.md
git add README.md
git commit -m "chore: initial commit"

# Push to GitHub
gh repo create my-project --public --source=. --push

# Create integration branch from main
git checkout -b integration
git push -u origin integration

# Return to main
git checkout main
```

If the repository already exists:

```bash
cd my-project
git checkout main
git pull origin main

# Create integration branch (if it doesn't exist)
git checkout -b integration
git push -u origin integration
git checkout main
```

### 2.2 Verify Branch Structure

```bash
git branch -a
```

Expected output:

```
* main
  integration
  remotes/origin/main
  remotes/origin/integration
```

---

## 3. Plugin Installation

### 3.1 Copy the Plugin

```bash
# From the plugin source directory
cp -r git-collaboration-workflow/ /path/to/your/repo/.claude/plugins/git-collaboration-workflow/
```

Or if the plugin is in a shared location:

```bash
# Create plugins directory
mkdir -p .claude/plugins

# Copy plugin
cp -r /path/to/git-collaboration-workflow .claude/plugins/
```

### 3.2 Verify Plugin Structure

```bash
ls -la .claude/plugins/git-collaboration-workflow/
```

Expected:

```
.secretsignore
plugin.json
VALIDATION.md
hooks/
  hooks.json
skills/
  start-feature.md
  sync-branch.md
  create-pr.md
  prepare-release.md
  hotfix.md
  rollback.md
  cleanup-branches.md
agents/
  merge-bot.md
```

### 3.3 Configure Secret Whitelist (Optional)

If your project has known false-positive credential patterns (e.g., test
API keys, fixture data), edit `.secretsignore`:

```bash
# Edit the plugin's secretsignore
vim .claude/plugins/git-collaboration-workflow/.secretsignore
```

Or create a project-level `.secretsignore` in your repo root:

```bash
cat > .secretsignore << 'EOF'
# Test fixture API keys
AKIA_TEST_[A-Z0-9]{16}
sk-test-[a-zA-Z0-9]{48}

# Documentation placeholder tokens
EXAMPLE_API_KEY_[A-Z0-9]+
your-api-key-here
EOF
```

### 3.4 Restart Claude Code

Hooks are loaded at session start. Restart Claude Code to activate:

```bash
# Exit current session (Ctrl+C or type /exit)
# Then restart
claude
```

### 3.5 Verify Plugin is Active

In Claude Code, try a forbidden operation:

```bash
# This should be BLOCKED:
git commit -m "fixed stuff"

# This should SUCCEED:
git commit -m "feat: add initial feature"
```

---

## 4. GitHub Configuration

### 4.1 Branch Protection Rules

Go to **Settings > Branches > Add branch protection rule**.

#### For `main`:

| Setting | Value |
|---------|-------|
| Branch name pattern | `main` |
| Require a pull request before merging | ✅ |
| Required approvals | 1 (from CODEOWNERS) |
| Dismiss stale approvals | ✅ |
| Require status checks to pass | ✅ |
| Require linear history | ✅ |
| Restrict who can push | ✅ (only merge queue) |
| Allow squash merging (only) | ✅ |

#### For `integration`:

| Setting | Value |
|---------|-------|
| Branch name pattern | `integration` |
| Require a pull request before merging | ✅ |
| Required approvals | 0 (CI-only gate) |
| Require status checks to pass | ✅ |
| Allow squash merging (only) | ✅ |

### 4.2 Enable Merge Queue

Go to **Settings > Branches > `integration` rule > Merge queue**:

| Setting | Value |
|---------|-------|
| Enable merge queue | ✅ |
| Build concurrency | 5 (adjust per CI capacity) |
| Minimum group size | 1 |
| Maximum group size | 5 |
| Wait time (minutes) | 5 |
| Merge method | Squash |

### 4.3 Create SemVer Labels

```bash
gh label create "semver:patch" --color "0e8a16" --description "Patch version bump (bug fixes)"
gh label create "semver:minor" --color "1d76db" --description "Minor version bump (new features)"
gh label create "semver:major" --color "d93f0b" --description "Major version bump (breaking changes)"
```

### 4.4 Set Up CODEOWNERS

```bash
cat > .github/CODEOWNERS << 'EOF'
# Default owners for everything
* @your-org/core-team

# Critical paths require senior review
/src/auth/     @your-org/security-team
/src/payments/ @your-org/payments-team
EOF

git add .github/CODEOWNERS
git commit -m "chore: add CODEOWNERS file"
git push origin main
```

### 4.5 Configure Required Status Checks

In branch protection settings, add these status checks:

- `ci/tests` (your test suite)
- `ci/lint` (code linting)
- `ci/build` (build verification)
- `ci/commitlint` (conventional commits check — optional server-side backup)

---

## 5. Team Onboarding

### 5.1 Daily Workflow Cheat Sheet

Share this with your team:

```
┌─────────────────────────────────────────────────────────┐
│              Git Collaboration Workflow                  │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Start work:     /start-feature                         │
│  Stay in sync:   /sync-branch                           │
│  Open a PR:      /create-pr                             │
│  Release:        /prepare-release                       │
│  Emergency fix:  /hotfix                                │
│  Rollback:       /rollback                              │
│  Clean up:       /cleanup-branches                      │
│                                                         │
│  ⛔ Forbidden:                                          │
│     git push origin main        (use PRs)               │
│     git push --force origin main (history is sacred)    │
│     git rebase (while on main)  (shared branch)         │
│     git commit -m "bad msg"     (use conventional)      │
│                                                         │
│  ✅ Commit format:                                      │
│     feat: add login page                                │
│     fix(auth): resolve token expiry                     │
│     docs: update API reference                          │
│                                                         │
│  ✅ Branch format:                                      │
│     feature/alice-login                                 │
│     hotfix/fix-auth-crash                               │
│     release/v1.2.0                                      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 5.2 For AI Instances

When setting up multiple AI agents:

1. Each agent should use a unique contributor ID (e.g., `agent-1`, `agent-2`)
2. Each agent creates its own feature branch via `/start-feature`
3. Agents should `/sync-branch` frequently to reduce merge conflicts
4. Agents should keep PRs small (< 20 files) to avoid queue ejections
5. Module-scoped work prevents file-level conflicts between agents

### 5.3 First Feature Walk-through

```bash
# 1. Start Claude Code in your project
claude

# 2. Create a feature branch
> /start-feature
#    → Enter contributor ID: alice
#    → Enter feature slug: add-login
#    → Creates: feature/alice-add-login

# 3. Make changes and commit
> # ... write code ...
> git add src/login.ts
> git commit -m "feat(auth): add login page component"

# 4. Sync with integration
> /sync-branch
#    → Rebases onto latest integration

# 5. Create a PR
> /create-pr
#    → Syncs branch
#    → Generates PR with template
#    → Applies semver:minor label
#    → Checks for conflicts with other PRs
```

---

## 6. Plugin Reference

### 6.1 Hooks

| Hook | Event | Trigger | Behavior |
|------|-------|---------|----------|
| prevent-direct-push | PreToolUse | `git push` to main/integration | Hard-block (main), Soft-block (integration) |
| prevent-force-push | PreToolUse | `git push --force` | Hard-block (main), Soft-block (integration), Warn (feature) |
| prevent-rebase-shared | PreToolUse | `git rebase` on main/integration | Hard-block |
| detect-conflict-markers | PreToolUse | `git commit`/`git add` | Hard-block if markers found |
| enforce-commit-format | PreToolUse | `git commit -m` | Block non-conventional messages |
| enforce-branch-naming | PreToolUse | `git checkout -b` | Block invalid branch names |
| detect-secrets | PreToolUse | `git add`/`git commit` | Hard-block credentials (whitelist via .secretsignore) |
| pr-scope-check | PostToolUse | `git diff --stat` | Warn if > 20 files changed |
| repo-status-check | SessionStart | Session begins | Auto-detect repo state, recommend actions with reasons, require approval |

### 6.2 Skills

| Skill | Command | Purpose |
|-------|---------|---------|
| Start Feature | `/start-feature` | Create validated feature branch from integration |
| Sync Branch | `/sync-branch` | Rebase feature onto latest integration |
| Create PR | `/create-pr` | PR with template, SemVer label, conflict check |
| Prepare Release | `/prepare-release` | Release PR from integration to main |
| Hotfix | `/hotfix` | Emergency fix from main + cherry-pick to integration |
| Rollback | `/rollback` | Revert latest release on main |
| Cleanup Branches | `/cleanup-branches` | Delete merged feature branches |
| Check Status | `/check-status` | On-demand repo health check with actionable recommendations |
| Repo Graph | `/repo-graph` | Visualize branch topology and commit history as Mermaid diagrams |
| Review PR | `/review-pr` | Structured code review with 5 lenses (correctness, security, performance, style, architecture) |

### 6.3 Agent

| Agent | Purpose | Tools | Max Turns |
|-------|---------|-------|-----------|
| merge-bot | Auto-enqueue approved PRs to merge queue | Bash, Read | 10 |

### 6.4 Blocking Tiers

```
                    ┌─────────┐
                    │  main   │  Hard-block (no bypass)
                    └────┬────┘
                         │
                    ┌────┴────┐
                    │integra- │  Soft-block (user can confirm)
                    │  tion   │
                    └────┬────┘
                         │
              ┌──────────┼──────────┐
              │          │          │
         ┌────┴───┐ ┌───┴────┐ ┌──┴─────┐
         │feature/│ │hotfix/ │ │release/│  Warn-only
         │  ...   │ │  ...   │ │  ...   │  (allowed)
         └────────┘ └────────┘ └────────┘
```

---

## 7. Troubleshooting

### Plugin not loading

```bash
# Check plugin directory location
ls .claude/plugins/git-collaboration-workflow/plugin.json

# Restart Claude Code
claude

# Check with debug mode
claude --debug
```

### Hooks not firing

1. Verify `hooks/hooks.json` is valid JSON:
   ```bash
   cat .claude/plugins/git-collaboration-workflow/hooks/hooks.json | python3 -m json.tool
   ```
2. Hooks only fire on `Bash` tool calls — direct terminal commands are NOT intercepted
3. Restart Claude Code after any hook changes

### `gh` CLI not found

```bash
# Install GitHub CLI
# macOS:
brew install gh

# Linux:
sudo apt install gh

# Windows:
winget install GitHub.cli

# Authenticate
gh auth login
```

### False positive secret detection

Add the pattern to `.secretsignore`:

```bash
echo "YOUR_PATTERN_REGEX" >> .secretsignore
```

### Merge queue ejections

Common causes:
1. **File conflicts** — Two PRs modify the same file. Use `/create-pr` to detect before submission.
2. **CI failure** — Tests fail when merged with other queued PRs. Keep PRs small and focused.
3. **Stale branch** — Run `/sync-branch` before `/create-pr`.

### Hooks block a legitimate operation

For soft-blocks (integration): Confirm the prompt to proceed.

For hard-blocks (main): These are intentional. Use the skill workflows instead:
- Instead of `git push origin main` → `/create-pr` then `/prepare-release`
- Instead of `git push --force origin main` → Never do this. Use `/rollback` instead.

---

## Appendix: File Reference

```
.claude/plugins/git-collaboration-workflow/
├── plugin.json              # Plugin metadata
├── .secretsignore           # False positive whitelist
├── VALIDATION.md            # Installation verification
├── hooks/
│   └── hooks.json           # 9 hooks (7 PreToolUse + 1 PostToolUse + 1 SessionStart)
├── scripts/
│   └── check-repo-status.sh # Session start status check script
├── skills/
│   ├── start-feature.md     # /start-feature
│   ├── sync-branch.md       # /sync-branch
│   ├── create-pr.md         # /create-pr
│   ├── prepare-release.md   # /prepare-release
│   ├── hotfix.md            # /hotfix
│   ├── rollback.md          # /rollback
│   ├── cleanup-branches.md  # /cleanup-branches
│   ├── check-status.md      # /check-status
│   ├── repo-graph.md        # /repo-graph
│   └── review-pr.md         # /review-pr
├── agents/
│   └── merge-bot.md         # Automated merge agent
└── docs/
    ├── setup-guide.md       # This file
    ├── architecture.md      # Architecture decisions
    └── workflow-reference.md # Command reference card
```
