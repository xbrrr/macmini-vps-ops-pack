#!/usr/bin/env bash
set -euo pipefail

BACKEND_CONTAINER="${CELERITY_BACKEND_CONTAINER:-hysteria-backend}"
BOOTSTRAP_SCRIPT_NAME="${CELERITY_BOOTSTRAP_SCRIPT:-bootstrap-admin.js}"
PANEL_HOST="${PANEL_HOST:-91-132-142-33.nip.io}"
VPN_USER_ID="${CELERITY_USER_ID:-vpn1}"
VPN_USERNAME="${CELERITY_USERNAME:-vpn1}"

KEY="$(docker exec -w /app "$BACKEND_CONTAINER" node "/app/${BOOTSTRAP_SCRIPT_NAME}" 2>/dev/null | jq -r .apiKey)"
USER_JSON="$(jq -n \
  --arg userId "$VPN_USER_ID" \
  --arg username "$VPN_USERNAME" \
  '{userId:$userId, username:$username, enabled:true}')"

curl -fsS -X POST "https://${PANEL_HOST}/api/users" \
  -H "X-API-Key: ${KEY}" \
  -H "Content-Type: application/json" \
  -d "$USER_JSON"
echo
