# Running with Podman

This host has Podman 5.4.2 and `podman-compose` 1.3.0. Podman runs rootlessly
with the Netavark network backend. The images, named volumes, health check,
networking, and port mapping in `compose.yaml` fit that setup.

All project scripts use `compose.sh`. It prefers a working Podman installation
and falls back to Docker Compose, so these are equivalent here:

```sh
./compose.sh ps
podman compose ps
```

Podman prints a notice when it delegates to the external `podman-compose`
provider. That notice is expected.

## Rootless operational notes

- Port 3000 does not require root privileges.
- Data lives in named volumes under the current user's Podman storage.
- Always run the scripts as the same user. Root and rootless Podman have
  separate container and volume stores.
- Rootless containers may stop when the user session ends unless lingering or
  a user-level systemd/Quadlet service keeps them alive.

The Compose bundle is sufficient for interactive use. For an always-on service,
convert it to Quadlet or create a reviewed user service rather than running it
through `sudo`.

Useful upstream documentation:

- <https://docs.podman.io/en/latest/markdown/podman-compose.1.html>
- <https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html>
