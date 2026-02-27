# Workflow Quick Reference

## Skills (Slash Commands)

### /start-feature
Create a new feature branch from latest integration.

```
Prompts for: contributor ID, feature slug
Creates:     feature/<id>-<slug> from integration HEAD
Sets up:     remote tracking with -u
```

**Pre-checks**: uncommitted changes warning, integration exists

---

### /sync-branch
Rebase current feature branch onto latest integration.

```
Fetches:     origin/integration
Rebases:     current branch onto origin/integration
Pushes:      --force-with-lease (safe force push)
```

**Pre-checks**: not on main/integration, auto-stash if dirty
**Conflict handling**: lists files, assists resolution, abort option

---

### /create-pr
Create a PR with full template and SemVer label.

```
Syncs:       branch with integration (if behind)
Checks:      file count (warns > 20)
Detects:     conflicts with open PRs and merge queue
Creates:     PR via gh with template sections filled
Labels:      semver:patch/minor/major based on commit types
```

**Pre-checks**: gh CLI, branch type, commits ahead
**Template sections**: Summary, Testing Plan, Risk & Rollback, Impacted Areas, Preview

---

### /prepare-release
Create a release PR from integration to main.

```
Collects:    PRs merged since last tag
Calculates:  next version from PR labels
Generates:   release notes from PR titles
Creates:     PR to main with chore(release) title
```

**Pre-checks**: gh CLI, on integration, CI green

---

### /hotfix
Emergency fix workflow from main.

```
Creates:     hotfix/<name> from main
Guides:      fix with fix: commit prefix
Creates:     PR to main with semver:patch
After merge: cherry-picks to integration
Cleans up:   deletes hotfix branch
```

**Pre-checks**: gh CLI, user confirmation

---

### /rollback
Revert latest release on main.

```
Identifies:  latest release tag
Reverts:     HEAD commit on main (git revert)
Creates:     PR for the revert
After merge: verifies new patch tag
Optional:    reverts on integration too
```

**Pre-checks**: gh CLI, user confirmation, tags exist

---

### /cleanup-branches
Delete merged feature branches.

```
Lists:       branches merged into integration
Filters:     excludes main, integration, HEAD
Confirms:    user selects branches to delete
Deletes:     remote (git push --delete) + local (git branch -d)
```

**Pre-checks**: remote configured

---

### /check-status
On-demand repository health check with actionable recommendations.

```
Checks:      current branch, uncommitted changes, sync status
Detects:     protected branch, detached HEAD, stale branch, missing tracking
Presents:    each issue with reason + recommended action
Requires:    explicit user approval before executing any action
```

**Supports**: batch approval ("approve all" or "approve 1, 3")

---

### /repo-graph
Visualize repository branch topology and commit history as Mermaid diagrams.

```
Diagrams:    Branch Topology (flowchart), Commit Timeline (gitGraph), Branch State (stateDiagram)
Collects:    branches, commits, merge points, ahead/behind counts
Outputs:     .mmd files (repo-graph-topology.mmd, repo-graph-timeline.mmd, repo-graph-state.mmd)
Renders:     via /pretty-mermaid (SVG) or ASCII fallback
```

**Options**: single diagram, all three, or ASCII-only mode

---

### /review-pr
Structured code review for current branch or a specific PR.

```
Reviews:     correctness, security, performance, style, architecture
Checks:      test coverage gaps for new/modified code
Outputs:     findings with severity (CRITICAL/WARNING/INFO) + location + fix
Verdict:     APPROVE / REQUEST CHANGES / COMMENT
Optional:    auto-fix findings, post review to GitHub PR
```

**Lenses**: Correctness, Security (OWASP), Performance, Style, Architecture

---

## Hooks (Automatic)

| When you... | Hook | Response |
|-------------|------|----------|
| `git push origin main` | prevent-direct-push | BLOCKED |
| `git push origin integration` | prevent-direct-push | CONFIRM? |
| `git push --force origin main` | prevent-force-push | BLOCKED |
| `git rebase` (on main/integration) | prevent-rebase-shared | BLOCKED |
| `git commit -m "bad msg"` | enforce-commit-format | BLOCKED |
| `git checkout -b bad-name` | enforce-branch-naming | BLOCKED |
| `git add` (with secrets) | detect-secrets | BLOCKED |
| `git commit` (with conflict markers) | detect-conflict-markers | BLOCKED |
| `git diff --stat` (> 20 files) | pr-scope-check | WARNING |
| Session starts | repo-status-check | RECOMMEND (with approval) |

## Commit Message Format

```
<type>[optional scope]: <description>

Types: feat fix docs chore refactor test ci build perf style
```

**Examples**:
- `feat: add user dashboard`
- `fix(auth): resolve token refresh loop`
- `docs(api): update endpoint documentation`
- `chore!: drop Node 14 support` (breaking change)

## Branch Naming

```
<type>/<kebab-case-name>

Types: feature phase hotfix release
```

**Examples**:
- `feature/alice-login-page`
- `hotfix/fix-payment-timeout`
- `release/v1.2.0`
- `phase/phase2-api-layer`
