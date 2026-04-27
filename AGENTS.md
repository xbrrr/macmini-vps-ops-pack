# AGENTS.md

## Repo Purpose

This repository stores operational scripts and notes for:

- Mac mini / OpenClaw recovery and watchdog flows
- VPS-side CELERITY and Hysteria bootstrap tasks
- OAuth recovery helpers and VPN user management

## Working Rules

- Treat this repo as infrastructure code: prefer safe defaults, explicit environment variables, and minimal secret exposure.
- Never commit live credentials, API keys, Mongo URIs, TLS private keys, OAuth artifacts, or rendered production configs.
- Prefer additive, low-disruption refactors because some scripts are used manually on live systems.
- Keep shell scripts POSIX-ish bash with `set -euo pipefail` and quote expansions.
- Prefer examples/templates over shipping live config values.
- Do not uninstall `Karing` unless explicitly requested. On a headless/remote Mac mini, keep Karing auto-connect, TUN, DNS hijack, and auto-route disabled unless a human intentionally enables them for an interactive session.
- If AnyDesk and Tailscale fail at the same time, diagnose normal outbound internet and the default route before restarting individual apps.

## Structure

- `scripts/`: operational shell and helper scripts
- `systemd/`: service and timer units
- `docs/`: notes, release history, and security guidance
- `templates/`: sanitized config examples

## Validation

- Update `README.md` whenever entrypoints or environment variables change.
- Preserve compatibility for existing root-level script names when practical.
- Before finishing, review `git diff --stat` and `git status --short`.

## Remote Mac Recovery Lessons

- Treat AnyDesk failure plus Tailscale offline as a host networking incident, not an AnyDesk-only incident.
- If tailnet SSH is unavailable but LAN access exists, use the LAN SSH path as the recovery channel and avoid changes that can drop the active interface.
- Verify the Mac has a global default route with `route -n get <public-ip-probe>`; a scoped route can appear in `netstat` while ordinary outbound TCP still fails with `Network is unreachable`.
- Verify DNS separately after restoring the route; working TCP to a public IP does not prove hostname resolution works.
- Keep Karing's macOS network service disabled for unattended operation. In Karing settings, keep auto-connect after launch, TUN, auto-route, DNS hijack, and proxy-all disabled.
- After network recovery, validate all three layers: Tailscale SSH, AnyDesk status, and OpenClaw gateway inference.

