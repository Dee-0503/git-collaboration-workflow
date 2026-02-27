#!/bin/bash
# enforce-branch-naming — Command hook for branch naming convention
# Fast deterministic check via regex. Runs in parallel with prompt hook.
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Only act on branch creation commands
if ! echo "$COMMAND" | grep -qE 'git\s+(checkout\s+-b|branch\s+[^-]|switch\s+-c)\s+'; then
  exit 0
fi

# Extract branch name
BRANCH=""

# git checkout -b <name>
BRANCH=$(echo "$COMMAND" | sed -nE 's/.*checkout\s+-b\s+([^ ]+).*/\1/p')

# git switch -c <name>
if [ -z "$BRANCH" ]; then
  BRANCH=$(echo "$COMMAND" | sed -nE 's/.*switch\s+-c\s+([^ ]+).*/\1/p')
fi

# git branch <name> (not git branch -d, -D, -m, -a, -r, -l, --list, etc.)
if [ -z "$BRANCH" ]; then
  BRANCH=$(echo "$COMMAND" | sed -nE 's/.*\bgranch\s+([^-][^ ]*).*/\1/p')
  # Fallback: more careful extraction for "git branch <name>"
  if [ -z "$BRANCH" ]; then
    BRANCH=$(echo "$COMMAND" | grep -oE 'git\s+branch\s+[a-zA-Z]' | sed -nE 's/git\s+branch\s+//p')
    if [ -n "$BRANCH" ]; then
      BRANCH=$(echo "$COMMAND" | sed -nE 's/.*git\s+branch\s+([^ ]+).*/\1/p')
    fi
  fi
fi

# Could not extract — let prompt hook handle it
if [ -z "$BRANCH" ]; then
  exit 0
fi

# Validate against naming convention
if echo "$BRANCH" | grep -qE '^(feature|phase|hotfix|release)/[a-z0-9][a-z0-9._-]*$'; then
  exit 0
fi

# Deny
cat >&2 << 'DENY'
Branch name does not follow naming convention.
Required: <type>/<kebab-case-name>
Types: feature | phase | hotfix | release
Name: must start with lowercase letter or digit, using only [a-z0-9._-]
Examples:
  feature/alice-login
  hotfix/fix-auth-crash
  release/v1.0.0
  phase/phase2-api-layer
DENY
exit 2
