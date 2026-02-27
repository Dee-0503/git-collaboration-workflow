#!/bin/bash
# repo-graph-data.sh — Collect structured repository data for Mermaid diagram generation
# Usage: repo-graph-data.sh [topology|timeline|state|all]
# Output: JSON with branches, commits, relationships for LLM to render as Mermaid
set -euo pipefail

DIAGRAM_TYPE="${1:-all}"

# Fetch latest
git fetch --all --prune 2>/dev/null || true

# Current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Collect all branches (deduplicated)
ALL_BRANCHES=$(git branch -a --format='%(refname:short)' 2>/dev/null | sed 's|origin/||' | sort -u | grep -v '^HEAD$' || true)

# Collect branch details
BRANCH_DATA=""
while IFS= read -r branch; do
  [ -z "$branch" ] && continue

  # Determine ref to use (prefer remote)
  REF="$branch"
  if git rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
    REF="origin/$branch"
  fi

  SHORT_HASH=$(git rev-parse --short "$REF" 2>/dev/null || echo "")
  [ -z "$SHORT_HASH" ] && continue

  LAST_DATE=$(git log -1 --format="%cr" "$REF" 2>/dev/null || echo "unknown")
  LAST_AUTHOR=$(git log -1 --format="%aN" "$REF" 2>/dev/null || echo "unknown")

  # Determine branch type
  TYPE="other"
  case "$branch" in
    main) TYPE="main" ;;
    integration) TYPE="integration" ;;
    feature/*) TYPE="feature" ;;
    hotfix/*) TYPE="hotfix" ;;
    release/*) TYPE="release" ;;
    phase/*) TYPE="phase" ;;
  esac

  # Ahead/behind vs integration (or main if integration doesn't exist)
  AHEAD=0; BEHIND=0
  if git rev-parse --verify origin/integration >/dev/null 2>&1 && [ "$branch" != "integration" ]; then
    COUNTS=$(git rev-list --left-right --count "origin/integration...$REF" 2>/dev/null || echo "0	0")
    BEHIND=$(echo "$COUNTS" | cut -f1)
    AHEAD=$(echo "$COUNTS" | cut -f2)
  elif git rev-parse --verify origin/main >/dev/null 2>&1 && [ "$branch" != "main" ]; then
    COUNTS=$(git rev-list --left-right --count "origin/main...$REF" 2>/dev/null || echo "0	0")
    BEHIND=$(echo "$COUNTS" | cut -f1)
    AHEAD=$(echo "$COUNTS" | cut -f2)
  fi

  # Is current branch?
  IS_CURRENT="false"
  [ "$branch" = "$CURRENT_BRANCH" ] && IS_CURRENT="true"

  # Latest tag on this branch
  TAG=$(git describe --tags --abbrev=0 "$REF" 2>/dev/null || echo "")

  BRANCH_DATA="${BRANCH_DATA}{\"name\":\"${branch}\",\"type\":\"${TYPE}\",\"head\":\"${SHORT_HASH}\",\"last_date\":\"${LAST_DATE}\",\"last_author\":\"${LAST_AUTHOR}\",\"ahead\":${AHEAD},\"behind\":${BEHIND},\"is_current\":${IS_CURRENT},\"tag\":\"${TAG}\"},"
done <<< "$ALL_BRANCHES"

# Remove trailing comma
BRANCH_DATA="${BRANCH_DATA%,}"

# Collect recent commits for timeline
COMMIT_DATA=""
if [ "$DIAGRAM_TYPE" = "timeline" ] || [ "$DIAGRAM_TYPE" = "all" ]; then
  while IFS='|' read -r hash parents subject decorations; do
    [ -z "$hash" ] && continue
    SHORT_HASH="${hash:0:7}"
    # Escape quotes in subject
    SAFE_SUBJECT=$(echo "$subject" | sed 's/"/\\"/g' | cut -c1-40)
    PARENT_COUNT=$(echo "$parents" | wc -w | tr -d ' ')
    IS_MERGE="false"
    [ "$PARENT_COUNT" -gt 1 ] && IS_MERGE="true"

    # Extract branch from decorations
    BRANCH_REF=$(echo "$decorations" | grep -oE '(feature|hotfix|release|phase)/[^,)]+' | head -1 || true)
    [ -z "$BRANCH_REF" ] && BRANCH_REF=$(echo "$decorations" | grep -oE '(main|integration)' | head -1 || true)

    # Extract tag
    TAG_REF=$(echo "$decorations" | grep -oE 'tag: [^,)]+' | sed 's/tag: //' | head -1 || true)

    COMMIT_DATA="${COMMIT_DATA}{\"hash\":\"${SHORT_HASH}\",\"subject\":\"${SAFE_SUBJECT}\",\"is_merge\":${IS_MERGE},\"branch\":\"${BRANCH_REF}\",\"tag\":\"${TAG_REF}\"},"
  done < <(git log --all --format="%H|%P|%s|%D" --topo-order -30 2>/dev/null)
  COMMIT_DATA="${COMMIT_DATA%,}"
fi

# Count total branches by type
FEATURE_COUNT=$(echo "$ALL_BRANCHES" | grep -c '^feature/' || echo "0")
HOTFIX_COUNT=$(echo "$ALL_BRANCHES" | grep -c '^hotfix/' || echo "0")
RELEASE_COUNT=$(echo "$ALL_BRANCHES" | grep -c '^release/' || echo "0")
PHASE_COUNT=$(echo "$ALL_BRANCHES" | grep -c '^phase/' || echo "0")
TOTAL_COUNT=$(echo "$ALL_BRANCHES" | grep -c . || echo "0")

# Tags
ALL_TAGS=$(git tag --sort=-v:refname 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//')

printf '{"status":"ok","diagram_type":"%s","current_branch":"%s","total_branches":%s,"branch_counts":{"feature":%s,"hotfix":%s,"release":%s,"phase":%s},"branches":[%s],"commits":[%s],"recent_tags":"%s"}' \
  "$DIAGRAM_TYPE" "$CURRENT_BRANCH" "$TOTAL_COUNT" \
  "$FEATURE_COUNT" "$HOTFIX_COUNT" "$RELEASE_COUNT" "$PHASE_COUNT" \
  "$BRANCH_DATA" "$COMMIT_DATA" "$ALL_TAGS"
