#!/usr/bin/env bash
set -euo pipefail

SERVICE="openclaw-gateway.service"
URL="http://127.0.0.1:18789/"
TIMEOUT_SECONDS=3
LOG_TAG="openclaw-watchdog"
CHANNEL_TIMEOUT_MS=5000
LOCK_FILE="/tmp/openclaw-gateway-watchdog.lock"

log() {
  logger -t "$LOG_TAG" "$*" || true
}

# Prevent overlap if a previous check is still running.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  exit 0
fi

# If systemd thinks it's not active, restart it.
if ! systemctl is-active --quiet "$SERVICE"; then
  log "$SERVICE not active; restarting"
  systemctl restart "$SERVICE"
  exit 0
fi

# Fast liveness check: HTTP 200 on the gateway port.
code="$(curl -sS --max-time "$TIMEOUT_SECONDS" -o /dev/null -w '%{http_code}' "$URL" || true)"
if [[ "$code" != "200" ]]; then
  log "gateway unhealthy (HTTP $code); restarting $SERVICE"
  systemctl restart "$SERVICE"
  exit 0
fi

# Channel liveness check: ensure Telegram polling loop is running.
# NOTE: intentionally uses `channels status`, not `openclaw status`,
# so we do not depend on operator scopes like operator.read.
channels_json="$(openclaw channels status --json --timeout "$CHANNEL_TIMEOUT_MS" 2>/dev/null || true)"
telegram_ok="$(
  CHANNELS_JSON="$channels_json" python3 - <<'PY' 2>/dev/null || echo 0
import json, os, sys
raw = os.environ.get("CHANNELS_JSON","").strip()
if not raw:
    print(0); sys.exit(0)
try:
    j = json.loads(raw)
    chan = (j.get("channels") or {}).get("telegram") or {}
    acct = ((j.get("channelAccounts") or {}).get("telegram") or [{}])[0] or {}
    ok = (
        chan.get("configured") is True and
        chan.get("running") is True and
        (chan.get("lastError") in (None, "")) and
        acct.get("enabled") is True and
        acct.get("configured") is True and
        acct.get("running") is True and
        (acct.get("lastError") in (None, ""))
    )
    print(1 if ok else 0)
except Exception:
    print(0)
PY
)"

if [[ "${telegram_ok}" != "1" ]]; then
  log "telegram channel not healthy; restarting $SERVICE"
  systemctl restart "$SERVICE"
  exit 0
fi

exit 0

