#!/usr/bin/env bash
set -euo pipefail

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [[ ! -f .env ]]; then
  echo "Missing .env. Run ./configure.sh [LAN-IP-OR-HOSTNAME] first." >&2
  exit 1
fi

ensure_service_started() {
  service=$1

  if ./compose.sh exec -T "$service" true >/dev/null 2>&1; then
    return
  fi

  ./compose.sh start "$service" >/dev/null 2>&1 || true
  if ./compose.sh exec -T "$service" true >/dev/null 2>&1; then
    return
  fi

  ./compose.sh up -d "$service"
}

./compose.sh config >/dev/null
ensure_service_started database

for attempt in {1..60}; do
  if ./compose.sh exec -T database \
    pg_isready -U hedgedoc -d hedgedoc >/dev/null 2>&1; then
    ensure_service_started app

    public_host=$(sed -n 's/^MD_EDIT_PUBLIC_HOST=//p' .env)
    echo "HedgeDoc is starting at http://$public_host:3000"
    echo "Follow startup with: ./logs.sh"
    exit 0
  fi
  sleep 1
done

echo "PostgreSQL did not become ready within 60 seconds." >&2
echo "Inspect it with: ./compose.sh logs database" >&2
exit 1
