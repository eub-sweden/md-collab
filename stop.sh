#!/usr/bin/env bash
set -euo pipefail

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
./compose.sh down
echo "Stopped HedgeDoc. Database and uploads were preserved."
