# Fix #1 - Performance Reset Baseline

Date: 2026-04-15

## Applied changes

- Switched active Windows power plan to `Balanced`:
  - GUID: `381b4222-f694-41f0-9685-ff5bb260df2e`

## Left unchanged on purpose

- RAM is already at 6000 MT/s (EXPO/XMP effectively active).
- HAGS remains OFF (`HwSchMode = 1`).
- MPO remains disabled (`OverlayTestMode = 5`).
- GameDVR remains disabled.
- Ethernet adapter low-latency settings remain as currently tuned.

## Rollback (if you ask to rollback fix #1)

Run:

`powercfg /S d6dc1319-c076-4fcc-b8be-a7187a370390`

That restores your previous `Maximum Performance` power plan.

