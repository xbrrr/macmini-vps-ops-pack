#!/bin/zsh
set -u
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

LOG=/tmp/tailscale-autoconnect.log
TS_BIN=""

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

for candidate in /opt/homebrew/bin/tailscale /opt/homebrew/opt/tailscale/bin/tailscale /usr/local/bin/tailscale; do
  if [[ -x "$candidate" ]]; then
    TS_BIN="$candidate"
    break
  fi
done

log "start"

if [[ -z "$TS_BIN" ]]; then
  log "tailscale CLI missing"
  exit 1
fi

for i in {1..20}; do
  if "$TS_BIN" status --self >> "$LOG" 2>&1; then
    log "tailscale already connected"
    exit 0
  fi

  log "tailscale status failed; trying tailscale up attempt=$i"
  "$TS_BIN" up --accept-routes=true --accept-dns=true >> "$LOG" 2>&1 || true
  sleep 3
done

log "tailscale did not become healthy"
exit 1
