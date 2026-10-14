# Collaborative Markdown on a trusted LAN

## Intended use and threat model

`md-edit` is a convenience tool for short-lived collaborative editing among
colleagues on a mutually trusted LAN. Run `md-edit document.md`, share the
random HedgeDoc URL it prints, and save the collaborative result back to the
local file when the session is finished.

This setup deliberately provides:

- plaintext HTTP on port 3000;
- anonymous note creation and editing; and
- no meaningful access-control boundary between LAN participants.

It does **not** provide TLS, authenticated collaborator identity, protection
against network eavesdropping or tampering, or resilience against malicious
LAN users. A random note URL is convenient routing, not a security credential.
The protected original and conflict checks guard against accidental data loss,
not an attacker with access to the host or its user account.

Do not expose this configuration to the public internet, port-forward it from a
router, or use it on an untrusted network. Add a firewall/VPN and HTTPS plus an
authentication policy before expanding beyond the trusted-LAN threat model.

This directory runs HedgeDoc 1.x with PostgreSQL. HedgeDoc provides real-time
Markdown editing, revisions, note permissions, uploads, diagrams, and slide
presentations.

Documents live in PostgreSQL rather than as ordinary `.md` files. Export notes
from the web UI when standalone Markdown files are needed.

## Prerequisites

- Podman with `podman-compose` (preferred), or Docker with Compose
- OpenSSL (used once to generate secrets)
- TCP port 3000 allowed through the host firewall for the intended LAN

This host has rootless Podman and `podman-compose`; see [PODMAN.md](PODMAN.md)
for operational notes.

## First run

From this directory:

```sh
./configure.sh 192.168.1.50
```

Replace the example with this machine's LAN IP or a hostname that every client
can resolve. `configure.sh` can usually detect the address when called without
an argument. Review `.env`, then start the service:

```sh
./start.sh
./logs.sh
```

Open `http://192.168.1.50:3000`, create a note, and share its URL. Press Ctrl-C
to leave the log viewer; that does not stop the containers.

The `0.0.0.0` bind in `.env` means "listen on every interface." It is not a URL
and does not by itself configure the firewall or router.

Always use the hostname printed by `start.sh` (currently the value of
`MD_EDIT_PUBLIC_HOST`) rather than substituting `localhost`. HedgeDoc uses that
hostname in its asset URLs and Content Security Policy. Opening the same server
under a different name can produce an unstyled or nonfunctional page.

The landing page offers sign-in, but the trusted-LAN defaults do not require it.
Use **New guest note**, visit the `/new` URL, or invoke `md-edit document.md` to
create an anonymously editable note.

## Edit an existing Markdown file

The `md-edit` launcher resolves its own installation directory, including when
invoked through a symbolic link. Install it somewhere already in `PATH`:

```sh
ln -s "$(realpath ./md-edit)" ~/.local/bin/md-edit
```

The command refuses naturally if that path already exists; inspect or remove an
old command yourself rather than forcing replacement.

From any directory, import a local file into a collaborative session and save
the result back:

```sh
md-edit document.md
md-edit document.md karn.local
md-edit document.md 10.10.10.10:3000
md-edit document.md karn.local:8300
```

Relative file arguments are resolved from the caller's current directory, not
from the repository containing the scripts. Calling `md-edit` without a file
only starts the HedgeDoc service. The command prints a URL to share, then waits.
Press Enter to export the current HedgeDoc version back to the file; Ctrl-C
performs the same guarded save.

The optional second argument selects the canonical `HOST[:PORT]` for that
throw-away collaboration session; the port defaults to 3000. If it differs from
`.env`, `md-edit` warns that active connections and old-origin URLs will be
disrupted and asks for confirmation. On approval it updates `.env`, stops the
old containers while preserving PostgreSQL and uploads, and starts the session
under the new origin. Rootless container engines may reject ports below 1024.

Before starting HedgeDoc or making a network request, the script keeps an
untouched copy under:

```text
${XDG_STATE_HOME:-~/.local/state}/md-edit/sessions/SESSION_ID/original.md
```

These originals and exported snapshots are never automatically deleted. They
are outside this repository and its container volumes. Set `MD_EDIT_STATE_DIR`
to choose a different private state directory.

List or recover sessions with:

```sh
./recover-md.sh list
./recover-md.sh save SESSION_ID
./recover-md.sh original SESSION_ID
./recover-md.sh original SESSION_ID ./restored-original.md
```

`save` refuses to overwrite the recorded source if another program changed it
after import or the last successful export. The freshly downloaded HedgeDoc
version is retained in the session directory for manual comparison. `original`
without a destination only prints the protected copy's path.

HedgeDoc remains authoritative during a collaborative session. Saving creates a
snapshot; it does not lock the note or prevent collaborators from making later
edits. Run `recover-md.sh save` again to retrieve a later version.

## Routine commands

```sh
./start.sh                 # create/start containers
./stop.sh                  # stop containers; preserve all data
./logs.sh                  # follow application and database logs
./backup.sh                # database, uploads, and config under backups/
./compose.sh ps             # current container state
./compose.sh pull           # fetch versions named in compose.yaml
```

Do not run `./compose.sh down --volumes` unless permanent data deletion is
intended.

## Access policy

The supplied `.env` is deliberately convenient for a trusted LAN:

- anonymous visitors are allowed;
- new local accounts may be registered; and
- a new signed-in user's notes default to `freely`, allowing link holders to
  edit.

For an account-only instance, edit `.env`:

```dotenv
MD_EDIT_ALLOW_ANONYMOUS=false
MD_EDIT_ALLOW_ANONYMOUS_EDITS=false
MD_EDIT_ALLOW_EMAIL_REGISTER=false
MD_EDIT_DEFAULT_PERMISSION=private
```

Create any wanted accounts before disabling registration, then restart with
`./compose.sh up -d`. Note owners can still change individual permissions in
the UI.

## Plain-HTTP warning

HTTP exposes note contents, passwords, and session cookies to anyone able to
observe the network. Keep port 3000 off the public internet and do not use this
configuration over untrusted Wi-Fi.

For remote access, a private VPN is the smallest next step. For conventional
internet hosting, put Caddy or nginx in front, change `MD_EDIT_BIND_IP` to
`127.0.0.1`, enable HTTPS-related HedgeDoc settings, and proxy WebSocket
upgrades for `/socket.io/`.

## Backups and restoration

`./backup.sh` creates a timestamped directory containing:

- `database.sql.gz`
- `uploads.tar.gz`
- `config.env`

Copy backups off this machine. They contain private documents and credentials.

Restoration overwrites data, so it is intentionally not wrapped in a script.
For a fresh stack, start the database, then restore the SQL before starting the
app:

```sh
./compose.sh up -d database
gzip -dc backups/TIMESTAMP/database.sql.gz |
  ./compose.sh exec -T database psql -U hedgedoc hedgedoc
./compose.sh up -d app
gzip -dc backups/TIMESTAMP/uploads.tar.gz |
  ./compose.sh exec -T app tar -C /hedgedoc/public/uploads -xzf -
```

Review the target and retain a separate backup before restoring over an
existing instance.

## Upgrades

The application and database images are pinned in `compose.yaml`. Before
changing either version, read its release notes and make a backup. PostgreSQL
major versions require a database migration; changing only the image tag is not
a valid major-version upgrade.

Useful upstream documentation:

- <https://docs.hedgedoc.org/setup/docker/>
- <https://docs.hedgedoc.org/configuration/>
- <https://docs.hedgedoc.org/guides/production-ready/>
- <https://docs.hedgedoc.org/guides/reverse-proxy/>
