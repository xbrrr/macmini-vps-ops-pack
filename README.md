# Mac mini + VPS Ops Pack

Operational scripts and notes used to stabilize:

- OpenClaw gateway and OAuth recovery on macOS (Mac mini)
- AnyDesk recovery on macOS (Mac mini)
- Tailscale and SSH reachability with watchdog automation
- CELERITY and Hysteria bootstrap flows for VPS-side setup

## Codex-ready usage

This repository is now safer to operate from Codex:

- runtime-specific values are provided by environment variables
- secrets stay out of the repository
- host, user, node, and container values can be overridden without editing source
- agent-facing guidance lives in `AGENTS.md`
- sanitized examples and security notes are separated from live operations

Copy `.env.example` into your runtime environment or export only the variables you need.

## Repository layout

- `AGENTS.md`: working rules for Codex and other agents
- `docs/`: security notes and operational history
- `docs/ANYDESK_RECOVERY.md`: runbook for recurring `AnyNet closed` failures on macOS
- `docs/REMOTE_MAC_OPENCLAW_RECOVERY.md`: sanitized runbook for combined Mac networking, Tailscale, AnyDesk, Karing, and OpenClaw recovery
- `scripts/lib/common.sh`: shared bash safety helpers
- `templates/`: sanitized config examples for rendered runtime files

## Key configuration

- `PANEL_HOST`: panel host used by the shell bootstrap scripts
- `PUBLIC_IP`: public IP for the Hysteria node
- `CELERITY_PANEL_DIR`: panel checkout directory on the VPS
- `CELERITY_BACKEND_CONTAINER`: backend container name
- `CELERITY_SSH_KEY_PATH`: SSH key used for node bootstrap
- `CELERITY_USER_ID`: VPN user identifier
- `CELERITY_USERNAME`: panel username for that VPN user
- `CELERITY_NODE_ID`: optional explicit node id for linking scripts
- `MONGO_URI`: required by the Node helper scripts

## Files

- `celerity-bootstrap-admin.js`: CommonJS bootstrap helper for admin and API key creation
- `celerity-bootstrap.mjs`: ESM-compatible variant of the same bootstrap helper
- `celerity-bootstrap.sh`: end-to-end panel bootstrap flow using env-based configuration and protected temp files
- `celerity-create-user.sh`: create a VPN user through the panel API
- `link-vpn-user-node.js`: attach a user to a node with env-configured ids
- `read-vpn-user.js`: inspect an existing VPN user via `MONGO_URI`, hiding stored password fields by default
- `openclaw-gateway-watchdog.service`: systemd unit for the watchdog
- `openclaw-gateway-watchdog.sh`: health check and restart logic
- `openclaw-gateway-watchdog.timer`: schedule for the watchdog
- `start_oauth_flow.sh`: recover or initiate the OpenAI Codex OAuth login flow
- `scripts/anydesk-mac-recover.sh`: restart and diagnose AnyDesk on macOS when `AnyNet closed` appears
- `templates/hysteria-config-fix.example.yaml`: sanitized config fragment for Hysteria fixes
- `fix_1_performance_reset.md`: documented rollback note for a Windows performance change
- `RELEASE_NOTES.md`: stabilization history

## Notes

- Secrets are intentionally excluded.
- Verify paths, container names, hosts, and rendered config secrets before running in production.
- Prefer controlled shells with explicit `PATH` and exported env vars.
- `celerity-bootstrap.sh` now writes sensitive bootstrap output to a protected temporary file instead of printing secrets directly.
