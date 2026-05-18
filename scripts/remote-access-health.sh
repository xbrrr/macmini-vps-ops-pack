#!/bin/zsh
set -u
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
LOG="$HOME/Library/Logs/remote-access-health.log"
TS=/opt/homebrew/bin/tailscale
AD=/Applications/AnyDesk.app/Contents/MacOS/AnyDesk
now() { date '+%Y-%m-%d %H:%M:%S'; }
line() { printf '%s %s\n' "$(now)" "$*" >> "$LOG"; }
check_port() {
  local host="$1" port="$2" name="$3"
  if nc -z -G 3 "$host" "$port" >/dev/null 2>&1; then
    line "OK $name $host:$port"
    return 0
  else
    line "FAIL $name $host:$port"
    return 1
  fi
}
mkdir -p "$(dirname "$LOG")"
TS_IP=""
if [[ -x "$TS" ]] && "$TS" status --self >/dev/null 2>&1; then
  TS_IP="$($TS ip -4 2>/dev/null | head -1)"
  line "OK tailscale ip=${TS_IP:-unknown}"
else
  line "FAIL tailscale status; trying up"
  [[ -x "$TS" ]] && "$TS" up --ssh --accept-routes=true --accept-dns=true >> "$LOG" 2>&1 || true
  TS_IP="$($TS ip -4 2>/dev/null | head -1)"
fi
if [[ -n "$TS_IP" ]]; then
  check_port "$TS_IP" 22 ssh || true
  check_port "$TS_IP" 5900 vnc || true
fi
if [[ -x "$AD" ]]; then
  AD_STATUS="$($AD --get-status 2>&1 | tail -1 | tr -d '\r')"
  AD_ID="$($AD --get-id 2>&1 | tail -1 | tr -dc '0-9')"
  line "AnyDesk status=$AD_STATUS id=${AD_ID:-unknown}"
  if [[ "$AD_STATUS" != "online" ]]; then
    launchctl kickstart -k system/com.anydesk.service >/dev/null 2>&1 || true
    open -a AnyDesk >/dev/null 2>&1 || true
    line "AnyDesk repair attempted"
  fi
fi
exit 0
