#!/usr/bin/env bash
# Back up Jarvis's vault to a private git remote (GitHub by default).
#
# The agent can write the vault's .git/config and hooks, so running git
# *inside* the vault on the host (push, log -p, status, …) could run
# agent-chosen commands outside the sandbox. This script never does. It
# fetches the vault's commits over file:// into a host-owned bare mirror (git
# serves that with upload-pack, which is safe to run against untrusted
# repositories), then pushes from the mirror, whose config only you control.
# Fetch and push are fast-forward only, so a compromised agent can't rewrite
# the backed-up history.
#
# Usage: scripts/vault-backup.sh setup | run | install | uninstall | status | log [git log args]
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_env

VAULT=${HERMES_PROJECT_DIR:-}
MIRROR=${JARVIS_BACKUP_MIRROR:-$HOME/.jarvis/vault-backup.git}
KEY=${JARVIS_BACKUP_KEY:-$HOME/.ssh/jarvis_vault_backup}
REMOTE=${JARVIS_BACKUP_REMOTE:-}
HOUR=${JARVIS_BACKUP_HOUR:-5}
LABEL=${JARVIS_BACKUP_LABEL:-com.jarvis.vault-backup}
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/jarvis/vault-backup.log"
STATE="$MIRROR/jarvis-last-backup"

mgit() { git --git-dir="$MIRROR" "$@"; }
stamp() { date '+%Y-%m-%d %H:%M:%S'; }

ensure_mirror() {
    [ -n "$VAULT" ] || die "HERMES_PROJECT_DIR is not set"
    [ -d "$VAULT/.git" ] || die "$VAULT is not a git repo (make vault-init)"
    [ -d "$MIRROR" ] || { mkdir -p "$(dirname "$MIRROR")" && git init -q --bare "$MIRROR"; }
}

# Pull the vault's commits into the mirror. Fast-forward only.
fetch_vault() {
    mgit fetch --quiet --no-tags "file://$VAULT" 'refs/heads/*:refs/heads/*'
}

github_repo() { # owner/name for GitHub remotes, else empty
    printf '%s\n' "$1" | sed -nE 's#^(git@github\.com:|ssh://git@github\.com/|https://github\.com/)([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//'
}

notify() {
    [ -n "${JARVIS_NOTIFY:-}" ] || return 0
    "$REPO/scripts/notify.sh" "Jarvis: vault backup failed. $1" >/dev/null 2>&1 || true
}

record() { # record ok|fail MESSAGE
    printf '%s %s %s\n' "$(date +%s)" "$1" "$2" >"$STATE"
    echo "[$(stamp)] backup $1: $2"
}

cmd_setup() {
    ensure_mirror
    if [ -z "$REMOTE" ]; then
        command -v gh >/dev/null && gh auth status >/dev/null 2>&1 ||
            die "set JARVIS_BACKUP_REMOTE in .env, or log in with 'gh auth login' to default to a private GitHub repo"
        REMOTE="git@github.com:$(gh api user -q .login)/jarvis-vault.git"
    fi

    case $REMOTE in
        git@* | ssh://*)
            if [ ! -f "$KEY" ]; then
                mkdir -p "$(dirname "$KEY")"
                ssh-keygen -q -t ed25519 -N "" -C "jarvis-vault-backup@$(hostname -s)" -f "$KEY"
                echo "created deploy key $KEY"
            fi
            mgit config core.sshCommand "ssh -i '$KEY' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
            ;;
    esac

    repo=$(github_repo "$REMOTE")
    if [ -n "$repo" ]; then
        if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
            if ! gh repo view "$repo" >/dev/null 2>&1; then
                gh repo create "$repo" --private --description "Jarvis memory vault backup" >/dev/null
                echo "created private GitHub repo $repo"
            fi
            visibility=$(gh repo view "$repo" --json visibility -q .visibility)
            [ "$visibility" = PRIVATE ] || die "$repo is $visibility; refusing to back up your memory to a non-private repo"
            pub=$(cut -d' ' -f1,2 "$KEY.pub")
            if ! gh api "repos/$repo/keys" -q '.[].key' | grep -qxF "$pub"; then
                gh repo deploy-key add "$KEY.pub" -R "$repo" --allow-write --title "jarvis-vault-backup ($(hostname -s))" >/dev/null
                echo "added write deploy key to $repo"
            fi
        else
            echo "gh isn't logged in here, so I can't create or check $repo. Make sure it exists, is"
            echo "PRIVATE, and has this deploy key with write access (Settings → Deploy keys):"
            cat "$KEY.pub"
        fi
    fi

    if mgit remote get-url backup >/dev/null 2>&1; then
        mgit remote set-url backup "$REMOTE"
    else
        mgit remote add backup "$REMOTE"
    fi
    echo "backup remote: $REMOTE"
    cmd_run
}

cmd_run() {
    ensure_mirror
    mgit remote get-url backup >/dev/null 2>&1 || die "no backup remote yet; run: make vault-backup-setup"
    local out
    if ! out=$(fetch_vault 2>&1); then
        record fail "couldn't fast-forward from the vault (was history rewritten?): ${out//$'\n'/ }"
        notify "Couldn't fast-forward from the vault; check it before forcing anything."
        return 1
    fi
    if ! out=$(mgit push --quiet backup 'refs/heads/*:refs/heads/*' 2>&1); then
        record fail "push to $(mgit remote get-url backup) failed: ${out//$'\n'/ }"
        notify "Push to the backup remote failed; run make check on the Mac."
        return 1
    fi
    record ok "$(mgit for-each-ref --format='%(refname:short)@%(objectname:short)' refs/heads | tr '\n' ' ')"
}

cmd_log() {
    ensure_mirror
    fetch_vault
    mgit log "$@"
}

cmd_install() {
    [ "$(uname)" = Darwin ] || die "the daily schedule uses launchd (macOS only)"
    mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
    cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$REPO/scripts/vault-backup.sh</string><string>run</string></array>
  <key>WorkingDirectory</key><string>$REPO</string>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$HOUR</integer><key>Minute</key><integer>0</integer></dict>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
    plutil -lint "$PLIST" >/dev/null
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "daily backup scheduled at $(printf '%02d' "$HOUR"):00 ($LABEL); log: $LOG"
}

cmd_uninstall() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "removed $LABEL"
}

cmd_status() {
    if [ -f "$STATE" ]; then
        read -r when result detail <"$STATE"
        echo "last backup: $result at $(date -r "$when" '+%Y-%m-%d %H:%M') ($detail)"
    else
        echo "no backup has run yet"
    fi
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
        echo "schedule: daily at $(printf '%02d' "$HOUR"):00 ($LABEL)"
    else
        echo "schedule: not installed"
    fi
}

case "${1:-}" in
    setup) cmd_setup ;;
    run) cmd_run ;;
    log) shift; cmd_log "$@" ;;
    install) cmd_install ;;
    uninstall) cmd_uninstall ;;
    status) cmd_status ;;
    *) echo "usage: $0 setup | run | install | uninstall | status | log [git log args]" >&2; exit 1 ;;
esac
