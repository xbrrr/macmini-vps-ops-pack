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
- Do not disable, stop, or uninstall `Karing`; it is a required VPN client and Codex app connectivity depends on it.

## Structure

- `scripts/`: operational shell and helper scripts
- `systemd/`: service and timer units
- `docs/`: notes, release history, and security guidance
- `templates/`: sanitized config examples

## Validation

- Update `README.md` whenever entrypoints or environment variables change.
- Preserve compatibility for existing root-level script names when practical.
- Before finishing, review `git diff --stat` and `git status --short`.

