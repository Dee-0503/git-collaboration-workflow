#!/bin/bash
# review-pr-diff.sh — Collect diff data for /review-pr skill
# Usage: review-pr-diff.sh [pr-number]
# Output: JSON with changed files, categories, line counts, diff content
set -euo pipefail

PR_NUMBER="${1:-}"

# Determine review mode
if [ -n "$PR_NUMBER" ]; then
  # Review a specific PR
  if ! command -v gh >/dev/null 2>&1; then
    echo '{"status":"error","message":"GitHub CLI (gh) required to review PRs by number."}'
    exit 1
  fi

  # Get PR info
  PR_INFO=$(gh pr view "$PR_NUMBER" --json title,headRefName,baseRefName,files,state 2>/dev/null)
  if [ -z "$PR_INFO" ]; then
    printf '{"status":"error","message":"PR #%s not found or not accessible."}' "$PR_NUMBER"
    exit 1
  fi

  TITLE=$(echo "$PR_INFO" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['title'])" 2>/dev/null || echo "unknown")
  HEAD_BRANCH=$(echo "$PR_INFO" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['headRefName'])" 2>/dev/null || echo "unknown")
  BASE_BRANCH=$(echo "$PR_INFO" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['baseRefName'])" 2>/dev/null || echo "unknown")

  # Get changed files list
  CHANGED_FILES=$(gh pr diff "$PR_NUMBER" --name-only 2>/dev/null || echo "")
  DIFF_STAT=$(gh pr diff "$PR_NUMBER" --stat 2>/dev/null || echo "")
  MODE="pr"
else
  # Review current branch vs integration
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "integration" ] || [ "$BRANCH" = "HEAD" ]; then
    printf '{"status":"error","message":"Cannot review %s. Switch to a feature branch or specify a PR number."}' "$BRANCH"
    exit 1
  fi

  if ! git rev-parse --verify origin/integration >/dev/null 2>&1; then
    echo '{"status":"error","message":"origin/integration not found. Cannot determine diff base."}'
    exit 1
  fi

  TITLE="$BRANCH"
  HEAD_BRANCH="$BRANCH"
  BASE_BRANCH="integration"

  CHANGED_FILES=$(git diff --name-only origin/integration...HEAD 2>/dev/null || echo "")
  DIFF_STAT=$(git diff --stat origin/integration...HEAD 2>/dev/null || echo "")
  MODE="branch"
fi

# Count files
if [ -z "$CHANGED_FILES" ]; then
  echo '{"status":"error","message":"No changes found to review."}'
  exit 1
fi

FILE_COUNT=$(echo "$CHANGED_FILES" | grep -c . || echo "0")

# Categorize files
python3 -c "
import json, re, sys

files = '''$CHANGED_FILES'''.strip().split('\n')
files = [f for f in files if f]

categories = {
    'source': [],
    'tests': [],
    'config': [],
    'docs': [],
    'infra': []
}

source_ext = {'.ts','.js','.tsx','.jsx','.py','.go','.rs','.java','.rb','.php','.cs','.cpp','.c','.h','.swift','.kt','.sh'}
test_patterns = ['test', 'spec', '__tests__', '_test.', '.test.', '.spec.']
config_ext = {'.json','.yaml','.yml','.toml','.ini','.cfg','.env'}
doc_ext = {'.md','.txt','.rst','.adoc'}
infra_patterns = ['Dockerfile', '.tf', '.github/', 'ci/', '.gitlab-ci', 'Makefile', 'docker-compose']

for f in files:
    name_lower = f.lower()
    ext = '.' + f.rsplit('.', 1)[-1] if '.' in f else ''

    if any(p in name_lower for p in test_patterns):
        categories['tests'].append(f)
    elif any(p in f for p in infra_patterns):
        categories['infra'].append(f)
    elif ext in doc_ext:
        categories['docs'].append(f)
    elif ext in config_ext:
        categories['config'].append(f)
    elif ext in source_ext:
        categories['source'].append(f)
    else:
        categories['source'].append(f)

result = {
    'status': 'ok',
    'mode': '$MODE',
    'title': '''$TITLE''',
    'head_branch': '$HEAD_BRANCH',
    'base_branch': '$BASE_BRANCH',
    'file_count': len(files),
    'files': files,
    'categories': {k: {'count': len(v), 'files': v} for k, v in categories.items()},
    'pr_number': $PR_NUMBER if '$PR_NUMBER' else None
}
print(json.dumps(result))
" 2>/dev/null || printf '{"status":"ok","mode":"%s","title":"%s","file_count":%s}' "$MODE" "$TITLE" "$FILE_COUNT"
