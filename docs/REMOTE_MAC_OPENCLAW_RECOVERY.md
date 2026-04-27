# Remote Mac + OpenClaw Recovery Runbook

This runbook captures the sanitized recovery pattern for a headless Mac mini that runs OpenClaw, AnyDesk, and Tailscale.

Do not store real hostnames, public IPs, private tailnet IPs, account emails, OAuth tokens, AnyDesk IDs, passwords, or SSH keys in this repository. Use placeholders such as `<mac-lan-ip>`, `<mac-tailnet-ip>`, `<vps-host>`, and `<proxy-tailnet-host>`.

## Symptom Pattern

- AnyDesk reports a closed network state or is unreachable.
- Tailscale shows the Mac as offline from another node.
- OpenClaw Telegram or gateway checks may start failing because the Mac cannot reach external provider endpoints.
- The Mac may still be alive on the local network and reachable by LAN SSH.

When AnyDesk and Tailscale fail together, treat this as a host networking issue first.

## First Checks

From a known-good VPS or admin workstation:

```bash
tailscale status
tailscale ping --timeout=5s <mac-tailnet-ip>
ssh -o BatchMode=yes -o ConnectTimeout=8 <mac-ssh-alias> 'hostname'
```

From the LAN, if tailnet access is down:

```bash
ping <mac-lan-ip>
nc -vz -G 5 <mac-lan-ip> 22
ssh <mac-lan-ip>
```

Prefer the LAN Ethernet IP as the recovery channel if both Ethernet and Wi-Fi are configured. Avoid disabling the interface that carries your current SSH session.

## Diagnose Mac Networking

Run on the Mac:

```bash
networksetup -listnetworkserviceorder
scutil --dns
scutil --proxy
netstat -rn -f inet | sed -n '1,40p'
route -n get <public-ip-probe>
ping -c 2 <lan-gateway>
nc -vz -G 5 <public-ip-probe> 443
curl -4 --connect-timeout 5 --max-time 10 https://ifconfig.me
```

A `default` line in `netstat` is not enough. If `route -n get <public-ip-probe>` says `not in table`, or TCP fails with `Network is unreachable`, restore the global default route before touching AnyDesk or OpenClaw.

## Karing Safety Baseline

Karing can leave macOS with broken default routing when auto VPN/TUN routing is enabled on an unattended Mac. Do not uninstall Karing unless requested, but keep these unattended-host settings disabled:

- `auto_connect_after_launch=false`
- `auto_connect_at_boot=false`
- `proxy_all=false`
- `proxy.auto_set_system_proxy=false`
- `proxy.disconnect_when_quit=true`
- `tun.enable=false`
- `tun.auto_route=false`
- `tun.hijack_dns=false`
- Karing macOS network service disabled

Useful checks:

```bash
networksetup -listnetworkserviceorder | grep -A2 -B1 'Karing'
ps ax -o pid,command | grep -Ei 'Karing|karing|nebula' | grep -v grep
```

The Karing network service should show as disabled for unattended operation.

## Restore Basic Internet

If the Mac has LAN connectivity but no outbound route, restore Ethernet first:

```bash
networksetup -setnetworkserviceenabled "Karing (system)" off
networksetup -ordernetworkservices "Ethernet" "Wi-Fi" "Thunderbolt Bridge" "Karing (system)"
networksetup -setmanual "Ethernet" <mac-lan-ip> <lan-netmask> <lan-gateway>
networksetup -setdnsservers "Ethernet" <lan-dns> <public-dns-1> <public-dns-2>
```

If DHCP is preferred and reliable:

```bash
networksetup -setdhcp "Ethernet"
```

Then re-check:

```bash
route -n get <public-ip-probe>
nc -vz -G 5 <public-ip-probe> 443
curl -4 --connect-timeout 5 --max-time 10 https://ifconfig.me
```

## Restore Tailscale

```bash
tailscale set --exit-node= --exit-node-allow-lan-access=false
brew services restart tailscale
sleep 10
tailscale status
tailscale ping --timeout=5s <vps-tailnet-ip>
```

The Mac should appear online from another tailnet node, and SSH over `<mac-tailnet-ip>` should work.

## Restore AnyDesk

```bash
open -a AnyDesk
sleep 8
/Applications/AnyDesk.app/Contents/MacOS/AnyDesk --get-status
/Applications/AnyDesk.app/Contents/MacOS/AnyDesk --version
```

Expected status is `online`. Do not commit AnyDesk IDs or other account details.

## Restore OpenClaw

OpenClaw should use the OAuth-backed Codex provider, not the API-key-only OpenAI provider:

```bash
openclaw models status
```

Expected properties:

- default model is `openai-codex/gpt-5.5`
- `codex` alias points to `openai-codex/gpt-5.5`
- OAuth profile for `openai-codex` is present
- no `Missing API key` error for the selected production model

Run a gateway smoke test:

```bash
openclaw infer model run --gateway --json \
  --model openai-codex/gpt-5.5 \
  --prompt 'Reply exactly: OPENCLAW_GATEWAY_OK'
```

If direct provider calls return an HTML/Cloudflare page from the Mac's public route, route only OpenClaw provider traffic through a controlled proxy configured outside this repository. Store proxy hosts and credentials in local service configuration, not in Git.

## Final Validation

Before closing the incident:

```bash
tailscale status
tailscale ping --timeout=5s <vps-tailnet-ip>
/Applications/AnyDesk.app/Contents/MacOS/AnyDesk --get-status
openclaw infer model run --gateway --json --model openai-codex/gpt-5.5 --prompt 'Reply exactly: OK'
route -n get <public-ip-probe>
```

Record only sanitized outcomes in repository docs.
