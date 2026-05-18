#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
LOG="$HOME/Library/Logs/remote-access-watchdog.log"
AD="/Applications/AnyDesk.app/Contents/MacOS/AnyDesk"
LAN_INTERFACE="${REMOTE_ACCESS_LAN_INTERFACE:-en1}"
LAN_SERVICE="${REMOTE_ACCESS_LAN_SERVICE:-Wi-Fi}"
LAN_IP="${REMOTE_ACCESS_LAN_IP:-}"
LAN_NETMASK="${REMOTE_ACCESS_LAN_NETMASK:-255.255.255.0}"
LAN_ROUTER="${REMOTE_ACCESS_LAN_ROUTER:-}"
LAN_DNS="${REMOTE_ACCESS_LAN_DNS:-}"
log(){ mkdir -p "$(dirname "$LOG")"; printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

# Keep the LAN endpoint predictable for local VNC/SSH when configured by env.
current_ip="$(ipconfig getifaddr "$LAN_INTERFACE" 2>/dev/null || true)"
if [[ -n "$LAN_IP" && "$current_ip" != "$LAN_IP" ]]; then
  log "lan ip drift: ${current_ip:-none}; restoring $LAN_IP"
  if [[ -n "$LAN_ROUTER" ]]; then
    networksetup -setmanual "$LAN_SERVICE" "$LAN_IP" "$LAN_NETMASK" "$LAN_ROUTER" >/dev/null 2>&1 || true
  fi
  if [[ -n "$LAN_DNS" ]]; then
    # shellcheck disable=SC2086
    networksetup -setdnsservers "$LAN_SERVICE" $LAN_DNS >/dev/null 2>&1 || true
  fi
fi

# Screen Sharing is socket-activated; kickstart keeps the VNC socket present.
if ! netstat -an -p tcp 2>/dev/null | grep -q '\.5900 .*LISTEN'; then
  log "vnc listener missing; kickstarting screen sharing"
  launchctl kickstart -k system/com.apple.screensharing >/dev/null 2>&1 || true
fi

# Remote Login is socket-activated too; log if socket disappears.
if ! netstat -an -p tcp 2>/dev/null | grep -q '\.22 .*LISTEN'; then
  log "ssh listener missing"
fi

# Tailscale is headless Homebrew daemon, not a GUI app. Check health only; launchd owns restart.
if command -v tailscale >/dev/null 2>&1; then
  if ! tailscale status --self >/dev/null 2>&1; then
    log "tailscale status failed"
  fi
fi

# AnyDesk often leaves root service alive but user/control side down. Relaunch user side.
if [[ -x "$AD" ]]; then
  st="$($AD --get-status 2>&1 | tail -n 1 | tr -d '\r' || true)"
  if [[ "$st" != "online" ]]; then
    log "anydesk status=$st; relaunching user app"
    osascript -e 'tell application "AnyDesk" to quit' >/dev/null 2>&1 || true
    pkill -u "$USER" -f '/Applications/AnyDesk.app/Contents/MacOS/AnyDesk( --control| --local-service| --backend)?$' >/dev/null 2>&1 || true
    open -a AnyDesk >/dev/null 2>&1 || true
  fi
fi
