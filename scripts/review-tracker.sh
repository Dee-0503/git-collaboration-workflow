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

    DB_FILE="$DB_FILE" PR_NUM="$PR_NUM" BRANCH="$BRANCH" NOW="$(now_utc)" \
    python3 -c "
import json, os, fcntl
db_file = os.environ['DB_FILE']
pr_num = os.environ['PR_NUM']
branch = os.environ['BRANCH']
now = os.environ['NOW']
lock_fd = open(db_file + '.lock', 'w')
fcntl.flock(lock_fd, fcntl.LOCK_EX)
with open(db_file, 'r') as f:
    db = json.load(f)
db['prs'][pr_num] = {
    'branch': branch,
    'status': 'pending_review',
    'round': 1,
    'created_at': now,
    'updated_at': now,
    'last_check': '',
    'comments_count': 0
}
with open(db_file, 'w') as f:
    json.dump(db, f, indent=2)
fcntl.flock(lock_fd, fcntl.LOCK_UN)
lock_fd.close()
print(json.dumps({'status': 'ok', 'pr': pr_num, 'state': 'pending_review'}))
"
    ;;

  status)
    PR_NUM="${1:?PR number required}"
    ensure_db
    DB_FILE="$DB_FILE" PR_NUM="$PR_NUM" python3 -c "
import json, os, sys
db_file = os.environ['DB_FILE']
pr_num = os.environ['PR_NUM']
with open(db_file, 'r') as f:
    db = json.load(f)
pr = db['prs'].get(pr_num)
if pr:
    print(json.dumps({'status': 'ok', 'pr': pr_num, **pr}))
else:
    print(json.dumps({'status': 'not_found', 'pr': pr_num}), file=sys.stderr)
    sys.exit(1)
"
    ;;

  update)
    PR_NUM="${1:?PR number required}"
    NEW_STATUS="${2:?New status required}"
    COMMENTS="${3:-0}"
    ensure_db
    DB_FILE="$DB_FILE" PR_NUM="$PR_NUM" NEW_STATUS="$NEW_STATUS" \
    UPDATED_AT="$(now_utc)" COMMENTS="$COMMENTS" python3 -c "
import json, os, sys, fcntl
db_file = os.environ['DB_FILE']
pr_num = os.environ['PR_NUM']
new_status = os.environ['NEW_STATUS']
updated_at = os.environ['UPDATED_AT']
comments = int(os.environ['COMMENTS'])
lock_fd = open(db_file + '.lock', 'w')
fcntl.flock(lock_fd, fcntl.LOCK_EX)
with open(db_file, 'r') as f:
    db = json.load(f)
pr = db['prs'].get(pr_num)
if pr:
    old_status = pr['status']
    pr['status'] = new_status
    pr['updated_at'] = updated_at
    pr['last_check'] = updated_at
    pr['comments_count'] = comments
    if new_status == 'pending_review' and old_status == 'fixing':
        pr['round'] = pr.get('round', 1) + 1
    with open(db_file, 'w') as f:
        json.dump(db, f, indent=2)
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    lock_fd.close()
    print(json.dumps({'status': 'ok', 'pr': pr_num, 'state': new_status}))
else:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    lock_fd.close()
    print(json.dumps({'status': 'not_found', 'pr': pr_num}), file=sys.stderr)
    sys.exit(1)
"
    ;;

  list)
    ensure_db
    DB_FILE="$DB_FILE" python3 -c "
import json, os
db_file = os.environ['DB_FILE']
with open(db_file, 'r') as f:
    db = json.load(f)
active = {k: v for k, v in db['prs'].items() if v['status'] not in ('passed', 'closed')}
print(json.dumps({'status': 'ok', 'total': len(db['prs']), 'active': len(active), 'prs': db['prs']}))
"
    ;;

  cleanup)
    ensure_db
    DB_FILE="$DB_FILE" python3 -c "
import json, os, fcntl
db_file = os.environ['DB_FILE']
lock_fd = open(db_file + '.lock', 'w')
fcntl.flock(lock_fd, fcntl.LOCK_EX)
with open(db_file, 'r') as f:
    db = json.load(f)
removed = [k for k, v in db['prs'].items() if v['status'] in ('passed', 'closed')]
for k in removed:
    del db['prs'][k]
with open(db_file, 'w') as f:
    json.dump(db, f, indent=2)
fcntl.flock(lock_fd, fcntl.LOCK_UN)
lock_fd.close()
print(json.dumps({'status': 'ok', 'removed': len(removed), 'remaining': len(db['prs'])}))
"
    ;;

  *)
    echo '{"status":"error","message":"Unknown action: '"$ACTION"'. Use: init, register, status, update, list, cleanup"}' >&2
    exit 1
    ;;
esac
