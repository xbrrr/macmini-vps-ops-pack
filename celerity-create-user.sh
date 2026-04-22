#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./scripts/lib/common.sh
source "${SCRIPT_DIR}/scripts/lib/common.sh"

require_command curl
require_command docker
require_command jq

require_env CELERITY_BACKEND_CONTAINER
require_env CELERITY_BOOTSTRAP_SCRIPT
require_env PANEL_HOST
require_env CELERITY_USER_ID
require_env CELERITY_USERNAME

BACKEND_CONTAINER="${CELERITY_BACKEND_CONTAINER}"
BOOTSTRAP_SCRIPT_NAME="${CELERITY_BOOTSTRAP_SCRIPT}"
PANEL_HOST="${PANEL_HOST}"
VPN_USER_ID="${CELERITY_USER_ID}"
VPN_USERNAME="${CELERITY_USERNAME}"

KEY="$(docker exec -w /app "$BACKEND_CONTAINER" node "/app/${BOOTSTRAP_SCRIPT_NAME}" 2>/dev/null | jq -r .apiKey)"
[[ -n "$KEY" && "$KEY" != "null" ]] || die "Unable to derive API key from bootstrap script output"
USER_JSON="$(jq -n \
  --arg userId "$VPN_USER_ID" \
  --arg username "$VPN_USERNAME" \
  '{userId:$userId, username:$username, enabled:true}')"

curl -fsS -X POST "https://${PANEL_HOST}/api/users" \
  -H "X-API-Key: ${KEY}" \
  -H "Content-Type: application/json" \
  -d "$USER_JSON"
echo
