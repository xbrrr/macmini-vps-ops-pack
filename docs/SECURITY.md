# Security Notes

## Principles

- Keep secrets in runtime environment variables or secret stores, not in tracked files.
- Use sanitized examples for Hysteria, OAuth, and panel bootstrap configuration.
- Avoid printing API keys, admin passwords, Mongo credentials, or subscription tokens to shared terminals unless explicitly requested.

## Operational Guidance

- Export only the variables needed for the current task.
- Prefer temporary files created with restrictive permissions and clean them up after use.
- Review tracked config files for embedded IPs, tokens, and hostnames before every commit.

## Sensitive Outputs

The bootstrap and inspection scripts now default to safer output:

- `celerity-bootstrap.sh` writes sensitive bootstrap output to a protected local file instead of echoing secrets to stdout.
- `read-vpn-user.js` omits stored password data unless `CELERITY_SHOW_PASSWORD=1` is set intentionally.

## Follow-up

- If you need live production configs, render them outside the repository or keep them in ignored files such as `*.local.yaml`.
