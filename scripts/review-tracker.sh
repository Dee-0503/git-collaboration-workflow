#!/bin/bash
# review-tracker.sh — Local JSON DB for PR review state tracking
# Usage: review-tracker.sh <action> [args...]
#   Actions: init, register <pr_number> <branch>, status <pr_number>,
#            update <pr_number> <new_status> [comments_count], list, cleanup
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$REPO_ROOT" ]; then
  echo '{"status":"error","message":"Not a git repository"}' >&2
  exit 1
fi

DB_DIR="${REPO_ROOT}/.claude"
DB_FILE="${DB_DIR}/review-tracker.json"

ACTION="${1:-list}"
shift || true

ensure_db() {
  mkdir -p "$DB_DIR"
  if [ ! -f "$DB_FILE" ]; then
    printf '{"prs":{}}\n' > "$DB_FILE"
  fi
}

now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

case "$ACTION" in
  init)
    ensure_db
    printf '{"status":"ok","db_path":"%s"}\n' "$DB_FILE"
    ;;

  register)
    PR_NUM="${1:?PR number required}"
    BRANCH="${2:?Branch name required}"
    ensure_db

    python3 -c "
import json, sys
with open('$DB_FILE', 'r') as f:
    db = json.load(f)
db['prs']['$PR_NUM'] = {
    'branch': '$BRANCH',
    'status': 'pending_review',
    'round': 1,
    'created_at': '$(now_utc)',
    'updated_at': '$(now_utc)',
    'last_check': '',
    'comments_count': 0
}
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print(json.dumps({'status': 'ok', 'pr': '$PR_NUM', 'state': 'pending_review'}))
"
    ;;

  status)
    PR_NUM="${1:?PR number required}"
    ensure_db
    python3 -c "
import json
with open('$DB_FILE', 'r') as f:
    db = json.load(f)
pr = db['prs'].get('$PR_NUM')
if pr:
    print(json.dumps({'status': 'ok', 'pr': '$PR_NUM', **pr}))
else:
    print(json.dumps({'status': 'not_found', 'pr': '$PR_NUM'}))
"
    ;;

  update)
    PR_NUM="${1:?PR number required}"
    NEW_STATUS="${2:?New status required}"
    COMMENTS="${3:-0}"
    ensure_db
    python3 -c "
import json
with open('$DB_FILE', 'r') as f:
    db = json.load(f)
pr = db['prs'].get('$PR_NUM')
if pr:
    old_status = pr['status']
    pr['status'] = '$NEW_STATUS'
    pr['updated_at'] = '$(now_utc)'
    pr['comments_count'] = int('$COMMENTS')
    if '$NEW_STATUS' == 'pending_review' and old_status == 'fixing':
        pr['round'] = pr.get('round', 1) + 1
    with open('$DB_FILE', 'w') as f:
        json.dump(db, f, indent=2)
    print(json.dumps({'status': 'ok', 'pr': '$PR_NUM', 'state': '$NEW_STATUS'}))
else:
    print(json.dumps({'status': 'not_found', 'pr': '$PR_NUM'}))
"
    ;;

  list)
    ensure_db
    python3 -c "
import json
with open('$DB_FILE', 'r') as f:
    db = json.load(f)
active = {k: v for k, v in db['prs'].items() if v['status'] not in ('passed', 'closed')}
print(json.dumps({'status': 'ok', 'total': len(db['prs']), 'active': len(active), 'prs': db['prs']}))
"
    ;;

  cleanup)
    ensure_db
    python3 -c "
import json
with open('$DB_FILE', 'r') as f:
    db = json.load(f)
removed = [k for k, v in db['prs'].items() if v['status'] in ('passed', 'closed')]
for k in removed:
    del db['prs'][k]
with open('$DB_FILE', 'w') as f:
    json.dump(db, f, indent=2)
print(json.dumps({'status': 'ok', 'removed': len(removed), 'remaining': len(db['prs'])}))
"
    ;;

  *)
    echo '{"status":"error","message":"Unknown action: '"$ACTION"'. Use: init, register, status, update, list, cleanup"}' >&2
    exit 1
    ;;
esac
