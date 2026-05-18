#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./scripts/lib/common.sh
source "${SCRIPT_DIR}/scripts/lib/common.sh"

require_command curl
require_command docker
require_command jq
require_command ssh-keygen

require_env CELERITY_PANEL_DIR
require_env PANEL_HOST
require_env PUBLIC_IP
require_env CELERITY_BACKEND_CONTAINER
require_env CELERITY_BOOTSTRAP_SCRIPT
require_env CELERITY_SSH_KEY_PATH
require_env CELERITY_USER_ID
require_env CELERITY_USERNAME

PANEL_DIR="${CELERITY_PANEL_DIR}"
PANEL_HOST="${PANEL_HOST}"
PUBLIC_IP="${PUBLIC_IP}"
BACKEND_CONTAINER="${CELERITY_BACKEND_CONTAINER}"
BOOTSTRAP_SCRIPT_NAME="${CELERITY_BOOTSTRAP_SCRIPT}"
SSH_KEY_PATH="${CELERITY_SSH_KEY_PATH}"
VPN_USER_ID="${CELERITY_USER_ID}"
VPN_USERNAME="${CELERITY_USERNAME}"
NODE_NAME="${CELERITY_NODE_NAME:-HY2-${PUBLIC_IP}}"
TMP_DIR="$(make_temp_dir)"
BOOT_ERR_FILE="${TMP_DIR}/bootstrap-node.err"
USER_CREATE_FILE="${TMP_DIR}/user-create.json"
SECRETS_FILE="${TMP_DIR}/bootstrap-secrets.txt"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

cd "$PANEL_DIR"

if [[ ! -f celerity-bootstrap-admin.js ]]; then
  die "Expected celerity-bootstrap-admin.js in ${PANEL_DIR}"
fi

# --- SSH key for panel -> host (same VPS) ---
if [[ ! -f "$SSH_KEY_PATH" ]]; then
  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -q
fi
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
if ! grep -qF "$(cat "${SSH_KEY_PATH}.pub")" /root/.ssh/authorized_keys 2>/dev/null; then
  cat "${SSH_KEY_PATH}.pub" >> /root/.ssh/authorized_keys
fi

# --- Admin + API key inside backend container ---
docker cp "${PANEL_DIR}/celerity-bootstrap-admin.js" "${BACKEND_CONTAINER}:/app/${BOOTSTRAP_SCRIPT_NAME}"
BOOT_JSON="$(docker exec -w /app "$BACKEND_CONTAINER" node "/app/${BOOTSTRAP_SCRIPT_NAME}" 2>"${BOOT_ERR_FILE}")"
BOOT_JSON="$(echo "$BOOT_JSON" | grep '^{' | tail -1)"

API_KEY="$(echo "$BOOT_JSON" | jq -r '.apiKey')"
ADMIN_PASS="$(echo "$BOOT_JSON" | jq -r '.adminPassword')"

if [[ -z "$API_KEY" || "$API_KEY" == "null" ]]; then
  die "No API key in bootstrap output: $BOOT_JSON"
fi

{
  echo "panel_url=https://${PANEL_HOST}/panel"
  echo "panel_user=paneladmin"
  echo "admin_password=${ADMIN_PASS:-}"
  echo "api_key=${API_KEY}"
} > "${SECRETS_FILE}"
chmod 600 "${SECRETS_FILE}"
log "bootstrap" "Sensitive bootstrap data saved to ${SECRETS_FILE}"

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
  die "Could not determine node id. Last create response: $CREATE_RES"
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
  -d "$USER_JSON" | tee "${USER_CREATE_FILE}"
set -e

TOKEN="$(jq -r '.subscriptionToken // empty' "${USER_CREATE_FILE}" 2>/dev/null || true)"
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(curl -fsS "https://${PANEL_HOST}/api/users/${VPN_USER_ID}" -H "X-API-Key: ${API_KEY}" | jq -r '.subscriptionToken')"
fi

echo ""
echo "========== COPY BELOW =========="
echo "Panel:     https://${PANEL_HOST}/panel"
echo "Login:     paneladmin  (password saved in ${SECRETS_FILE} if newly created)"
echo "Subscribe (URI list): https://${PANEL_HOST}/api/files/${TOKEN}?format=uri"
echo "Sing-box JSON:        https://${PANEL_HOST}/api/files/${TOKEN}?format=singbox"
echo "Clash YAML:           https://${PANEL_HOST}/api/files/${TOKEN}?format=clash"
echo "API key:   saved in ${SECRETS_FILE}"
echo "================================"
