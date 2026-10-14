#!/usr/bin/env bash
set -euo pipefail

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# Podman is preferred. `podman compose` delegates to an installed Compose
# provider such as podman-compose.
if command -v podman >/dev/null 2>&1; then
  if podman compose version >/dev/null 2>&1; then
    exec podman compose "$@"
  fi
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  exec docker compose "$@"
fi

echo "No usable Compose implementation found." >&2
echo "Install Podman Compose or Docker Compose." >&2
exit 1
