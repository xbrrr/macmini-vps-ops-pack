#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
LOCK_FILE="/tmp/openclaw-gateway-watchdog.lock"
LOG_DIR="/tmp/openclaw"
LOG_FILE="$LOG_DIR/gateway-watchdog.log"
SUP_LOG="$LOG_DIR/gateway-supervised.log"

mkdir -p "$LOG_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  exit 0
fi

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" >> "$LOG_FILE"; }

start_gateway() {
  nohup openclaw gateway run --bind loopback >> "$SUP_LOG" 2>&1 &
  sleep 2
}

if timeout 12s openclaw gateway health >/dev/null 2>&1; then
  exit 0
fi

if pgrep -f '^openclaw-gateway$' >/dev/null 2>&1; then
  log "gateway unhealthy, restarting"
  pkill -f '^openclaw-gateway$' || true
  sleep 1
  start_gateway
else
  log "gateway not running, starting"
  start_gateway
fi

if timeout 12s openclaw gateway health >/dev/null 2>&1; then
  log "gateway healthy after action"
else
  log "gateway still unhealthy after action"
fi
