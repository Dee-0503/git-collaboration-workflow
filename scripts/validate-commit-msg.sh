#!/bin/bash
# enforce-commit-format — Command hook for Conventional Commits validation
# Fast deterministic check via regex. Runs in parallel with prompt hook.
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Only act on git commit -m
if ! echo "$COMMAND" | grep -qE 'git\s+commit\s+.*-m\s+'; then
  exit 0
fi

# Extract message from various quoting styles:
#   git commit -m "message"
#   git commit -m 'message'
#   git commit -m "$(cat <<'EOF'\n...\nEOF\n)"
MSG=""

# Try double-quoted
MSG=$(echo "$COMMAND" | sed -nE 's/.*-m\s+"([^"]+)".*/\1/p')

# Try single-quoted
if [ -z "$MSG" ]; then
  MSG=$(echo "$COMMAND" | sed -nE "s/.*-m\s+'([^']+)'.*/\1/p")
fi

# Try HEREDOC (extract first line after EOF marker)
if [ -z "$MSG" ]; then
  MSG=$(echo "$COMMAND" | sed -nE 's/.*-m\s+"\$\(cat <<.*//p' | head -1)
fi

# Could not extract message — let prompt hook handle it
if [ -z "$MSG" ]; then
  exit 0
fi

# Take first line only (for multi-line messages)
MSG=$(echo "$MSG" | head -1)

# Validate against Conventional Commits regex
if echo "$MSG" | grep -qE '^(feat|fix|docs|chore|refactor|test|ci|build|perf|style)(\(.+\))?!?:\s.+$'; then
  exit 0
fi

# Deny
cat >&2 << 'DENY'
Commit message does not follow Conventional Commits format.
Required: <type>[optional scope]: <description>
Types: feat | fix | docs | chore | refactor | test | ci | build | perf | style
Examples:
  feat: add login page
  fix(auth): resolve token expiry bug
  docs: update API reference
  chore!: drop Node 14 support
DENY
exit 2
