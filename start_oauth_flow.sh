#!/usr/bin/env bash
set -euo pipefail
export PATH=/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
pkill -f "openclaw models auth login --provider openai-codex" 2>/dev/null || true
rm -f /tmp/oc_oauth_in /tmp/oc_oauth.log /tmp/oc_oauth_nohup.log
mkfifo /tmp/oc_oauth_in
nohup script -q /tmp/oc_oauth.log -c "cat /tmp/oc_oauth_in | /opt/homebrew/bin/openclaw models auth login --provider openai-codex" >/tmp/oc_oauth_nohup.log 2>&1 &
sleep 2
python3 - <<'PY'
import time,re,pathlib
p=pathlib.Path('/tmp/oc_oauth.log')
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
