#!/bin/bash
# review-reply.sh — Manage inline review comment replies
# Usage: review-reply.sh <action> <REPO> <PR> [args...]
#   Actions: list-unreplied, reply, collect-threads
set -euo pipefail

source "$(dirname "$0")/lib/gate.sh"
check_enabled

ACTION="${1:-}"
REPO="${2:-}"
PR="${3:-}"
shift 3 || true

if [ -z "$ACTION" ] || [ -z "$REPO" ] || [ -z "$PR" ]; then
  echo '{"status":"error","message":"Usage: review-reply.sh <action> <REPO> <PR> [args...]"}' >&2
  exit 1
fi

MAX_REPLY_LENGTH=500

case "$ACTION" in
  list-unreplied)
    # List claude[bot] inline comments that have no replies
    gh api --paginate "repos/$REPO/pulls/$PR/comments" \
      --jq '[.[] | {id, path, line, body: (.body | split("\n")[0] | .[0:200]),
             user: .user.login, in_reply_to_id}]' 2>/dev/null \
    | python3 -c "
import json, sys
comments = json.load(sys.stdin)

# Find claude[bot] comments
bot_comments = [c for c in comments if c['user'] == 'claude[bot]' and c.get('in_reply_to_id') is None]

# Find which have replies
replied_to_ids = set(c['in_reply_to_id'] for c in comments if c.get('in_reply_to_id'))

unreplied = [c for c in bot_comments if c['id'] not in replied_to_ids]
print(json.dumps(unreplied, indent=2))
" 2>/dev/null
    ;;

  reply)
    # Usage: review-reply.sh reply <REPO> <PR> <COMMENT_ID> <TYPE> <MESSAGE>
    # TYPE: resolved | disputed | wontfix | acknowledged
    COMMENT_ID="${1:-}"
    REPLY_TYPE="${2:-}"
    MESSAGE="${3:-}"

    if [ -z "$COMMENT_ID" ] || [ -z "$REPLY_TYPE" ]; then
      echo '{"status":"error","message":"Usage: reply <REPO> <PR> <COMMENT_ID> <TYPE> <MESSAGE>"}' >&2
      exit 1
    fi

    # Validate type
    case "$REPLY_TYPE" in
      resolved|disputed|wontfix|acknowledged) ;;
      *) echo "{\"status\":\"error\",\"message\":\"Invalid type: $REPLY_TYPE\"}" >&2; exit 1 ;;
    esac

    # Build tag
    TAG=$(echo "$REPLY_TYPE" | tr '[:lower:]' '[:upper:]')

    # Truncate message to MAX_REPLY_LENGTH
    SAFE_MESSAGE=$(echo "$MESSAGE" | head -c "$MAX_REPLY_LENGTH")

    REPLY_BODY="[$TAG] $SAFE_MESSAGE"

    # Post reply
    RESULT=$(gh api "repos/$REPO/pulls/$PR/comments/$COMMENT_ID/replies" \
      -f body="$REPLY_BODY" \
      --jq '{id, body: (.body | .[0:100])}' 2>/dev/null)

    echo "{\"status\":\"ok\",\"comment_id\":$COMMENT_ID,\"type\":\"$REPLY_TYPE\",\"reply\":$RESULT}"
    ;;

  collect-threads)
    # Collect claude[bot] comments + all replies for review prompt context
    gh api --paginate "repos/$REPO/pulls/$PR/comments" \
      --jq '[.[] | select(
        .user.login == "claude[bot]" or .in_reply_to_id != null
      ) | {
        id, path, line,
        body: (.body | split("\n")[0] | .[0:200]),
        user: .user.login,
        is_reply: (.in_reply_to_id != null),
        reply_to: .in_reply_to_id
      }]' 2>/dev/null \
    | python3 -c "
import json, sys
comments = json.load(sys.stdin)

# Group into threads: {comment_id: {comment: ..., replies: [...]}}
threads = {}
replies_map = {}

for c in comments:
    if not c.get('is_reply'):
        threads[c['id']] = {'comment': c, 'replies': []}
    else:
        replies_map.setdefault(c.get('reply_to'), []).append(c)

for cid, thread in threads.items():
    thread['replies'] = replies_map.get(cid, [])

# Output as list of threads
result = []
for cid, thread in threads.items():
    entry = {
        'comment_id': cid,
        'path': thread['comment'].get('path', ''),
        'line': thread['comment'].get('line', 0),
        'finding': thread['comment']['body'],
        'replies': [{'user': r['user'], 'body': r['body']} for r in thread['replies']],
        'has_resolution': any(
            r['body'].startswith(('[RESOLVED]', '[DISPUTED]', '[WONTFIX]'))
            for r in thread['replies']
        )
    }
    result.append(entry)

print(json.dumps(result, indent=2))
" 2>/dev/null
    ;;

  *)
    echo "{\"status\":\"error\",\"message\":\"Unknown action: $ACTION\"}" >&2
    exit 1
    ;;
esac
