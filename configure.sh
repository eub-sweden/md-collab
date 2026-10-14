#!/usr/bin/env bash
set -euo pipefail

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  echo "Usage: $0 [HOSTNAME-OR-IPV4[:PORT]]"
  echo "Creates .env without starting HedgeDoc."
  exit 0
fi

if [[ -e .env ]]; then
  echo "Refusing to replace existing .env; move it aside first." >&2
  exit 1
fi

public_endpoint=${1:-}
if [[ -z $public_endpoint ]] && command -v ip >/dev/null 2>&1; then
  public_endpoint=$(ip route get 1.1.1.1 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }' || true)
fi
if [[ -z $public_endpoint ]] && command -v hostname >/dev/null 2>&1; then
  public_endpoint=$(hostname -I 2>/dev/null | awk '{ print $1 }' || true)
fi
if [[ -z $public_endpoint ]]; then
  echo "Could not detect a LAN address. Run: $0 192.168.1.50:3000" >&2
  exit 1
fi
if [[ ! $public_endpoint =~ ^([A-Za-z0-9][A-Za-z0-9._-]*)(:([0-9]{1,5}))?$ ]]; then
  echo "Use HOSTNAME-OR-IPV4[:PORT] without a scheme, path, or spaces." >&2
  exit 1
fi
public_host=${BASH_REMATCH[1]}
public_port=${BASH_REMATCH[3]:-3000}
if (( 10#$public_port < 1 || 10#$public_port > 65535 )); then
  echo "Port must be between 1 and 65535." >&2
  exit 1
fi
public_port=$((10#$public_port))
if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate secrets." >&2
  exit 1
fi

umask 077
db_password=$(openssl rand -hex 32)
session_secret=$(openssl rand -hex 48)

cat >.env <<EOF
MD_EDIT_PUBLIC_HOST=$public_host
MD_EDIT_PORT=$public_port
MD_EDIT_DB_PASSWORD=$db_password
MD_EDIT_SESSION_SECRET=$session_secret
MD_EDIT_BIND_IP=0.0.0.0
MD_EDIT_ALLOW_ANONYMOUS=true
MD_EDIT_ALLOW_ANONYMOUS_EDITS=false
MD_EDIT_ALLOW_EMAIL_REGISTER=true
MD_EDIT_DEFAULT_PERMISSION=freely
EOF

echo "Created .env for http://$public_host:$public_port"
echo "Review it, then run ./start.sh"
