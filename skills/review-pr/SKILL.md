---
name: review-pr
description: This skill should be used when the user asks to "review my code", "code review", "review this PR", "check my changes", "review PR #N", or wants feedback on code quality before merging. Performs structured 5-lens code review (correctness, security, performance, style, architecture) with actionable findings.
user_invocable: true
---

# /review-pr — Code Review

**Version Compatibility**: Before executing, verify that all referenced tools
and APIs are available. If any tool or API referenced in this workflow is
unavailable, skip that specific step with a notice to the user rather than
failing entirely.

## Purpose

Perform a structured code review of the current branch's changes or a specific
PR. Reviews cover correctness, security, performance, style, and architectural
alignment. Uses a backing script to collect diff data, then applies review lenses.

## Pre-flight

1. Verify this is a git repository: `git rev-parse --git-dir`

## Steps

### Step 1 — Collect Diff Data

Execute the backing script to gather change information:

```bash
# Review current branch vs integration
bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-pr-diff.sh"

# Review a specific PR
bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-pr-diff.sh" <pr-number>
```

Parse the JSON output:

| Field | Description |
|-------|-------------|
| `status` | `ok` or `error` |
| `mode` | `branch` or `pr` |
| `title` | Branch name or PR title |
| `head_branch` | Head branch name |
| `base_branch` | Base branch name |
| `file_count` | Total changed files |
| `files` | Array of all changed file paths |
| `categories` | Object with `source`, `tests`, `config`, `docs`, `infra` |
| `pr_number` | PR number (if reviewing a PR) |

Each category contains:
- `count`: Number of files in this category
- `files`: Array of file paths

### Step 2 — Read and Analyze Changes

For each changed file, read the full diff:

```bash
# For current branch
git diff origin/integration...HEAD -- <file>

# For a specific PR
gh pr diff <number>
```

Apply these review lenses sequentially:

#### Lens 1: Correctness
- Logic errors, off-by-one, null/undefined handling
- Missing edge cases
- Incorrect API usage
- Type mismatches
- Incomplete error handling

#### Lens 2: Security (OWASP-aligned)
- Injection vulnerabilities (SQL, command, XSS)
- Hardcoded credentials or secrets
- Missing input validation at system boundaries
- Insecure deserialization
- Missing authentication/authorization checks
- Path traversal risks

#### Lens 3: Performance
- O(n²) or worse in hot paths
- Missing pagination for list queries
- Unnecessary re-renders or re-computations
- Missing indexes for database queries
- Large memory allocations in loops

#### Lens 4: Style & Conventions
- Conventional Commits compliance
- Naming conventions
- Dead code or commented-out blocks
- Overly complex functions (> 50 lines or > 5 parameters)

#### Lens 5: Architecture
- Changes crossing module boundaries unexpectedly
- New dependencies without justification
- Violations of existing codebase patterns
- Missing tests for new functionality

### Step 3 — Present Findings

```
Code Review: <title>
═══════════════════════════════════
Files reviewed:  <N> (source: N, tests: N, config: N, docs: N, infra: N)
Findings:        <N> (X critical, Y warning, Z info)

──────────────────────────────────
[CRITICAL] <file>:<line>
Category:    Security
Finding:     SQL injection via unsanitized user input
Suggestion:  Use parameterized queries
Code:        <relevant snippet>
──────────────────────────────────
```

### Step 4 — Test Coverage Assessment

Check if new code has corresponding tests:
1. For each new source file, check for corresponding test file
2. For modified functions, check for test coverage
3. Report gaps

### Step 5 — Summary and Verdict

| Verdict | Criteria |
|---------|----------|
| APPROVE | No critical findings, all warnings addressable |
| REQUEST CHANGES | Critical findings that must be fixed |
| COMMENT | Only informational findings |

### Step 6 — Apply Feedback (Optional)

Ask the user:
> 1. Fix all critical issues
> 2. Fix critical + warnings
> 3. Let me choose specific findings
> 4. No, I'll fix them manually

If approved, apply fixes and re-run relevant lenses.

## Integration with Workflow

- After APPROVE: suggest `/create-pr`
- For existing PR: offer to post findings via `gh pr review`

## Behavior Rules

- **Read before judging**: Always read full file context, not just diff
- **No false positives**: Only flag confident issues
- **Respect existing patterns**: Don't flag consistent codebase patterns
- **Severity matters**: Don't mark style issues as critical
- **Be specific**: Include file:line references
- **Skip if clean**: If no issues, say so clearly
- If script not found, fall back to running git commands directly
