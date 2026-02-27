#!/bin/bash
# detect-conflict-markers — Command hook for unresolved merge conflict detection
# Scans staged files for conflict markers (<<<<<<<, =======, >>>>>>>).
# Unlike the prompt hook, this ACTUALLY READS file contents.
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Only act on git commit or git add
if ! echo "$COMMAND" | grep -qE 'git\s+(commit|add)'; then
  exit 0
fi

# Determine files to scan
FILES=""
if echo "$COMMAND" | grep -qE 'git\s+add'; then
  FILES=$(echo "$COMMAND" | sed 's/git add//' | tr ' ' '\n' | grep -v '^-' | grep -v '^$' | tr '\n' ' ')
  if echo "$FILES" | grep -qE '^\s*\.\s*$'; then
    FILES=$(git diff --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
  fi
else
  FILES=$(git diff --cached --name-only 2>/dev/null)
fi

if [ -z "$FILES" ]; then
  exit 0
fi

FOUND=""
for file in $FILES; do
  [ ! -f "$file" ] && continue
  # Skip binary files
  file -b --mime "$file" 2>/dev/null | grep -q "text/" || continue

  # Check for conflict markers
  MARKERS=$(grep -nE '^(<{7}|={7}|>{7})' "$file" 2>/dev/null || true)
  if [ -n "$MARKERS" ]; then
    LINES=$(echo "$MARKERS" | head -3 | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
    FOUND="${FOUND}  ${file} (lines: ${LINES})\n"
  fi
done

if [ -n "$FOUND" ]; then
  printf "Unresolved merge conflict markers detected:\n%b\nResolve all conflicts before committing.\nLook for <<<<<<< ======= >>>>>>> markers and choose the correct code.\n" "$FOUND" >&2
  exit 2
fi

exit 0
