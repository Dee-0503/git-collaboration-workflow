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

# No config — block and show setup instructions
cat >&2 <<'MSG'
[Git Collaboration Workflow] 项目未配置

首次使用需要初始化配置。请运行 /setup-project 完成配置，或手动创建配置文件：

  mkdir -p .claude
  echo "mode: full" > .claude/git-collab.yml

可选模式：
  full     — 全部 hook 生效（推荐）
  minimal  — 仅 secret 扫描 + 冲突标记检测
  disabled — 关闭插件
MSG
exit 2
