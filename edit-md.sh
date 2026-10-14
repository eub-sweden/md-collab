#!/usr/bin/env bash
set -euo pipefail

caller_dir=$PWD
script_path=$(realpath -- "${BASH_SOURCE[0]}")
script_dir=$(CDPATH= cd -- "$(dirname -- "$script_path")" && pwd)

usage() {
  echo "Usage: $0 MARKDOWN_FILE [PUBLIC_HOST[:PORT]]" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
command -v curl >/dev/null 2>&1 || {
  echo "curl is required." >&2
  exit 1
}
command -v sha256sum >/dev/null 2>&1 || {
  echo "sha256sum is required." >&2
  exit 1
}
command -v realpath >/dev/null 2>&1 || {
  echo "realpath is required." >&2
  exit 1
}

source_argument=$1
if [[ $source_argument != /* ]]; then
  source_argument=$caller_dir/$source_argument
fi
source_path=$(realpath -- "$source_argument")
[[ -f $source_path ]] || {
  echo "Not a regular file: $source_path" >&2
  exit 1
}
[[ -r $source_path ]] || {
  echo "File is not readable: $source_path" >&2
  exit 1
}
[[ -w $source_path && -w $(dirname -- "$source_path") ]] || {
  echo "File and its directory must be writable: $source_path" >&2
  exit 1
}
[[ $source_path != *$'\n'* ]] || {
  echo "Newlines in file paths are not supported." >&2
  exit 1
}

cd "$script_dir"

if [[ $# -eq 2 ]]; then
  ./set-public-host.sh "$2"
fi

state_root=${MD_EDIT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/md-edit}
sessions_dir=$state_root/sessions
umask 077
mkdir -p "$sessions_dir"
chmod 700 "$state_root" "$sessions_dir"

pending_id="pending-$(date -u +%Y%m%dT%H%M%SZ)-$$"
session_dir=$sessions_dir/$pending_id
mkdir "$session_dir"

# This copy is made before HedgeDoc or the network is touched and is retained
# permanently unless the user explicitly removes the session directory.
cp -p -- "$source_path" "$session_dir/original.md"
sha256sum "$source_path" | awk '{ print $1 }' >"$session_dir/original.sha256"
printf '%s\n' "$source_path" >"$session_dir/source-path"
date -u +%Y-%m-%dT%H:%M:%SZ >"$session_dir/created-at"

echo "Protected original: $session_dir/original.md"

if ! ./start.sh; then
  echo "HedgeDoc failed to start. The protected original remains at:" >&2
  echo "  $session_dir/original.md" >&2
  exit 1
fi

server_port=$(sed -n 's/^MD_EDIT_PORT=//p' .env)
server_port=${server_port:-3000}
server_url=http://127.0.0.1:$server_port
for attempt in {1..60}; do
  if curl --fail --silent --output /dev/null "$server_url/"; then
    break
  fi
  if [[ $attempt -eq 60 ]]; then
    echo "HedgeDoc did not answer within 60 seconds." >&2
    echo "The protected original remains at: $session_dir/original.md" >&2
    exit 1
  fi
  sleep 1
done

if ! curl --fail --silent --show-error \
  --cookie-jar "$session_dir/cookies.txt" \
  --dump-header "$session_dir/import-headers" \
  --output /dev/null \
  --header 'Content-Type: text/markdown' \
  --data-binary "@$source_path" \
  "$server_url/new"; then
  echo "Import failed. The protected original remains at:" >&2
  echo "  $session_dir/original.md" >&2
  exit 1
fi

note_url=$(sed -n 's/^[Ll]ocation: //p' "$session_dir/import-headers" |
  tr -d '\r' | tail -n 1)
note_id=${note_url##*/}
note_id=${note_id%%\?*}
if [[ -z $note_id || $note_id == *[/\\]* ]]; then
  echo "Could not determine the imported note ID." >&2
  echo "The protected original remains at: $session_dir/original.md" >&2
  exit 1
fi

final_session_dir=$sessions_dir/$note_id
if [[ -e $final_session_dir ]]; then
  echo "Session directory already exists: $final_session_dir" >&2
  echo "Pending session retained at: $session_dir" >&2
  exit 1
fi
mv -- "$session_dir" "$final_session_dir"
session_dir=$final_session_dir
printf '%s\n' "$note_id" >"$session_dir/note-id"
printf '%s\n' "$note_url" >"$session_dir/note-url"
printf '%s\n' "$server_url" >"$session_dir/server-url"

finish() {
  signal_status=$1
  trap - INT TERM
  echo
  if "$script_dir/recover-md.sh" save "$note_id"; then
    echo "The protected original remains at: $session_dir/original.md"
    exit "$signal_status"
  fi
  echo "Save failed; the HedgeDoc note and protected original remain recoverable." >&2
  echo "Retry with: $script_dir/recover-md.sh save $note_id" >&2
  exit 1
}

trap 'finish 130' INT
trap 'finish 143' TERM

echo
echo "Collaborative URL: $note_url"
echo "Session ID:        $note_id"
echo "Protected original: $session_dir/original.md"
echo
echo "Press Enter to save the current HedgeDoc version back to the file."
echo "Ctrl-C also attempts the same guarded save."

if [[ -t 0 ]]; then
  read -r _ || true
  finish 0
fi

echo "No interactive terminal; leaving the session open without exporting." >&2
echo "Save later with: $script_dir/recover-md.sh save $note_id" >&2
