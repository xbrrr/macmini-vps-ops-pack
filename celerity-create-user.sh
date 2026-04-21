#!/usr/bin/env bash
set -euo pipefail
KEY="$(docker exec -w /app hysteria-backend node /app/bootstrap-admin.js 2>/dev/null | jq -r .apiKey)"
curl -fsS -X POST "https://91-132-142-33.nip.io/api/users" \
  -H "X-API-Key: ${KEY}" \
  -H "Content-Type: application/json" \
  -d '{"userId":"vpn1","username":"vpn1","enabled":true}'
echo
