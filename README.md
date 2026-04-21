# Mac mini + VPS Ops Pack

Operational scripts and notes used to stabilize:

- OpenClaw gateway and OAuth recovery on macOS (Mac mini)
- Tailscale/SSH reachability and watchdog setup
- CELERITY/Hysteria helper scripts for VPS-side user/bootstrap tasks

## Included files

- `celerity-bootstrap-admin.js`
- `celerity-bootstrap.mjs`
- `celerity-bootstrap.sh`
- `celerity-create-user.sh`
- `hysteria-config-fix.yaml`
- `link-vpn-user-node.js`
- `read-vpn-user.js`
- `openclaw-gateway-watchdog.service`
- `openclaw-gateway-watchdog.sh`
- `openclaw-gateway-watchdog.timer`
- `start_oauth_flow.sh`
- `fix_1_performance_reset.md`

## Notes

- Secrets are intentionally excluded.
- Verify paths/hosts before running in production.
- Prefer running scripts from a controlled shell with explicit PATH.
