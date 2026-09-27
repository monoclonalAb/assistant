# Personal Hermes container

This launcher runs the entire Hermes Agent process in Docker. It deliberately:

- exposes no host ports;
- mounts no Docker socket;
- mounts no home directory;
- persists Hermes state only in `~/.hermes-docker`; and
- lets Hermes edit only the directory selected by `HERMES_PROJECT_DIR` in `.env`.

The Discord gateway is a persistent Compose service with automatic restart.
Generated files intended for messaging are exported through
`~/.hermes-docker/cache/documents`, mounted as `/output` in the container.

## First run

Start Docker Desktop, then run:

```sh
cd ~/Desktop/projects/hermes/hermes-docker
make update
make setup
```

The setup wizard stores authentication and configuration in
`~/.hermes-docker`, separate from the native installation in `~/.hermes`.
It stops the gateway before changing shared state, then starts it again.

## Discord gateway

Start the gateway in the background and inspect it with:

```sh
make gateway-up
docker compose ps
make logs
```

The service runs `hermes gateway run` with `restart: unless-stopped`. Stop or
restart it with `make gateway-down` or `make gateway-restart`. Docker Desktop
must be running for the bot to stay online.

## Use Hermes

```sh
cd ~/Desktop/projects/hermes/hermes-docker
make tui
```

Use `make chat` for the classic interface, `make status` to inspect the
configuration, and `make doctor` for diagnostics. These commands execute inside
the running gateway container, so the gateway and interactive interfaces share
state without mounting the same state directory into competing containers.

## Work on a different project

Stop Hermes, edit `HERMES_PROJECT_DIR` in `.env` to the absolute path of one
specific project, then start it again. Do not point this variable at your home
directory. Any mounted project remains writable by Hermes, so keep important
work in Git and push or back it up regularly.

## Security boundary

Docker isolates host processes and files that are not mounted. It does not make
untrusted content harmless: Hermes can modify the mounted project, access its
own credentials in `/opt/data`, write messaging exports under `/output`, and use
the network. The `local` terminal backend means local to this outer container,
not local to macOS. Review third-party skills and plugins before installing
them, and do not expose a gateway or dashboard port without authentication and
a local firewall/VPN.
