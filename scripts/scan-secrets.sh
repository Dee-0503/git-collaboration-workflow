#!/bin/bash
# detect-secrets — Command hook for credential scanning
# Scans staged files for known secret patterns.
# Unlike the prompt hook, this ACTUALLY READS file contents.
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Only act on git add or git commit
if ! echo "$COMMAND" | grep -qE 'git\s+(add|commit)'; then
  exit 0
fi

# Determine files to scan
FILES=""
if echo "$COMMAND" | grep -qE 'git\s+add'; then
  # Extract file paths from git add command (skip flags)
  FILES=$(echo "$COMMAND" | sed 's/git add//' | tr ' ' '\n' | grep -v '^-' | grep -v '^$' | tr '\n' ' ')
  # If "git add ." or "git add -A", scan all modified files
  if echo "$FILES" | grep -qE '^\s*\.\s*$'; then
    FILES=$(git diff --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
  fi
else
  # For git commit, scan staged files
  FILES=$(git diff --cached --name-only 2>/dev/null)
fi

if [ -z "$FILES" ]; then
  exit 0
fi

# Load whitelist patterns from .secretsignore
WHITELIST_FILE=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.secretsignore" ]; then
  WHITELIST_FILE="$CLAUDE_PROJECT_DIR/.secretsignore"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/.secretsignore" ]; then
  WHITELIST_FILE="$CLAUDE_PLUGIN_ROOT/.secretsignore"
fi

# Secret patterns to detect
PATTERNS=(
  'AKIA[0-9A-Z]{16}'
  'ghp_[A-Za-z0-9_]{36,}'
  'ghs_[A-Za-z0-9_]{36,}'
  'sk-[A-Za-z0-9]{48,}'
  '-----BEGIN[[:space:]]+(RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'
  'mongodb(\+srv)?://[^:]+:[^@]+@'
  'postgres(ql)?://[^:]+:[^@]+@'
  'mysql://[^:]+:[^@]+@'
)

FOUND=""
for file in $FILES; do
  # Skip binary files and non-existent files
  [ ! -f "$file" ] && continue
  file -b --mime "$file" 2>/dev/null | grep -q "text/" || continue

  for pattern in "${PATTERNS[@]}"; do
    MATCHES=$(grep -nE "$pattern" "$file" 2>/dev/null || true)
    if [ -n "$MATCHES" ]; then
      # Check whitelist
      WHITELISTED=false
      if [ -n "$WHITELIST_FILE" ]; then
        while IFS= read -r wp; do
          [ -z "$wp" ] && continue
          [[ "$wp" == \#* ]] && continue
          if echo "$MATCHES" | grep -qE "$wp" 2>/dev/null; then
            WHITELISTED=true
            break
          fi
        done < "$WHITELIST_FILE"
      fi

      if [ "$WHITELISTED" = false ]; then
        LINE=$(echo "$MATCHES" | head -1 | cut -d: -f1)
        FOUND="${FOUND}  ${file}:${LINE} — matches pattern: ${pattern}\n"
      fi
    fi
  done
done

if [ -n "$FOUND" ]; then
  printf "Potential secrets/credentials detected in staged files:\n%b\nRemove credentials and use environment variables instead.\nIf these are known false positives, add patterns to .secretsignore.\n" "$FOUND" >&2
  exit 2
fi

exit 0
