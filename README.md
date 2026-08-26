# Personal Hermes container

This launcher runs the entire Hermes Agent process in Docker. It deliberately:

- exposes no host ports;
- mounts no Docker socket;
- mounts no home directory;
- persists Hermes state only in `~/.hermes-docker`; and
- lets Hermes edit only the directory selected by `HERMES_PROJECT_DIR` in `.env`.

## First run

Start Docker Desktop, then run:

```sh
cd ~/Projects/hermes-docker
make update
make setup
```

The setup wizard stores authentication and configuration in
`~/.hermes-docker`, separate from the native installation in `~/.hermes`.

## Use Hermes

```sh
cd ~/Projects/hermes-docker
make tui
```

Use `make chat` for the classic interface, `make status` to inspect the
configuration, and `make doctor` for diagnostics.

## Work on a different project

Stop Hermes, edit `HERMES_PROJECT_DIR` in `.env` to the absolute path of one
specific project, then start it again. Do not point this variable at your home
directory. Any mounted project remains writable by Hermes, so keep important
work in Git and push or back it up regularly.

## Security boundary

Docker isolates host processes and files that are not mounted. It does not make
untrusted content harmless: Hermes can modify the mounted project, access its
own credentials in `/opt/data`, and use the network. Review third-party skills
and plugins before installing them, and do not expose a gateway or dashboard
port without authentication and a local firewall/VPN.
