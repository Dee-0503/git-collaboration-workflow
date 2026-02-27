# Quickstart Validation Checklist

Use this checklist to verify that the Git Collaboration Workflow Plugin
is correctly installed and operational.

## Prerequisites

- [ ] Claude Code is running (latest or previous major version)
- [ ] Plugin directory copied to `.claude/plugins/git-collaboration-workflow/`
- [ ] Git repository has `main` and `integration` branches
- [ ] `gh` CLI installed and authenticated (for PR skills)

## Hook Verification

### Safety Hooks (Hard-block)

- [ ] `git push origin HEAD:main` — **BLOCKED** with message about using PRs
- [ ] `git push --force origin main` — **BLOCKED** with message about append-only history
- [ ] `git rebase origin/main` (while on `integration`) — **BLOCKED** with message about shared branches
- [ ] `git commit -m "fixed stuff"` — **BLOCKED** with Conventional Commits format guidance

### Safety Hooks (Soft-block)

- [ ] `git push origin HEAD:integration` — **PROMPTED** for confirmation (user can override)
- [ ] `git push --force origin integration` — **PROMPTED** with warning

### Allowed Operations

- [ ] `git push origin feature/test-branch` — **ALLOWED** (feature branch push)
- [ ] `git commit -m "feat(auth): add login endpoint"` — **ALLOWED** (valid conventional commit)
- [ ] `git rebase origin/integration` (while on `feature/x`) — **ALLOWED** (feature sync)
- [ ] `git checkout -b feature/alice-login` — **ALLOWED** (valid branch name)

### Validation Hooks

- [ ] `git checkout -b bad-name` — **BLOCKED** with naming convention examples
- [ ] Staging a file with `AKIA...` pattern — **BLOCKED** with credential warning
- [ ] Staging a file with conflict markers `<<<<<<<` — **BLOCKED** with resolution instructions

### Session Start Hook

- [ ] Start a new Claude Code session — **STATUS REPORT** shown with branch name
- [ ] Start session while on `main` — **RECOMMEND** creating feature branch (with reason + approval prompt)
- [ ] Start session with uncommitted changes — **RECOMMEND** commit/stash (with reason + approval prompt)

## Skill Verification

- [ ] `/check-status` — Shows full health report, recommends actions with reasons, requires approval
- [ ] `/start-feature` — Creates branch from integration with validated name
- [ ] `/sync-branch` — Rebases feature branch onto latest integration
- [ ] `/create-pr` — Creates PR with template, SemVer label, conflict checks
- [ ] `/prepare-release` — Creates release PR with changelog
- [ ] `/hotfix` — Guides emergency fix from main
- [ ] `/rollback` — Reverts latest release on main
- [ ] `/cleanup-branches` — Lists and deletes merged branches
- [ ] `/check-status` — Shows full health report, recommends actions with reasons, requires approval
- [ ] `/repo-graph` — Generates Mermaid diagrams of branch topology and commit history
- [ ] `/review-pr` — Structured code review with findings, severity, and optional auto-fix

## Agent Verification

- [ ] merge-bot agent definition present at `agents/merge-bot.md`

## Plugin Structure

- [ ] `plugin.json` exists with name, description, version
- [ ] `hooks/hooks.json` exists with 7 PreToolUse + 1 PostToolUse + 1 SessionStart hooks
- [ ] `scripts/check-repo-status.sh` exists and is executable
- [ ] `skills/` contains 10 skill files
- [ ] `agents/` contains 1 agent file
- [ ] `.secretsignore` exists with example patterns
