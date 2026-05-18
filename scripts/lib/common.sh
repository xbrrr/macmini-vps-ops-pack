#!/usr/bin/env bash
set -euo pipefail

umask 077

log() {
  printf '[%s] %s\n' "${1}" "${2}" >&2
}

die() {
  log "error" "$1"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || die "Required environment variable is not set: ${name}"
}

make_temp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/ops-pack.XXXXXX"
}
