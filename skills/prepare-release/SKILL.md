---
name: prepare-release
description: This skill should be used when the user asks to "prepare a release", "create a release", "ship to production", "cut a release", "deploy to main", or when integration is ready for production. Creates a release PR from integration to main with auto-generated changelog and SemVer version.
user_invocable: true
---

# /prepare-release — Prepare Release

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Prepare a release by collecting merged changes, calculating the next version,
generating release notes, and creating a release PR from `integration` to `main`.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`
2. Check `gh` CLI: run `which gh`. If missing, block with install instructions.

## Steps

### Step 1 — Collect Release Data

Execute the backing script to gather all release information:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/prepare-release-data.sh"
```

Parse the JSON output:

| Field | Description |
|-------|-------------|
| `status` | `ok` or `error` |
| `current_version` | Current tag on main (e.g., `v1.2.0`) |
| `next_version` | Calculated next version (e.g., `v1.3.0`) |
| `semver_bump` | Bump level: `patch`, `minor`, or `major` |
| `commit_count` | Number of commits since last release |
| `ci_status` | CI status on integration HEAD |
| `features` | Array of feat commit messages |
| `fixes` | Array of fix commit messages |
| `breaking_changes` | Array of breaking change messages |
| `other` | Array of other commit messages |
| `contributors` | Array of contributor names |
| `repo` | Repository name with owner |

### Step 2 — Present Release Summary

Display to the user:
- Current version → Next version (with bump reason)
- CI status on integration
- Features, fixes, breaking changes
- Contributors

### Step 3 — Confirm with User

Ask: "Ready to create release PR for `<next_version>`? (y/n)"

If CI status is not "success", warn: "CI is not green on integration. Proceed anyway?"

### Step 4 — Generate Release Notes

From the script data, compose release notes:

```markdown
## What's Changed

### 🚀 Features
- <feature commits>

### 🐛 Bug Fixes
- <fix commits>

### ⚠️ Breaking Changes
- <breaking changes>

### 🔧 Other
- <other commits>

### 👥 Contributors
- <contributor list>
```

### Step 5 — Create Release PR

```bash
gh pr create --base main --head integration \
  --title "chore(release): prepare <next_version>" \
  --body "<release notes>"
```

### Step 6 — Apply SemVer Label

```bash
gh pr edit <pr-number> --add-label "semver:<level>"
```

### Step 7 — Display Result

Show:
- PR URL
- Version: current → next
- SemVer label applied
- Approval checklist:
  - [ ] CI passes on release PR
  - [ ] CODEOWNER approval obtained
  - [ ] Version number is correct
  - [ ] Release notes are accurate

## Error Handling

- If no tags exist yet, use v0.0.0 as base version
- If no new commits since last release, abort
- If `gh` commands fail, suggest checking authentication
