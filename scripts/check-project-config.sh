#!/bin/bash
# check-project-config.sh — UserPromptSubmit gate
# Blocks user interaction until .claude/git-collab.yml is configured.
# exit 2 = block with error message shown to user in UI.
# exit 0 = allow prompt to proceed.
set -euo pipefail

CONFIG=".claude/git-collab.yml"

# If config exists, allow
if [ -f "$CONFIG" ]; then
  exit 0
fi

# Read user prompt from stdin to allow setup commands through
USER_PROMPT=$(cat 2>/dev/null || echo "")
if echo "$USER_PROMPT" | grep -qi "setup-project\|setup_project\|git-collab\|git.collab"; then
  exit 0
fi

# No config — block and show setup instructions
cat >&2 <<'MSG'
[Git Collaboration Workflow] 项目未配置

首次使用需要初始化配置。请输入 /setup-project 完成引导式配置。
MSG
exit 2
