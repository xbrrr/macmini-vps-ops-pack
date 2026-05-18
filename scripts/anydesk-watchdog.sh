#!/bin/zsh
set -u
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin

AD_BIN="/Applications/AnyDesk.app/Contents/MacOS/AnyDesk"
LOGFILE="${HOME}/Library/Logs/anydesk-watchdog.repair.log"
LOCK_DIR="${HOME}/Library/Caches/anydesk-watchdog.lock"
CLI_TIMEOUT_SECONDS=6
EXPECTED_ID="${ANYDESK_EXPECTED_ID:-}"

log() {
  mkdir -p "$(dirname "$LOGFILE")"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOGFILE"
}

cleanup_lock() {
  rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
}

if ! mkdir "$LOCK_DIR" >/dev/null 2>&1; then
  log "skip: previous watchdog still running"
  exit 0
fi
trap cleanup_lock EXIT INT TERM

run_ad_cli() {
  python3 - "$CLI_TIMEOUT_SECONDS" "$AD_BIN" "$@" <<'PY'
import subprocess, sys
seconds = int(sys.argv[1])
cmd = sys.argv[2:]
try:
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=seconds)
    sys.stdout.write(p.stdout or "")
    raise SystemExit(p.returncode)
except subprocess.TimeoutExpired:
    print("TIMEOUT")
    raise SystemExit(124)
except Exception as exc:
    print(f"ERROR: {type(exc).__name__}: {exc}")
    raise SystemExit(125)
PY
}

ad_status() {
  run_ad_cli --get-status 2>&1 | tail -n 1 | tr -d '\r' | tr '[:upper:]' '[:lower:]'
}

ad_id() {
  run_ad_cli --get-id 2>&1 | tail -n 1 | tr -dc '0-9'
}

count_main() {
  pgrep -x AnyDesk 2>/dev/null | wc -l | tr -d ' '
}

count_arg() {
  pgrep -f "/Applications/AnyDesk.app/Contents/MacOS/AnyDesk $1" 2>/dev/null | wc -l | tr -d ' '
}

restart_anydesk() {
  local reason="$1"
  log "repair: $reason; restarting AnyDesk"
  osascript -e 'tell application "AnyDesk" to quit' >/dev/null 2>&1 || true
  sleep 2
  pkill -TERM -f '/Applications/AnyDesk.app/Contents/MacOS/AnyDesk' >/dev/null 2>&1 || true
  sleep 4
  pkill -KILL -f '/Applications/AnyDesk.app/Contents/MacOS/AnyDesk' >/dev/null 2>&1 || true
  sleep 2
  open -a AnyDesk >/dev/null 2>&1 || open /Applications/AnyDesk.app >/dev/null 2>&1 || true
  sleep 10
}


sync_identity_configs() {
  local user_system="$HOME/.anydesk/system.conf"
  local user_service="$HOME/.anydesk/service.conf"
  local etc_system="/etc/anydesk/system.conf"
  local etc_service="/etc/anydesk/service.conf"
  [[ -f "$user_system" && -f "$user_service" && -f "$etc_system" && -f "$etc_service" ]] || return 0

  local user_id etc_id
  user_id="$(awk -F= '/^ad\.anynet\.id=/{print $2; exit}' "$user_system" 2>/dev/null || true)"
  etc_id="$(awk -F= '/^ad\.anynet\.id=/{print $2; exit}' "$etc_system" 2>/dev/null || true)"
  [[ -n "$user_id" ]] || return 0

  if [[ -n "$EXPECTED_ID" && "$user_id" != "$EXPECTED_ID" ]]; then
    log "warn: user config id=$user_id differs from expected=$EXPECTED_ID; not syncing identity"
    return 0
  fi

  if [[ "$etc_id" != "$user_id" ]] || ! cmp -s "$user_system" "$etc_system" || ! cmp -s "$user_service" "$etc_service"; then
    log "identity drift: user=$user_id installed=${etc_id:-missing}; syncing /etc/anydesk from user config"
    if [[ ! -w "$etc_system" || ! -w "$etc_service" ]]; then
      log "identity drift: /etc/anydesk is not writable by user; manual root sync needed"
      return 0
    fi
    cp -p "$etc_system" "$etc_system.bak-watchdog-$(date +%Y%m%d%H%M%S)" >/dev/null 2>&1 || true
    cp -p "$etc_service" "$etc_service.bak-watchdog-$(date +%Y%m%d%H%M%S)" >/dev/null 2>&1 || true
    cp -p "$user_system" "$etc_system"
    cp -p "$user_service" "$etc_service"
  fi
}

if [[ ! -x "$AD_BIN" ]]; then
  log "skip: AnyDesk binary missing: $AD_BIN"
  exit 0
fi

sync_identity_configs

ST="$(ad_status || true)"
ID="$(ad_id || true)"
MAIN_COUNT="$(count_main)"
SERVICE_COUNT="$(count_arg --service)"
LOCAL_SERVICE_COUNT="$(count_arg --local-service)"
CONTROL_COUNT="$(count_arg --control)"
BACKEND_COUNT="$(count_arg --backend)"

if [[ -n "$EXPECTED_ID" && "$ID" != "$EXPECTED_ID" ]]; then
  log "warn: unexpected AnyDesk id live=${ID:-unknown} expected=$EXPECTED_ID"
fi

if [[ "$ST" == "online" && "$MAIN_COUNT" != "0" && "$LOCAL_SERVICE_COUNT" != "0" ]]; then
  exit 0
fi

restart_anydesk "status=${ST:-empty} id=${ID:-empty} main=$MAIN_COUNT service=$SERVICE_COUNT local=$LOCAL_SERVICE_COUNT control=$CONTROL_COUNT backend=$BACKEND_COUNT"

ST2="$(ad_status || true)"
ID2="$(ad_id || true)"
MAIN2="$(count_main)"
LOCAL2="$(count_arg --local-service)"
log "result: status=${ST2:-empty} id=${ID2:-empty} main=$MAIN2 local=$LOCAL2"

exit 0
