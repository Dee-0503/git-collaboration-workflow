#!/bin/bash
# setup-github-repo.sh — Detect and configure GitHub repository best practices
# Usage: setup-github-repo.sh <mode> [visibility]
#   mode: check | apply | create-and-apply
#   visibility: public | private (only used with create-and-apply)
# Output: JSON with status, findings/actions, and manual steps
set -euo pipefail

MODE="${1:-check}"
VISIBILITY="${2:-public}"

# ─── Prerequisites ──────────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  printf '{"status":"error","code":"no_gh","message":"GitHub CLI (gh) is not installed. Install from https://cli.github.com/"}\n'
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  printf '{"status":"error","code":"no_auth","message":"GitHub CLI is not authenticated. Run: gh auth login"}\n'
  exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  printf '{"status":"error","code":"no_git","message":"Not a git repository."}\n'
  exit 1
fi

# ─── Detect or create remote ────────────────────────────────────────
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")

if [ -z "$REMOTE_URL" ]; then
  if [ "$MODE" = "create-and-apply" ]; then
    REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
    if ! gh repo create "$REPO_NAME" --"$VISIBILITY" --source=. --push 2>/dev/null; then
      printf '{"status":"error","code":"create_failed","message":"Failed to create GitHub repository. Check gh auth and permissions."}\n'
      exit 1
    fi
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
  else
    printf '{"status":"no_remote","has_remote":false,"message":"No GitHub remote found. Use /setup-repo to create one or run: git remote add origin <url>"}\n'
    exit 0
  fi
fi

# Extract owner/repo robustly (two-stage sed, avoids non-greedy issues)
OWNER_REPO=$(echo "$REMOTE_URL" | sed -E 's#^.+github\.com[:/]##' | sed -E 's#\.git$##')

if [ -z "$OWNER_REPO" ]; then
  printf '{"status":"error","code":"parse_failed","message":"Cannot parse owner/repo from remote URL: %s"}\n' "$REMOTE_URL"
  exit 1
fi

# ─── JSON helpers ───────────────────────────────────────────────────

# Escape special characters for JSON string values
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr -d '\n\r'
}
FINDINGS=""
FINDING_COUNT=0
ACTIONS=""
ACTION_COUNT=0
ERRORS=""
ERROR_COUNT=0

add_finding() {
  local id="$1" category="$2" desc current expected
  desc=$(json_escape "$3")
  current=$(json_escape "$4")
  expected=$(json_escape "$5")
  FINDING_COUNT=$((FINDING_COUNT + 1))
  if [ "$FINDING_COUNT" -gt 1 ]; then FINDINGS="${FINDINGS},"; fi
  FINDINGS="${FINDINGS}{\"id\":\"${id}\",\"category\":\"${category}\",\"description\":\"${desc}\",\"current\":\"${current}\",\"expected\":\"${expected}\"}"
}

add_action() {
  local msg
  msg=$(json_escape "$1")
  ACTION_COUNT=$((ACTION_COUNT + 1))
  if [ "$ACTION_COUNT" -gt 1 ]; then ACTIONS="${ACTIONS},"; fi
  ACTIONS="${ACTIONS}\"${msg}\""
}

add_error() {
  local msg
  msg=$(json_escape "$1")
  ERROR_COUNT=$((ERROR_COUNT + 1))
  if [ "$ERROR_COUNT" -gt 1 ]; then ERRORS="${ERRORS},"; fi
  ERRORS="${ERRORS}\"${msg}\""
}

# ─── Check functions ────────────────────────────────────────────────

check_repo_settings() {
  # Single API call, extract all 4 booleans as CSV
  local settings
  settings=$(gh api "repos/$OWNER_REPO" --jq '[.allow_squash_merge, .allow_merge_commit, .allow_rebase_merge, .delete_branch_on_merge] | @csv' 2>/dev/null || echo "")

  if [ -z "$settings" ]; then
    add_finding "repo_api_error" "repo" "Cannot read repository settings (API error or insufficient permissions)" "unknown" "readable"
    return
  fi

  # Parse CSV: "true,true,true,false"
  local squash merge rebase delete_br
  IFS=',' read -r squash merge rebase delete_br <<< "$settings"

  if [ "$squash" != "true" ]; then
    add_finding "repo_squash_disabled" "repo" "Squash merge is not enabled" "$squash" "true"
  fi
  if [ "$merge" != "false" ]; then
    add_finding "repo_merge_commit_allowed" "repo" "Merge commits are allowed (should be squash-only)" "$merge" "false"
  fi
  if [ "$rebase" != "false" ]; then
    add_finding "repo_rebase_allowed" "repo" "Rebase merge is allowed (should be squash-only)" "$rebase" "false"
  fi
  if [ "$delete_br" != "true" ]; then
    add_finding "repo_no_auto_delete" "repo" "Auto-delete head branches after merge is disabled" "$delete_br" "true"
  fi
}

check_branch_protection() {
  local branch="$1" expect_reviews="$2"

  # Check if branch exists on remote
  if ! gh api "repos/$OWNER_REPO/branches/$branch" --jq '.name' >/dev/null 2>&1; then
    add_finding "${branch}_not_found" "branch" "Branch '$branch' does not exist on remote" "missing" "exists"
    return
  fi

  # Check branch protection — single API call extracting all fields as CSV
  local prot_csv prot_exit=0
  prot_csv=$(gh api "repos/$OWNER_REPO/branches/$branch/protection" \
    --jq '[(.enforce_admins.enabled | tostring), (.allow_force_pushes.enabled | tostring), (.required_linear_history.enabled | tostring), ((.required_pull_request_reviews.required_approving_review_count // -1) | tostring)] | join(",")' \
    2>&1) || prot_exit=$?

  if [ "$prot_exit" -ne 0 ]; then
    # Distinguish 404 (no protection) from other errors
    if echo "$prot_csv" | grep -q "Not Found"; then
      add_finding "${branch}_no_protection" "protection" "No branch protection rules on '$branch'" "none" "protected"
    fi
    # Other errors (rate limit, network): skip silently
    return
  fi

  # Parse CSV: "true,false,true,1"
  local enforce_admins allow_force linear_history review_count
  IFS=',' read -r enforce_admins allow_force linear_history review_count <<< "$prot_csv"

  if [ "$enforce_admins" != "true" ]; then
    add_finding "${branch}_no_admin_enforce" "protection" "Admin enforcement not enabled on '$branch'" "$enforce_admins" "true"
  fi
  if [ "$allow_force" != "false" ]; then
    add_finding "${branch}_force_push_allowed" "protection" "Force push is allowed on '$branch'" "$allow_force" "false"
  fi

  if [ "$branch" = "main" ] && [ "$linear_history" != "true" ]; then
    add_finding "main_no_linear_history" "protection" "Linear history not required on main" "$linear_history" "true"
  fi

  # Check PR review requirement
  if [ "$review_count" = "-1" ] || [ -z "$review_count" ]; then
    add_finding "${branch}_no_pr_required" "protection" "Pull request reviews not required on '$branch'" "none" "${expect_reviews} approval(s)"
  elif [ "$branch" = "main" ] && [ "$review_count" -lt "$expect_reviews" ] 2>/dev/null; then
    add_finding "${branch}_low_reviews" "protection" "Review count too low on '$branch'" "$review_count" "$expect_reviews"
  fi
}

check_workflows() {
  # Check workflow files via GitHub API (not local filesystem)
  if ! gh api "repos/$OWNER_REPO/contents/.github/workflows/claude.yml" --jq '.name' >/dev/null 2>&1; then
    add_finding "workflow_claude_missing" "workflow" "Claude Code interactive workflow (.github/workflows/claude.yml) is missing" "missing" "exists"
  fi

  if ! gh api "repos/$OWNER_REPO/contents/.github/workflows/claude-code-review.yml" --jq '.name' >/dev/null 2>&1; then
    add_finding "workflow_review_missing" "workflow" "Claude Code auto-review workflow (.github/workflows/claude-code-review.yml) is missing" "missing" "exists"
  fi
}

check_api_secret() {
  local secrets
  local secret_exit=0
  secrets=$(gh secret list --repo "$OWNER_REPO" --json name --jq '.[].name' 2>&1) || secret_exit=$?

  if [ "$secret_exit" -ne 0 ]; then
    # Cannot read secrets (permissions or plan): skip silently
    return
  fi

  if ! echo "$secrets" | grep -qx "ANTHROPIC_AUTH_TOKEN"; then
    add_finding "secret_auth_token_missing" "workflow" "ANTHROPIC_AUTH_TOKEN secret is not configured (required for Claude Code GitHub Actions)" "missing" "configured"
  fi
  # ANTHROPIC_BASE_URL is only needed for relay mode; only flag if AUTH_TOKEN is present
  if echo "$secrets" | grep -qx "ANTHROPIC_AUTH_TOKEN" && ! echo "$secrets" | grep -qx "ANTHROPIC_BASE_URL"; then
    add_finding "secret_base_url_missing" "workflow" "ANTHROPIC_BASE_URL secret is not configured (required if using a custom relay endpoint)" "missing" "configured"
  fi
}

check_labels() {
  local existing_labels
  existing_labels=$(gh label list --repo "$OWNER_REPO" --json name --jq '.[].name' 2>/dev/null || echo "")

  for label in "semver:patch" "semver:minor" "semver:major"; do
    if ! echo "$existing_labels" | grep -qx "$label"; then
      add_finding "label_missing_${label}" "labels" "SemVer label '$label' is missing" "missing" "exists"
    fi
  done
}

# ─── Check mode ─────────────────────────────────────────────────────
if [ "$MODE" = "check" ]; then
  check_repo_settings
  check_branch_protection "main" "1"
  check_branch_protection "integration" "0"
  check_labels
  check_workflows
  check_api_secret

  if [ "$FINDING_COUNT" -eq 0 ]; then
    # All checks passed — write verification marker
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -n "$REPO_ROOT" ]; then
      mkdir -p "${REPO_ROOT}/.claude"
      printf '{"verified_at":"%s","remote_url":"%s","repo":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$REMOTE_URL" "$OWNER_REPO" > "${REPO_ROOT}/.claude/.github-setup-verified"
    fi
    printf '{"status":"ok","has_remote":true,"repo":"%s","repo_url":"https://github.com/%s","finding_count":0,"findings":[],"message":"All GitHub settings match best practices."}\n' "$OWNER_REPO" "$OWNER_REPO"
  else
    printf '{"status":"needs_setup","has_remote":true,"repo":"%s","repo_url":"https://github.com/%s","finding_count":%d,"findings":[%s]}\n' "$OWNER_REPO" "$OWNER_REPO" "$FINDING_COUNT" "$FINDINGS"
  fi
  exit 0
fi

# ─── Apply mode: fix all settings ───────────────────────────────────

# Apply repo settings
apply_repo_settings() {
  if gh api "repos/$OWNER_REPO" -X PATCH --input - >/dev/null 2>&1 <<'REPOJSON'
{
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "delete_branch_on_merge": true
}
REPOJSON
  then
    add_action "Configured repo: squash-only merge, auto-delete branches on merge"
  else
    add_error "Failed to update repo merge settings (check permissions)"
  fi
}

# Apply branch protection
apply_branch_protection() {
  local branch="$1" reviews="$2"

  # Skip if branch doesn't exist
  if ! gh api "repos/$OWNER_REPO/branches/$branch" --jq '.name' >/dev/null 2>&1; then
    add_error "Cannot protect '$branch': branch does not exist on remote"
    return
  fi

  local body
  if [ "$branch" = "main" ]; then
    body='{
      "required_pull_request_reviews": {
        "dismiss_stale_reviews": true,
        "required_approving_review_count": '"$reviews"'
      },
      "enforce_admins": true,
      "required_status_checks": null,
      "restrictions": null,
      "required_linear_history": true,
      "allow_force_pushes": false,
      "allow_deletions": false
    }'
  else
    body='{
      "required_pull_request_reviews": {
        "dismiss_stale_reviews": false,
        "required_approving_review_count": '"$reviews"'
      },
      "enforce_admins": true,
      "required_status_checks": null,
      "restrictions": null,
      "allow_force_pushes": false,
      "allow_deletions": false
    }'
  fi

  if echo "$body" | gh api "repos/$OWNER_REPO/branches/$branch/protection" -X PUT --input - >/dev/null 2>&1; then
    add_action "Applied branch protection to '$branch': require ${reviews} PR review(s), enforce admins, block force push"
  else
    # Retry with 1 review (free plan may not support 0)
    if [ "$reviews" = "0" ]; then
      local fallback_body='{
        "required_pull_request_reviews": {
          "dismiss_stale_reviews": false,
          "required_approving_review_count": 1
        },
        "enforce_admins": true,
        "required_status_checks": null,
        "restrictions": null,
        "allow_force_pushes": false,
        "allow_deletions": false
      }'
      if echo "$fallback_body" | gh api "repos/$OWNER_REPO/branches/$branch/protection" -X PUT --input - >/dev/null 2>&1; then
        add_action "Applied branch protection to '$branch': require 1 PR review (free plan minimum), enforce admins, block force push"
      else
        add_error "Failed to set branch protection on '$branch' (check GitHub plan and permissions)"
      fi
    else
      add_error "Failed to set branch protection on '$branch' (check GitHub plan and permissions)"
    fi
  fi
}

# Apply SemVer labels
apply_labels() {
  local existing_labels
  existing_labels=$(gh label list --repo "$OWNER_REPO" --json name --jq '.[].name' 2>/dev/null || echo "")

  local created=0
  if ! echo "$existing_labels" | grep -qx "semver:patch"; then
    gh label create "semver:patch" --repo "$OWNER_REPO" --color "0e8a16" --description "Patch version bump (bug fixes)" 2>/dev/null && created=$((created + 1))
  fi
  if ! echo "$existing_labels" | grep -qx "semver:minor"; then
    gh label create "semver:minor" --repo "$OWNER_REPO" --color "1d76db" --description "Minor version bump (new features)" 2>/dev/null && created=$((created + 1))
  fi
  if ! echo "$existing_labels" | grep -qx "semver:major"; then
    gh label create "semver:major" --repo "$OWNER_REPO" --color "d93f0b" --description "Major version bump (breaking changes)" 2>/dev/null && created=$((created + 1))
  fi

  if [ "$created" -gt 0 ]; then
    add_action "Created ${created} SemVer label(s): semver:patch, semver:minor, semver:major"
  fi
}

# Apply Claude Code workflow files
apply_workflows() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -z "$repo_root" ]; then return; fi

  mkdir -p "$repo_root/.github/workflows"
  local created=0
  local existing=0

  if [ ! -f "$repo_root/.github/workflows/claude.yml" ]; then
    cat > "$repo_root/.github/workflows/claude.yml" <<'CLAUDE_WF_EOF'
name: Claude Code

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]
  pull_request_review:
    types: [submitted]

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review' && contains(github.event.review.body, '@claude')) ||
      (github.event_name == 'issues' && (contains(github.event.issue.body, '@claude') || contains(github.event.issue.title, '@claude')))
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      issues: write
      id-token: write
      actions: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 1

      - name: Run Claude Code
        id: claude
        uses: anthropics/claude-code-action@v1
        env:
          ANTHROPIC_BASE_URL: ${{ secrets.ANTHROPIC_BASE_URL }}
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_AUTH_TOKEN }}
          additional_permissions: |
            actions: read
CLAUDE_WF_EOF
    # Back in if-block scope after heredoc
    created=$((created + 1))
  else
    existing=$((existing + 1))
  fi

  if [ ! -f "$repo_root/.github/workflows/claude-code-review.yml" ]; then
    cat > "$repo_root/.github/workflows/claude-code-review.yml" <<'REVIEW_WF_EOF'
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize, ready_for_review, reopened]
    branches: [main]

jobs:
  claude-review:
    if: github.event.pull_request.draft == false
    runs-on: ubuntu-latest
    timeout-minutes: 60
    permissions:
      contents: read
      pull-requests: write
      issues: write
      id-token: write
      actions: read

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 1

      - name: Collect previous review findings
        id: prev-review
        if: github.event.action == 'synchronize'
        run: |
          PR=${{ github.event.pull_request.number }}
          REPO=${{ github.repository }}

          INLINE_JSON=$(gh api "repos/$REPO/pulls/$PR/comments" \
            --jq '[.[] | select(.user.login == "claude[bot]") | {path, line, body: (.body | split("\n")[0] | .[0:200])}]' \
            2>/dev/null || echo "[]")
          INLINE_COUNT=$(echo "$INLINE_JSON" | jq 'length')

          if [ "$INLINE_COUNT" -gt 0 ]; then
            FINDINGS=""
            for i in $(seq 0 $((INLINE_COUNT - 1))); do
              FILE=$(echo "$INLINE_JSON" | jq -r ".[$i].path")
              LINE=$(echo "$INLINE_JSON" | jq -r ".[$i].line // \"N/A\"")
              BODY=$(echo "$INLINE_JSON" | jq -r ".[$i].body" | head -1 | cut -c1-150)
              N=$((i + 1))
              FINDINGS+="$N. $FILE:L$LINE — $BODY"$'\n'
            done

            {
              echo "context<<CONTEXT_EOF"
              echo ""
              echo "PREVIOUS REVIEW FINDINGS ($INLINE_COUNT issue(s) from prior round):"
              echo "$FINDINGS"
              echo "For each previous finding above, verify whether it was addressed in the new commits."
              echo "Report status: [RESOLVED] if fixed, [STILL OPEN] if not, [PARTIALLY FIXED] if partially addressed."
              echo "CONTEXT_EOF"
            } >> "$GITHUB_OUTPUT"
          fi

          gh api "repos/$REPO/issues/$PR/comments" \
            --jq '.[] | select(.body | test("### Code Review")) | select(.user.login | test("github-actions|claude")) | .id' 2>/dev/null \
          | while read comment_id; do
              gh api "repos/$REPO/issues/comments/$comment_id" -X DELETE 2>/dev/null || true
            done
        env:
          GH_TOKEN: ${{ github.token }}

      - name: Verify API connectivity
        env:
          ANTHROPIC_BASE_URL: ${{ secrets.ANTHROPIC_BASE_URL }}
          ANTHROPIC_AUTH_TOKEN: ${{ secrets.ANTHROPIC_AUTH_TOKEN }}
        run: |
          set +e
          curl -s --connect-timeout 10 --max-time 15 \
            -X POST "${ANTHROPIC_BASE_URL}/v1/messages" \
            -H "x-api-key: ${ANTHROPIC_AUTH_TOKEN}" \
            -H "anthropic-version: 2023-06-01" \
            -H "content-type: application/json" \
            -d '{"model":"claude-sonnet-4-6","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}' \
            -o /dev/null -w "HTTP %{http_code}" && echo " OK" || echo "::warning::API connectivity check failed, proceeding anyway"

      - name: Run Claude Code Review
        id: claude-review
        uses: anthropics/claude-code-action@v1
        env:
          ANTHROPIC_BASE_URL: ${{ secrets.ANTHROPIC_BASE_URL }}
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_AUTH_TOKEN }}
          prompt: |
            You are a senior code reviewer. Perform a thorough review of PR #${{ github.event.pull_request.number }} in ${{ github.repository }}.

            ${{ steps.prev-review.outputs.context }}

            ## Review Pipeline

            ### Step 1: Gather Context
            Run: `gh pr diff ${{ github.event.pull_request.number }}` and `gh pr view ${{ github.event.pull_request.number }} --json title,body,files`
            Find all CLAUDE.md files relevant to modified directories.

            ### Step 2: Parallel Review (5 agents)
            Use Agent tool to launch 5 parallel agents reviewing the full diff:
            1. CLAUDE.md Compliance
            2. Bug Detection (shallow, diff-only)
            3. Historical Context (git blame/log)
            4. Security & Performance
            5. Code Quality & Patterns

            ### Step 3: Confidence Scoring (0-100, threshold 80)
            Discard false positives: pre-existing issues, linter-catchable, nitpicks, intentional changes.

            ### Step 4: Post via `gh pr comment` with format: "### Code Review\n\nFound N issue(s):\n1. description (category)\n   permalink"
            If previous findings provided, add "### Previous Findings Status" section.
          claude_args: '--allowedTools "Agent,Read,Glob,Grep,Bash(gh:*),Bash(git blame:*),Bash(git log:*),Bash(git diff:*),Bash(git show:*),Bash(cat:*),Bash(head:*),Bash(wc:*),Bash(find:*),Bash(ls:*)"'
          show_full_output: true
          additional_permissions: |
            actions: read
REVIEW_WF_EOF
    # Back in if-block scope after heredoc
    created=$((created + 1))
  else
    existing=$((existing + 1))
  fi

  if [ "$created" -gt 0 ]; then
    add_action "Created ${created} Claude Code workflow file(s) in .github/workflows/ (commit and push to activate)"
  fi
  if [ "$existing" -gt 0 ]; then
    add_action "${existing} Claude Code workflow file(s) already exist in .github/workflows/"
  fi
}

# Run apply
apply_repo_settings
apply_branch_protection "main" "1"
apply_branch_protection "integration" "0"
apply_labels
apply_workflows

# Manual steps that cannot be automated via API
MANUAL_STEPS='"Install Claude GitHub App: https://github.com/apps/claude (or run /install-github-app in Claude Code)","Add ANTHROPIC_AUTH_TOKEN to repository secrets (Settings > Secrets > Actions) — required for Claude Code GitHub Actions","Add ANTHROPIC_BASE_URL to repository secrets if using a custom relay endpoint","Commit and push .github/workflows/ files to activate Claude Code review automation","Enable merge queue in GitHub Settings > Branches > integration rule (requires GitHub repo settings UI)","Add required status checks (ci/tests, ci/lint, ci/build) in branch protection after CI is configured","Create CODEOWNERS file for code review routing"'

# Output
if [ "$ERROR_COUNT" -eq 0 ]; then
  printf '{"status":"ok","repo":"%s","repo_url":"https://github.com/%s","action_count":%d,"actions":[%s],"manual_steps":[%s]}\n' \
    "$OWNER_REPO" "$OWNER_REPO" "$ACTION_COUNT" "$ACTIONS" "$MANUAL_STEPS"
else
  printf '{"status":"partial","repo":"%s","repo_url":"https://github.com/%s","action_count":%d,"actions":[%s],"error_count":%d,"errors":[%s],"manual_steps":[%s]}\n' \
    "$OWNER_REPO" "$OWNER_REPO" "$ACTION_COUNT" "$ACTIONS" "$ERROR_COUNT" "$ERRORS" "$MANUAL_STEPS"
fi

exit 0
