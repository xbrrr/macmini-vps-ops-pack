#!/usr/bin/env bash
set -euo pipefail

PANEL_DIR="${CELERITY_PANEL_DIR:-/opt/celerity-panel}"
PANEL_HOST="${PANEL_HOST:-91-132-142-33.nip.io}"
PUBLIC_IP="${PUBLIC_IP:-91.132.142.33}"
BACKEND_CONTAINER="${CELERITY_BACKEND_CONTAINER:-hysteria-backend}"
BOOTSTRAP_SCRIPT_NAME="${CELERITY_BOOTSTRAP_SCRIPT:-bootstrap-admin.js}"
SSH_KEY_PATH="${CELERITY_SSH_KEY_PATH:-/root/.ssh/celerity_autosetup}"
VPN_USER_ID="${CELERITY_USER_ID:-vpn1}"
VPN_USERNAME="${CELERITY_USERNAME:-vpn1}"
NODE_NAME="${CELERITY_NODE_NAME:-HY2-${PUBLIC_IP}}"

cd "$PANEL_DIR"

if [[ ! -f celerity-bootstrap-admin.js ]]; then
  echo "Expected celerity-bootstrap-admin.js in ${PANEL_DIR}" >&2
  exit 1
fi

# --- SSH key for panel -> host (same VPS) ---
if [[ ! -f "$SSH_KEY_PATH" ]]; then
  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -q
fi
if ! grep -qF "$SSH_KEY_PATH" /root/.ssh/authorized_keys 2>/dev/null; then
  cat "${SSH_KEY_PATH}.pub" >> /root/.ssh/authorized_keys
fi

# --- Admin + API key inside backend container ---
docker cp "${PANEL_DIR}/celerity-bootstrap-admin.js" "${BACKEND_CONTAINER}:/app/${BOOTSTRAP_SCRIPT_NAME}"
BOOT_JSON="$(docker exec -w /app "$BACKEND_CONTAINER" node "/app/${BOOTSTRAP_SCRIPT_NAME}" 2>/tmp/celerity-bootstrap-node.err)"
BOOT_JSON="$(echo "$BOOT_JSON" | grep '^{' | tail -1)"

API_KEY="$(echo "$BOOT_JSON" | jq -r '.apiKey')"
ADMIN_PASS="$(echo "$BOOT_JSON" | jq -r '.adminPassword')"

if [[ -z "$API_KEY" || "$API_KEY" == "null" ]]; then
  echo "No API key in bootstrap output: $BOOT_JSON" >&2
  exit 1
fi

echo "[bootstrap] paneladmin password (only if just created): ${ADMIN_PASS:-'(existing admin)'}"
echo "[bootstrap] API key (save once): $API_KEY"

PRIVKEY="$(cat "$SSH_KEY_PATH")"
NODE_JSON="$(jq -n \
  --arg name "$NODE_NAME" \
  --arg ip "$PUBLIC_IP" \
  --arg domain "$PANEL_HOST" \
  --arg pk "$PRIVKEY" \
  '{name:$name, ip:$ip, domain:$domain, type:"hysteria", port:443, portRange:"20000-50000", ssh:{username:"root", port:22, privateKey:$pk}}')"

set +e
CREATE_RES="$(curl -fsS -X POST "https://${PANEL_HOST}/api/nodes" \
  -H "X-API-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$NODE_JSON" 2>&1)"
CURL_EC=$?
set -e

NODE_ID=""
if [[ "$CURL_EC" -eq 0 ]]; then
  NODE_ID="$(echo "$CREATE_RES" | jq -r '._id // .id // empty')"
else
  echo "$CREATE_RES" >&2
fi
if [[ -z "$NODE_ID" || "$NODE_ID" == "null" ]]; then
  NODE_ID="$(curl -fsS "https://${PANEL_HOST}/api/nodes" -H "X-API-Key: ${API_KEY}" | jq -r --arg ip "$PUBLIC_IP" '.[] | select(.ip==$ip) | ._id' | head -1)"
fi
if [[ -z "$NODE_ID" || "$NODE_ID" == "null" ]]; then
  echo "Could not determine node id. Last create response: $CREATE_RES" >&2
  exit 1
fi
echo "[bootstrap] Node id: $NODE_ID"

SETUP_RES="$(curl -fsS -X POST "https://${PANEL_HOST}/api/nodes/${NODE_ID}/setup" \
  -H "X-API-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"installHysteria":true,"setupPortHopping":true,"restartService":true}')" || true
echo "$SETUP_RES" | jq . 2>/dev/null || echo "$SETUP_RES"

USER_JSON="$(jq -n \
  --arg userId "$VPN_USER_ID" \
  --arg username "$VPN_USERNAME" \
  '{userId:$userId, username:$username, enabled:true}')"
set +e
curl -fsS -X POST "https://${PANEL_HOST}/api/users" \
  -H "X-API-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$USER_JSON" | tee /tmp/user-create.json
set -e

TOKEN="$(jq -r '.subscriptionToken // empty' /tmp/user-create.json 2>/dev/null || true)"
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(curl -fsS "https://${PANEL_HOST}/api/users/${VPN_USER_ID}" -H "X-API-Key: ${API_KEY}" | jq -r '.subscriptionToken')"
fi

echo ""
echo "========== COPY BELOW =========="
echo "Panel:     https://${PANEL_HOST}/panel"
echo "Login:     paneladmin  (password printed above if newly created)"
echo "Subscribe (URI list): https://${PANEL_HOST}/api/files/${TOKEN}?format=uri"
echo "Sing-box JSON:        https://${PANEL_HOST}/api/files/${TOKEN}?format=singbox"
echo "Clash YAML:           https://${PANEL_HOST}/api/files/${TOKEN}?format=clash"
echo "API key:   ${API_KEY}"
echo "================================"
