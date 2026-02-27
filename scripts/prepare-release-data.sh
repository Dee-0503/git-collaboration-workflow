#!/bin/bash
# prepare-release-data.sh — Collect release data for /prepare-release skill
# Usage: prepare-release-data.sh
# Output: JSON with merged PRs, version info, changelog entries
set -euo pipefail

# Check gh CLI
if ! command -v gh >/dev/null 2>&1; then
  echo '{"status":"error","message":"GitHub CLI (gh) not found. Install: https://cli.github.com/"}'
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo '{"status":"error","message":"GitHub CLI not authenticated. Run: gh auth login"}'
  exit 1
fi

# Ensure on integration or can reach it
git fetch origin integration 2>/dev/null || true
git fetch origin main 2>/dev/null || true

# Get current version tag on main
CURRENT_TAG=$(git describe --tags --abbrev=0 origin/main 2>/dev/null || echo "v0.0.0")
CURRENT_VERSION="${CURRENT_TAG#v}"

# Get the base commit (tag or root)
BASE_COMMIT=$(git rev-parse "$CURRENT_TAG" 2>/dev/null || git rev-list --max-parents=0 HEAD)

# Count commits since last release
COMMIT_COUNT=$(git rev-list --count "${BASE_COMMIT}..origin/integration" 2>/dev/null || echo "0")
if [ "$COMMIT_COUNT" = "0" ]; then
  echo '{"status":"error","message":"No changes since last release. Nothing to release."}'
  exit 1
fi

# Collect commits since last release
COMMITS=$(git log --oneline "${BASE_COMMIT}..origin/integration" --format="%s" 2>/dev/null)

# Determine SemVer bump from PR labels (preferred) or commit messages (fallback)
SEMVER="patch"
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "")

if [ -n "$REPO" ]; then
  # Check PR labels for semver hints
  PR_LABELS=$(gh pr list --base integration --state merged --json labels --limit 100 2>/dev/null || echo "[]")
  if echo "$PR_LABELS" | grep -q '"semver:major"' 2>/dev/null; then
    SEMVER="major"
  elif echo "$PR_LABELS" | grep -q '"semver:minor"' 2>/dev/null; then
    SEMVER="minor"
  fi
fi

# Fallback: derive from commit messages
if [ "$SEMVER" = "patch" ]; then
  if echo "$COMMITS" | grep -qE '!:' || echo "$COMMITS" | grep -qiE 'BREAKING'; then
    SEMVER="major"
  elif echo "$COMMITS" | grep -qE '^feat(\(.+\))?!?:'; then
    SEMVER="minor"
  fi
fi

# Calculate next version
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR="${MAJOR:-0}"; MINOR="${MINOR:-0}"; PATCH="${PATCH:-0}"
case "$SEMVER" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
NEXT_VERSION="v${MAJOR}.${MINOR}.${PATCH}"

# Categorize commits
FEATURES=$(echo "$COMMITS" | grep -E '^feat(\(.+\))?:' | head -20 || true)
FIXES=$(echo "$COMMITS" | grep -E '^fix(\(.+\))?:' | head -20 || true)
BREAKING=$(echo "$COMMITS" | grep -E '!:' | head -10 || true)
OTHER=$(echo "$COMMITS" | grep -vE '^(feat|fix)(\(.+\))?!?:' | head -10 || true)

# Get contributors
CONTRIBUTORS=$(git log "${BASE_COMMIT}..origin/integration" --format="%aN" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')

# CI status on integration HEAD
CI_STATUS=$(gh api "repos/$REPO/commits/$(git rev-parse origin/integration)/status" --jq '.state' 2>/dev/null || echo "unknown")

# Build JSON output using python3 for proper escaping
python3 -c "
import json, sys

features = '''$FEATURES'''.strip().split('\n') if '''$FEATURES'''.strip() else []
fixes = '''$FIXES'''.strip().split('\n') if '''$FIXES'''.strip() else []
breaking = '''$BREAKING'''.strip().split('\n') if '''$BREAKING'''.strip() else []
other = '''$OTHER'''.strip().split('\n') if '''$OTHER'''.strip() else []
contribs = '''$CONTRIBUTORS'''.strip().split(',') if '''$CONTRIBUTORS'''.strip() else []

result = {
    'status': 'ok',
    'current_version': '$CURRENT_TAG',
    'next_version': '$NEXT_VERSION',
    'semver_bump': '$SEMVER',
    'commit_count': $COMMIT_COUNT,
    'ci_status': '$CI_STATUS',
    'features': [f for f in features if f],
    'fixes': [f for f in fixes if f],
    'breaking_changes': [b for b in breaking if b],
    'other': [o for o in other if o],
    'contributors': [c for c in contribs if c],
    'repo': '$REPO'
}
print(json.dumps(result))
" 2>/dev/null || printf '{"status":"ok","current_version":"%s","next_version":"%s","semver_bump":"%s","commit_count":%s,"ci_status":"%s"}' \
  "$CURRENT_TAG" "$NEXT_VERSION" "$SEMVER" "$COMMIT_COUNT" "$CI_STATUS"
