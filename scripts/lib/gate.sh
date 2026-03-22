#!/usr/bin/env bash
# Gate function: check if plugin is enabled for this project
# Reads .claude/git-collab.yml and exits the calling script if disabled.
#
# Usage: source this file at the top of any hook/skill script, then call check_enabled.
#   source "$(dirname "$0")/../lib/gate.sh"
#   check_enabled

check_enabled() {
  local config=".claude/git-collab.yml"
  [ ! -f "$config" ] && exit 0
  local mode=$(grep '^mode:' "$config" | awk '{print $2}')
  [ "$mode" = "disabled" ] && exit 0
  if [ "$mode" = "minimal" ]; then
    case "${HOOK_NAME:-$(basename "$0")}" in
      detect-secrets*|detect-conflict-markers*|scan-secrets*|scan-conflict-markers*) ;;
      *) exit 0 ;;
    esac
  fi
}
