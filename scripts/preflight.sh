#!/bin/sh
# Runs before anything starts the container. Refuses to mount anything but a
# Jarvis vault as Hermes's writable project: Jarvis is reachable by text and
# reads untrusted content, so it must never get a code project or client repo.
set -eu
. "$(dirname "$0")/lib.sh"
load_env

vault=${HERMES_PROJECT_DIR:-}
data=${HERMES_DATA_DIR:-}
refuse() {
    echo "✗ $*" >&2
    echo "  HERMES_PROJECT_DIR must be Jarvis's memory vault (create one with: make vault-init)." >&2
    exit 1
}

[ -n "$data" ] || { echo "✗ HERMES_DATA_DIR is not set (cp .env.example .env)" >&2; exit 1; }
case $data in /*) ;; *) echo "✗ HERMES_DATA_DIR must be an absolute path: $data" >&2; exit 1 ;; esac
[ -n "$vault" ] || refuse "HERMES_PROJECT_DIR is not set"
case $vault in /*) ;; *) refuse "HERMES_PROJECT_DIR must be an absolute path: $vault" ;; esac
[ "$vault" != "$HOME" ] && [ "$vault" != / ] || refuse "HERMES_PROJECT_DIR must not be $vault"
[ -d "$vault/.git" ] && [ -f "$vault/.hermes.md" ] && [ -f "$vault/system/chat.md" ] ||
    refuse "$vault is not a Jarvis vault"

case $vault in
    "$HOME"/Desktop/* | "$HOME"/Documents/* | "$HOME"/Library/Mobile\ Documents/*)
        echo "! $vault is under Desktop/Documents/iCloud. Sync can corrupt git, and macOS privacy" >&2
        echo "  prompts can block Docker and the backup job. ~/jarvis-vault is a better home." >&2
        ;;
esac

# compose.yaml bind-mounts this; create it so a fresh data dir just works.
mkdir -p "$data/cache/documents"
