#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_command date
require_command grep
require_command pgrep
require_command pkill
require_command sed

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This script is intended to run on macOS"
fi

ANYDESK_APP_PATH="${ANYDESK_APP_PATH:-/Applications/AnyDesk.app}"
ANYDESK_BIN="${ANYDESK_BIN:-${ANYDESK_APP_PATH}/Contents/MacOS/AnyDesk}"
ANYDESK_SUPPORT_DIR="${ANYDESK_SUPPORT_DIR:-$HOME/Library/Application Support/AnyDesk}"
RESET_NETWORK_CACHE="${RESET_NETWORK_CACHE:-0}"

log_info() {
  log "anydesk" "$1"
}

restart_user_agent() {
  local user_uid
  user_uid="$(id -u)"
  local agent
  agent="$(launchctl print "gui/${user_uid}" 2>/dev/null | sed -n 's/.*\(com\.philandro\.anydesk-frontend\).*/\1/p' | head -1 || true)"
  if [[ -n "$agent" ]]; then
    log_info "Restarting launch agent ${agent}"
    launchctl kickstart -k "gui/${user_uid}/${agent}" >/dev/null 2>&1 || true
  else
    log_info "LaunchAgent label not discovered; continuing with process restart"
  fi
}

print_status() {
  echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "host=$(scutil --get LocalHostName 2>/dev/null || hostname)"
  echo "binary_present=$([[ -x "${ANYDESK_BIN}" ]] && echo yes || echo no)"
  echo "support_dir_present=$([[ -d "${ANYDESK_SUPPORT_DIR}" ]] && echo yes || echo no)"
  echo "app_processes=$(pgrep -lf AnyDesk || true)"
  echo "launch_agents=$(launchctl print "gui/$(id -u)" 2>/dev/null | grep -i anydesk || true)"
  echo "tcp_listeners=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | grep -i AnyDesk || true)"
}

if [[ ! -x "${ANYDESK_BIN}" ]]; then
  die "AnyDesk binary not found at ${ANYDESK_BIN}"
fi

log_info "Collecting pre-restart status"
print_status

log_info "Stopping AnyDesk processes"
pkill -x AnyDesk 2>/dev/null || true
sleep 2

restart_user_agent

if [[ "${RESET_NETWORK_CACHE}" == "1" ]]; then
  if [[ -d "${ANYDESK_SUPPORT_DIR}" ]]; then
    local backup_dir
    backup_dir="${ANYDESK_SUPPORT_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    log_info "Backing up support directory to ${backup_dir}"
    mv "${ANYDESK_SUPPORT_DIR}" "${backup_dir}"
  fi
fi

log_info "Starting AnyDesk app"
open -a "${ANYDESK_APP_PATH}" >/dev/null 2>&1 || "${ANYDESK_BIN}" >/dev/null 2>&1 &
sleep 5

log_info "Collecting post-restart status"
print_status

log_info "Recovery attempt finished"
