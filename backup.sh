#!/usr/bin/env bash
set -euo pipefail

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

for service in database app; do
  if ! ./compose.sh exec -T "$service" true >/dev/null 2>&1; then
    echo "$service is not running; start the stack before backing up." >&2
    exit 1
  fi
done

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_dir="backups/$timestamp"
mkdir -p "$backup_dir"

./compose.sh exec -T database \
  pg_dump --clean --if-exists --no-owner -U hedgedoc hedgedoc |
  gzip >"$backup_dir/database.sql.gz"

./compose.sh exec -T app \
  tar -C /hedgedoc/public/uploads -czf - . >"$backup_dir/uploads.tar.gz"

cp .env "$backup_dir/config.env"
chmod 600 "$backup_dir/config.env"

echo "Backup written to $backup_dir"
echo "Keep it private: it contains the database and service secrets."
