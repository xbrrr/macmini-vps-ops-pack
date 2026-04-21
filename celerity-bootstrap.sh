#!/usr/bin/env bash
set -euo pipefail
cd /opt/celerity-panel

PANEL_HOST="${PANEL_HOST:-91-132-142-33.nip.io}"
PUBLIC_IP="${PUBLIC_IP:-91.132.142.33}"

# --- SSH key for panel -> host (same VPS) ---
if [[ ! -f /root/.ssh/celerity_autosetup ]]; then
  ssh-keygen -t ed25519 -f /root/.ssh/celerity_autosetup -N "" -q
fi
if ! grep -qF "celerity_autosetup" /root/.ssh/authorized_keys 2>/dev/null; then
  cat /root/.ssh/celerity_autosetup.pub >> /root/.ssh/authorized_keys
fi

# --- Admin + API key inside backend container ---
docker cp /opt/celerity-panel/bootstrap-admin.js hysteria-backend:/app/bootstrap-admin.js
BOOT_JSON="$(docker exec -w /app hysteria-backend node /app/bootstrap-admin.js 2>/tmp/celerity-bootstrap-node.err)"
BOOT_JSON="$(echo "$BOOT_JSON" | grep '^{' | tail -1)"

API_KEY="$(echo "$BOOT_JSON" | jq -r '.apiKey')"
ADMIN_PASS="$(echo "$BOOT_JSON" | jq -r '.adminPassword')"

if [[ -z "$API_KEY" || "$API_KEY" == "null" ]]; then
  echo "No API key in bootstrap output: $BOOT_JSON" >&2
  exit 1
fi

# If admin existed, ADMIN_PASS may be empty — user logs in with existing password
echo "[bootstrap] paneladmin password (only if just created): ${ADMIN_PASS:-'(existing admin)'}"
echo "[bootstrap] API key (save once): $API_KEY"

PRIVKEY="$(cat /root/.ssh/celerity_autosetup)"
NODE_JSON="$(jq -n \
  --arg name "HY2-${PUBLIC_IP}" \
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

# Create VPN user
USER_JSON='{"userId":"vpn1","username":"vpn1","enabled":true}'
set +e
curl -fsS -X POST "https://${PANEL_HOST}/api/users" \
  -H "X-API-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$USER_JSON" | tee /tmp/user-create.json
set -e

TOKEN="$(jq -r '.subscriptionToken // empty' /tmp/user-create.json 2>/dev/null || true)"
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(curl -fsS "https://${PANEL_HOST}/api/users/vpn1" -H "X-API-Key: ${API_KEY}" | jq -r '.subscriptionToken')"
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
