#!/usr/bin/env bash
set -euo pipefail

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  echo "Usage: $0 [LAN-IP-OR-HOSTNAME]"
  echo "Creates .env without starting HedgeDoc."
  exit 0
fi

if [[ -e .env ]]; then
  echo "Refusing to replace existing .env; move it aside first." >&2
  exit 1
fi

public_host=${1:-}
if [[ -z $public_host ]] && command -v ip >/dev/null 2>&1; then
  public_host=$(ip route get 1.1.1.1 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }' || true)
fi
if [[ -z $public_host ]] && command -v hostname >/dev/null 2>&1; then
  public_host=$(hostname -I 2>/dev/null | awk '{ print $1 }' || true)
fi
if [[ -z $public_host ]]; then
  echo "Could not detect a LAN address. Run: $0 192.168.1.50" >&2
  exit 1
fi
if [[ $public_host == *://* || $public_host == */* || $public_host == *:* ]]; then
  echo "Use a hostname or IPv4 address without a scheme, path, or port." >&2
  exit 1
fi
if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate secrets." >&2
  exit 1
fi

umask 077
db_password=$(openssl rand -hex 32)
session_secret=$(openssl rand -hex 48)

cat >.env <<EOF
MD_EDIT_PUBLIC_HOST=$public_host
MD_EDIT_DB_PASSWORD=$db_password
MD_EDIT_SESSION_SECRET=$session_secret
MD_EDIT_BIND_IP=0.0.0.0
MD_EDIT_ALLOW_ANONYMOUS=true
MD_EDIT_ALLOW_ANONYMOUS_EDITS=false
MD_EDIT_ALLOW_EMAIL_REGISTER=true
MD_EDIT_DEFAULT_PERMISSION=freely
EOF

echo "Created .env for http://$public_host:3000"
echo "Review it, then run ./start.sh"
