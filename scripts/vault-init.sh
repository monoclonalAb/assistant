#!/bin/sh
# Create Jarvis's memory vault from vault-template/ as a fresh git repo.
# Usage: scripts/vault-init.sh /absolute/path/to/vault
set -eu

vault=${1:-}
here=$(cd "$(dirname "$0")/.." && pwd)

if [ -z "$vault" ]; then
    echo "usage: $0 /absolute/path/to/vault (set HERMES_PROJECT_DIR in .env)" >&2
    exit 1
fi
case "$vault" in
    /*) ;;
    *) echo "vault path must be absolute: $vault" >&2; exit 1 ;;
esac
if [ "$vault" = "$HOME" ] || [ "$vault" = "/" ]; then
    echo "refusing to use $vault as the vault" >&2
    exit 1
fi

if [ -d "$vault/.git" ]; then
    echo "vault already initialised at $vault; leaving it alone"
    exit 0
fi
if [ -d "$vault" ] && [ -n "$(ls -A "$vault")" ]; then
    echo "$vault exists and is not empty; point HERMES_PROJECT_DIR at a new directory" >&2
    exit 1
fi

mkdir -p "$vault"
cp -R "$here/vault-template/." "$vault/"
git -C "$vault" init -q
git -C "$vault" add -A
git -C "$vault" -c user.name=Jarvis -c user.email=jarvis@localhost commit -q -m "vault: initial scaffold"
echo "created vault at $vault"
