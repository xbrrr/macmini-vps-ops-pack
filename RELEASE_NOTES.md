# Release Notes

## 2026-04-21 - Mac mini / VPS stabilization pack

### Added
- Operational toolkit repository with scripts for OpenClaw, CELERITY, Hysteria, and VPN user management.
- SSH alias and workflow support for Mac mini maintenance from Windows.
- Gateway watchdog artifacts for OpenClaw (`.service`, `.timer`, `.sh`).
- AnyDesk recovery helper and runbook for recurring `AnyNet closed` failures on the Mac mini.

### Infrastructure fixes completed
- Restored stable SSH access to Mac mini through Tailscale and verified remote reachability.
- Migrated Mac mini Tailscale identity to a new active node (`mac-mini-mike-1`) and updated working access path.
- Validated post-reboot recovery path: node becomes reachable by `tailscale ping` and SSH.
- Re-established OpenClaw gateway service on macOS LaunchAgent and confirmed Telegram channel health.

### OAuth / model access
- Recovered OpenAI Codex OAuth flow and validated authenticated model availability in OpenClaw.
- Captured known caveat: token refresh race can occur with reused refresh token sessions.

### Notes
- Current active Mac mini node: `mac-mini-mike-1` (`100.82.112.95`).
- Legacy offline node entries should be removed from Tailscale admin to avoid confusion.
- Telegram privacy mode warning remains a policy choice (`requireMention=false`), not a runtime failure.
