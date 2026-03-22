#!/bin/bash
# review-state.sh — Finding state CRUD via PR Comment storage
# Usage: review-state.sh <action> <REPO> <PR> [args...]
#   Actions: init, get, update, upsert, filter, converged, summary
set -euo pipefail

source "$(dirname "$0")/lib/gate.sh"
check_enabled

ACTION="${1:-}"
REPO="${2:-}"
PR="${3:-}"
shift 3 || true

MARKER_START="<!-- REVIEW_STATE_V1_START -->"
MARKER_END="<!-- REVIEW_STATE_V1_END -->"
SCHEMA_VERSION="1.0"

if [ -z "$ACTION" ] || [ -z "$REPO" ] || [ -z "$PR" ]; then
  echo '{"status":"error","message":"Usage: review-state.sh <action> <REPO> <PR> [args...]"}' >&2
  exit 1
fi

# Find the state comment ID, returns "" if not found
find_state_comment_id() {
  gh api --paginate "repos/$REPO/issues/$PR/comments" \
    --jq ".[] | select(.body | test(\"$MARKER_START\")) | .id" \
    2>/dev/null | head -1 || echo ""
}

# Extract JSON from state comment body
extract_state_json() {
  local BODY="$1"
  echo "$BODY" | python3 -c "
import sys, json, re
body = sys.stdin.read()
match = re.search(r'\`\`\`json\n(.*?)\n\`\`\`', body, re.DOTALL)
if match:
    obj = json.loads(match.group(1))
    print(json.dumps(obj))
else:
    print(json.dumps({'schema_version': '$SCHEMA_VERSION', 'pr_number': $PR, 'last_updated_round': 0, 'findings': {}}))
" 2>/dev/null
}

# Build the full comment body from JSON state
build_comment_body() {
  local STATE_JSON="$1"
  local STATS
  STATS=$(echo "$STATE_JSON" | python3 -c "
import sys, json
s = json.load(sys.stdin)
f = s.get('findings', {})
counts = {}
for v in f.values():
    st = v.get('status', 'OPEN')
    counts[st] = counts.get(st, 0) + 1
rnd = s.get('last_updated_round', 0)
parts = [f'Round {rnd}']
for k in ['OPEN','RESOLVED','DISPUTED','WONTFIX']:
    parts.append(f'{k}: {counts.get(k, 0)}')
print(' | '.join(parts))
" 2>/dev/null)

  cat <<BODY
$MARKER_START
\`\`\`json
$STATE_JSON
\`\`\`
$MARKER_END

**Review State** | $STATS
BODY
}

case "$ACTION" in
  init)
    # Check if state comment already exists
    COMMENT_ID=$(find_state_comment_id)
    if [ -n "$COMMENT_ID" ]; then
      echo "{\"status\":\"ok\",\"action\":\"exists\",\"comment_id\":$COMMENT_ID}"
      exit 0
    fi

    # Create initial state
    INIT_STATE=$(python3 -c "
import json
print(json.dumps({
    'schema_version': '$SCHEMA_VERSION',
    'pr_number': $PR,
    'last_updated_round': 0,
    'findings': {}
}, indent=2))
" 2>/dev/null)

    BODY=$(build_comment_body "$INIT_STATE")
    NEW_ID=$(gh api "repos/$REPO/issues/$PR/comments" \
      -f body="$BODY" \
      --jq '.id' 2>/dev/null)
    echo "{\"status\":\"ok\",\"action\":\"created\",\"comment_id\":$NEW_ID}"
    ;;

  get)
    COMMENT_ID=$(find_state_comment_id)
    if [ -z "$COMMENT_ID" ]; then
      # No state yet — return empty state
      python3 -c "
import json
print(json.dumps({
    'schema_version': '$SCHEMA_VERSION',
    'pr_number': $PR,
    'last_updated_round': 0,
    'findings': {}
}, indent=2))
"
      exit 0
    fi

    COMMENT_BODY=$(gh api "repos/$REPO/issues/comments/$COMMENT_ID" --jq '.body' 2>/dev/null)
    extract_state_json "$COMMENT_BODY"
    ;;

  update)
    # Usage: review-state.sh update <REPO> <PR> <FINDING_ID> <STATUS> [NOTE]
    FINDING_ID="${1:-}"
    NEW_STATUS="${2:-}"
    NOTE="${3:-}"

    if [ -z "$FINDING_ID" ] || [ -z "$NEW_STATUS" ]; then
      echo '{"status":"error","message":"Usage: update <REPO> <PR> <FINDING_ID> <STATUS> [NOTE]"}' >&2
      exit 1
    fi

    # Validate status
    case "$NEW_STATUS" in
      OPEN|RESOLVED|DISPUTED|WONTFIX) ;;
      *) echo "{\"status\":\"error\",\"message\":\"Invalid status: $NEW_STATUS. Must be OPEN|RESOLVED|DISPUTED|WONTFIX\"}" >&2; exit 1 ;;
    esac

    # Get current state
    COMMENT_ID=$(find_state_comment_id)
    if [ -z "$COMMENT_ID" ]; then
      echo '{"status":"error","message":"No review state found. Run init first."}' >&2
      exit 1
    fi

    COMMENT_BODY=$(gh api "repos/$REPO/issues/comments/$COMMENT_ID" --jq '.body' 2>/dev/null)
    CURRENT_STATE=$(extract_state_json "$COMMENT_BODY")

    # Update finding status
    UPDATED_STATE=$(CURRENT_STATE="$CURRENT_STATE" FINDING_ID="$FINDING_ID" \
      NEW_STATUS="$NEW_STATUS" NOTE="$NOTE" python3 -c "
import json, os, sys
state = json.loads(os.environ['CURRENT_STATE'])
fid = os.environ['FINDING_ID']
new_status = os.environ['NEW_STATUS']
note = os.environ.get('NOTE', '')

if fid not in state['findings']:
    print(json.dumps({'status': 'error', 'message': f'Finding {fid} not found'}), file=sys.stderr)
    sys.exit(1)

state['findings'][fid]['status'] = new_status
if note:
    state['findings'][fid]['resolution_note'] = note
if new_status == 'RESOLVED':
    state['findings'][fid]['resolved_round'] = state.get('last_updated_round', 0)
print(json.dumps(state, indent=2))
" 2>/dev/null)

    if [ $? -ne 0 ]; then
      echo "$UPDATED_STATE" >&2
      exit 1
    fi

    # Write back
    BODY=$(build_comment_body "$UPDATED_STATE")
    gh api "repos/$REPO/issues/comments/$COMMENT_ID" \
      -X PATCH -f body="$BODY" --silent 2>/dev/null
    echo "{\"status\":\"ok\",\"finding\":\"$FINDING_ID\",\"new_status\":\"$NEW_STATUS\"}"
    ;;

  upsert)
    # Usage: review-state.sh upsert <REPO> <PR> <FINDINGS_JSON_FILE> [ROUND]
    # FINDINGS_JSON_FILE: path to JSON file with array of new findings
    # Each finding: {file, line_start, line_end, category, summary}
    FINDINGS_FILE="${1:-}"
    ROUND="${2:-}"

    if [ -z "$FINDINGS_FILE" ] || [ ! -f "$FINDINGS_FILE" ]; then
      echo '{"status":"error","message":"Usage: upsert <REPO> <PR> <findings.json> [round]"}' >&2
      exit 1
    fi

    # Ensure state exists
    COMMENT_ID=$(find_state_comment_id)
    if [ -z "$COMMENT_ID" ]; then
      # Auto-init
      "$0" init "$REPO" "$PR" > /dev/null
      COMMENT_ID=$(find_state_comment_id)
    fi

    COMMENT_BODY=$(gh api "repos/$REPO/issues/comments/$COMMENT_ID" --jq '.body' 2>/dev/null)
    CURRENT_STATE=$(extract_state_json "$COMMENT_BODY")

    # Merge new findings into state
    UPDATED_STATE=$(CURRENT_STATE="$CURRENT_STATE" ROUND="$ROUND" python3 -c "
import json, os, sys, hashlib

state = json.loads(os.environ['CURRENT_STATE'])
round_num = int(os.environ.get('ROUND', '0')) or (state.get('last_updated_round', 0) + 1)
state['last_updated_round'] = round_num

with open('$FINDINGS_FILE') as f:
    new_findings = json.load(f)

for nf in new_findings:
    # Generate finding ID: sha256(file:line_start:category) first 8 chars
    key = f\"{nf['file']}:{nf.get('line_start',0)}:{nf.get('category','general')}\"
    fid = 'f-' + hashlib.sha256(key.encode()).hexdigest()[:8]

    if fid in state['findings']:
        # Existing finding: update last_evaluated_round, keep status
        state['findings'][fid]['last_evaluated_round'] = round_num
        state['findings'][fid]['summary'] = nf.get('summary', state['findings'][fid].get('summary', ''))
    else:
        # New finding
        state['findings'][fid] = {
            'file': nf['file'],
            'line_range': [nf.get('line_start', 0), nf.get('line_end', 0)],
            'category': nf.get('category', 'general'),
            'summary': nf.get('summary', ''),
            'status': 'OPEN',
            'first_seen_round': round_num,
            'last_evaluated_round': round_num
        }

print(json.dumps(state, indent=2))
" 2>/dev/null)

    # Write back
    BODY=$(build_comment_body "$UPDATED_STATE")
    gh api "repos/$REPO/issues/comments/$COMMENT_ID" \
      -X PATCH -f body="$BODY" --silent 2>/dev/null

    # Output stats
    echo "$UPDATED_STATE" | python3 -c "
import json, sys
s = json.load(sys.stdin)
f = s['findings']
counts = {}
for v in f.values():
    st = v.get('status', 'OPEN')
    counts[st] = counts.get(st, 0) + 1
print(json.dumps({
    'status': 'ok',
    'round': s['last_updated_round'],
    'total': len(f),
    'open': counts.get('OPEN', 0),
    'resolved': counts.get('RESOLVED', 0),
    'disputed': counts.get('DISPUTED', 0),
    'wontfix': counts.get('WONTFIX', 0)
}))
" 2>/dev/null
    ;;

  filter)
    # Returns only OPEN and DISPUTED findings as JSON (for review prompt injection)
    COMMENT_ID=$(find_state_comment_id)
    if [ -z "$COMMENT_ID" ]; then
      echo '[]'
      exit 0
    fi

    COMMENT_BODY=$(gh api "repos/$REPO/issues/comments/$COMMENT_ID" --jq '.body' 2>/dev/null)
    CURRENT_STATE=$(extract_state_json "$COMMENT_BODY")

    echo "$CURRENT_STATE" | python3 -c "
import json, sys
state = json.load(sys.stdin)
active = []
for fid, f in state.get('findings', {}).items():
    if f.get('status') in ('OPEN', 'DISPUTED'):
        entry = dict(f)
        entry['id'] = fid
        active.append(entry)
print(json.dumps(active, indent=2))
" 2>/dev/null
    ;;

  converged)
    # Check convergence: exit 0 if converged, exit 1 if not
    # Convergence = no OPEN findings AND last_updated_round >= 2
    COMMENT_ID=$(find_state_comment_id)
    if [ -z "$COMMENT_ID" ]; then
      echo '{"converged":false,"reason":"no state found"}'
      exit 1
    fi

    COMMENT_BODY=$(gh api "repos/$REPO/issues/comments/$COMMENT_ID" --jq '.body' 2>/dev/null)
    CURRENT_STATE=$(extract_state_json "$COMMENT_BODY")

    echo "$CURRENT_STATE" | python3 -c "
import json, sys
state = json.load(sys.stdin)
findings = state.get('findings', {})
round_num = state.get('last_updated_round', 0)

open_count = sum(1 for f in findings.values() if f.get('status') == 'OPEN')
disputed_count = sum(1 for f in findings.values() if f.get('status') == 'DISPUTED')
total = len(findings)

result = {
    'round': round_num,
    'total_findings': total,
    'open': open_count,
    'disputed': disputed_count
}

if round_num < 2:
    result['converged'] = False
    result['reason'] = f'Only {round_num} round(s), need >= 2'
    print(json.dumps(result))
    sys.exit(1)
elif open_count > 0:
    result['converged'] = False
    result['reason'] = f'{open_count} OPEN finding(s) remain'
    print(json.dumps(result))
    sys.exit(1)
elif disputed_count > 0:
    result['converged'] = False
    result['reason'] = f'{disputed_count} DISPUTED finding(s) need resolution'
    print(json.dumps(result))
    sys.exit(1)
else:
    result['converged'] = True
    result['reason'] = 'All findings resolved'
    print(json.dumps(result))
    sys.exit(0)
" 2>/dev/null
    CONV_EXIT=$?
    exit $CONV_EXIT
    ;;

  summary)
    # Human-readable summary
    COMMENT_ID=$(find_state_comment_id)
    if [ -z "$COMMENT_ID" ]; then
      echo "No review state found for PR #$PR"
      exit 0
    fi

    COMMENT_BODY=$(gh api "repos/$REPO/issues/comments/$COMMENT_ID" --jq '.body' 2>/dev/null)
    CURRENT_STATE=$(extract_state_json "$COMMENT_BODY")

    echo "$CURRENT_STATE" | python3 -c "
import json, sys
state = json.load(sys.stdin)
findings = state.get('findings', {})
round_num = state.get('last_updated_round', 0)

counts = {}
for f in findings.values():
    st = f.get('status', 'OPEN')
    counts[st] = counts.get(st, 0) + 1

print(f'PR #{state[\"pr_number\"]} Review State (Round {round_num})')
print(f'  Total findings: {len(findings)}')
for status in ['OPEN', 'RESOLVED', 'DISPUTED', 'WONTFIX']:
    c = counts.get(status, 0)
    if c > 0:
        print(f'  {status}: {c}')

# Show OPEN findings detail
open_findings = [(fid, f) for fid, f in findings.items() if f.get('status') == 'OPEN']
if open_findings:
    print(f'\nOpen findings:')
    for fid, f in open_findings:
        print(f'  [{fid}] {f[\"file\"]}:{f[\"line_range\"][0]} — {f[\"summary\"]}')
" 2>/dev/null
    ;;

  *)
    echo "{\"status\":\"error\",\"message\":\"Unknown action: $ACTION\"}" >&2
    exit 1
    ;;
esac
