# AnyDesk Recovery on Mac mini

This runbook is for the recurring case where AnyDesk shows `AnyNet closed` and the Mac mini becomes unreachable through the normal remote-control path.

## What `AnyNet closed` usually means

In practice, this error is most often one of these:

- the AnyDesk frontend process is stuck
- the macOS LaunchAgent did not recover after sleep, reboot, or network change
- AnyDesk local state became unhealthy
- outbound connectivity changed and the app did not reconnect cleanly

## Fast recovery

Run on the Mac mini over SSH:

```bash
cd /path/to/macmini-vps-ops-pack
./scripts/anydesk-mac-recover.sh
```

What it does:

- prints a before/after status snapshot
- restarts AnyDesk processes
- attempts a LaunchAgent kickstart for the user session
- relaunches the app

## Escalated recovery

If the fast restart does not help, retry once with a backup of local AnyDesk state:

```bash
RESET_NETWORK_CACHE=1 ./scripts/anydesk-mac-recover.sh
```

That moves `~/Library/Application Support/AnyDesk` aside into a timestamped backup before restart.

## Manual checks

- Confirm the Mac mini still has outbound internet.
- Confirm the AnyDesk app is present in `/Applications/AnyDesk.app`.
- Confirm the logged-in GUI user session exists; AnyDesk on macOS is more reliable with an active user session than in a fully headless logged-out state.
- If the host recently changed network path, disable and re-enable AnyDesk network access in macOS firewall or reboot the box once if SSH access is healthy.
- If the machine was asleep, wake handling may be the actual trigger; prefer disabling deep sleep for this host if remote reachability matters more than power savings.

## Suggested follow-up hardening

- Add a LaunchAgent or periodic SSH check that relaunches AnyDesk when its process disappears.
- Keep a secondary remote path alive: Tailscale + SSH should remain the recovery path even when AnyDesk is broken.
- Avoid storing AnyDesk production state in the repo; only store runbooks and helpers.
