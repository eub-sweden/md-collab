#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir"

if [[ $# -ne 1 || ${1:-} == -h || ${1:-} == --help ]]; then
  echo "Usage: $0 HOSTNAME-OR-IPV4[:PORT]" >&2
  exit 2
fi

requested_endpoint=$1
if [[ ! $requested_endpoint =~ ^([A-Za-z0-9][A-Za-z0-9._-]*)(:([0-9]{1,5}))?$ ]]; then
  echo "Use HOSTNAME-OR-IPV4[:PORT] without a scheme, path, or spaces." >&2
  exit 1
fi
requested_host=${BASH_REMATCH[1]}
requested_port=${BASH_REMATCH[3]:-3000}
if (( 10#$requested_port < 1 || 10#$requested_port > 65535 )); then
  echo "Port must be between 1 and 65535." >&2
  exit 1
fi
requested_port=$((10#$requested_port))

if [[ ! -e .env ]]; then
  exec ./configure.sh "$requested_host:$requested_port"
fi

current_host=$(sed -n 's/^MD_EDIT_PUBLIC_HOST=//p' .env)
current_port=$(sed -n 's/^MD_EDIT_PORT=//p' .env)
current_port=${current_port:-3000}
if [[ $current_host == "$requested_host" && $current_port == "$requested_port" ]]; then
  exit 0
fi

cat >&2 <<EOF
WARNING: changing HedgeDoc's public origin

  current:   http://$current_host:$current_port
  requested: http://$requested_host:$requested_port

This stops and recreates the Compose stack. Active editing connections will be
interrupted, and old URLs may not render correctly under the previous hostname.
PostgreSQL, uploads, protected originals, and exported snapshots are preserved.
EOF

if [[ -t 0 ]]; then
  printf 'Continue? [y/N] ' >&2
  IFS= read -r answer || answer=
elif exec 3<>/dev/tty 2>/dev/null; then
  printf 'Continue? [y/N] ' >&3
  IFS= read -r answer <&3 || answer=
  exec 3>&-
else
  echo "Cannot ask for confirmation without an interactive terminal." >&2
  exit 1
fi
case $answer in
  y | Y | yes | YES | Yes) ;;
  *)
    echo "Host change cancelled." >&2
    exit 1
    ;;
esac

umask 077
temporary_env=$(mktemp ./.env.XXXXXX)
cleanup() {
  rm -f -- "$temporary_env"
}
trap cleanup EXIT

awk -v host="$requested_host" -v port="$requested_port" '
  BEGIN { host_replaced = 0; port_replaced = 0 }
  /^MD_EDIT_PUBLIC_HOST=/ {
    print "MD_EDIT_PUBLIC_HOST=" host
    host_replaced = 1
    next
  }
  /^MD_EDIT_PORT=/ {
    print "MD_EDIT_PORT=" port
    port_replaced = 1
    next
  }
  { print }
  END {
    if (!host_replaced) print "MD_EDIT_PUBLIC_HOST=" host
    if (!port_replaced) print "MD_EDIT_PORT=" port
  }
' .env >"$temporary_env"
chmod --reference=.env "$temporary_env"
mv -- "$temporary_env" .env
trap - EXIT

echo "Public origin changed to http://$requested_host:$requested_port."
echo "Stopping the old-origin containers; persistent data is preserved."
./compose.sh down
