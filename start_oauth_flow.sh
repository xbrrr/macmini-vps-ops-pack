#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./scripts/lib/common.sh
source "${SCRIPT_DIR}/scripts/lib/common.sh"

require_command mkfifo
require_command nohup
require_command pkill
require_command python3
require_command script

export PATH=/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
TMP_DIR="$(make_temp_dir)"
FIFO_PATH="${TMP_DIR}/oc_oauth_in"
LOG_PATH="${TMP_DIR}/oc_oauth.log"
NOHUP_LOG_PATH="${TMP_DIR}/oc_oauth_nohup.log"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

pkill -f "openclaw models auth login --provider openai-codex" 2>/dev/null || true
mkfifo "${FIFO_PATH}"
nohup script -q "${LOG_PATH}" -c "cat ${FIFO_PATH} | /opt/homebrew/bin/openclaw models auth login --provider openai-codex" >"${NOHUP_LOG_PATH}" 2>&1 &
sleep 2
OAUTH_LOG_PATH="${LOG_PATH}" python3 - <<'PY'
import time,re,pathlib
p=pathlib.Path(__import__('os').environ['OAUTH_LOG_PATH'])
url=''
for _ in range(60):
    if p.exists():
        s=p.read_text(errors='ignore')
        m=re.search(r'https://auth\.openai\.com/oauth/authorize\?[^\s]+', s)
        if m:
            url=m.group(0); break
    time.sleep(1)
print(url if url else 'NO_URL')
PY
