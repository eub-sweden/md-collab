#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
state_root=${MD_EDIT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/md-edit}
sessions_dir=$state_root/sessions

usage() {
  cat >&2 <<EOF
Usage:
  $0 list
  $0 save SESSION_ID [DESTINATION]
  $0 original SESSION_ID [DESTINATION]

"save" downloads the current HedgeDoc Markdown. When writing to the recorded
source file, it refuses to overwrite independent local changes.

"original" copies the untouched pre-HedgeDoc file. Without DESTINATION, it
prints the protected copy's path and does not copy anything.
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage
action=$1

if [[ $action == list ]]; then
  [[ $# -eq 1 ]] || usage
  if [[ ! -d $sessions_dir ]]; then
    echo "No sessions found under $sessions_dir"
    exit 0
  fi
  found=false
  for session_dir in "$sessions_dir"/*; do
    [[ -d $session_dir ]] || continue
    found=true
    session_id=${session_dir##*/}
    source_path=$(sed -n '1p' "$session_dir/source-path" 2>/dev/null || true)
    note_url=$(sed -n '1p' "$session_dir/note-url" 2>/dev/null || true)
    printf '%s\t%s\t%s\n' "$session_id" "$source_path" "$note_url"
  done
  if [[ $found == false ]]; then
    echo "No sessions found under $sessions_dir"
  fi
  exit 0
fi

[[ $action == save || $action == original ]] || usage
[[ $# -ge 2 && $# -le 3 ]] || usage

session_id=$2
[[ $session_id != */* && $session_id != *$'\n'* ]] || {
  echo "Invalid session ID: $session_id" >&2
  exit 1
}
session_dir=$sessions_dir/$session_id
[[ -d $session_dir ]] || {
  echo "Unknown session: $session_id" >&2
  echo "List sessions with: $0 list" >&2
  exit 1
}

source_path=$(sed -n '1p' "$session_dir/source-path")
original_path=$session_dir/original.md
[[ -f $original_path ]] || {
  echo "Protected original is missing: $original_path" >&2
  exit 1
}

if [[ $action == original ]]; then
  if [[ $# -eq 2 ]]; then
    echo "$original_path"
    exit 0
  fi
  destination=$3
  if [[ -e $destination ]]; then
    echo "Refusing to overwrite existing destination: $destination" >&2
    exit 1
  fi
  cp -p -- "$original_path" "$destination"
  echo "Copied protected original to: $destination"
  exit 0
fi

command -v curl >/dev/null 2>&1 || {
  echo "curl is required." >&2
  exit 1
}
command -v sha256sum >/dev/null 2>&1 || {
  echo "sha256sum is required." >&2
  exit 1
}

destination=${3:-$source_path}
server_url=$(sed -n '1p' "$session_dir/server-url")
note_id=$(sed -n '1p' "$session_dir/note-id")
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
export_path=$session_dir/export-$timestamp.md

if ! curl --fail --silent --show-error \
  --cookie "$session_dir/cookies.txt" \
  --output "$export_path" \
  "$server_url/$note_id/download"; then
  rm -f -- "$export_path"
  echo "Could not download note $note_id from $server_url" >&2
  exit 1
fi

if [[ $destination == "$source_path" && -e $destination ]]; then
  current_hash=$(sha256sum "$destination" | awk '{ print $1 }')
  if [[ -f $session_dir/last-saved.sha256 ]]; then
    expected_hash=$(sed -n '1p' "$session_dir/last-saved.sha256")
  else
    expected_hash=$(sed -n '1p' "$session_dir/original.sha256")
  fi
  if [[ $current_hash != "$expected_hash" ]]; then
    echo "Refusing to overwrite a locally modified source file:" >&2
    echo "  $destination" >&2
    echo "The downloaded HedgeDoc version is preserved at:" >&2
    echo "  $export_path" >&2
    exit 1
  fi
elif [[ -e $destination ]]; then
  echo "Refusing to overwrite existing destination: $destination" >&2
  echo "Downloaded version retained at: $export_path" >&2
  exit 1
fi

destination_dir=$(dirname -- "$destination")
destination_name=$(basename -- "$destination")
[[ -d $destination_dir && -w $destination_dir ]] || {
  echo "Destination directory is not writable: $destination_dir" >&2
  echo "Downloaded version retained at: $export_path" >&2
  exit 1
}

temporary_path=$(mktemp "$destination_dir/.$destination_name.hedgedoc.XXXXXX")
cleanup() {
  rm -f -- "$temporary_path"
}
trap cleanup EXIT
cp -- "$export_path" "$temporary_path"
if [[ -e $destination ]]; then
  chmod --reference="$destination" "$temporary_path"
fi
mv -- "$temporary_path" "$destination"
trap - EXIT

sha256sum "$destination" | awk '{ print $1 }' >"$session_dir/last-saved.sha256"
date -u +%Y-%m-%dT%H:%M:%SZ >"$session_dir/last-saved-at"

echo "Saved HedgeDoc note $note_id to: $destination"
echo "Export snapshot retained at: $export_path"
