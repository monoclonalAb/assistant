#!/usr/bin/env bash
# One-time macOS settings for the always-on Jarvis Mac (make host-setup). Uses sudo.
#
#  - Never sleep on AC power, so Messages, BlueBubbles and Docker stay up.
#  - Download macOS updates automatically but don't install them. With
#    FileVault on, an unattended reboot leaves Jarvis offline until someone logs
#    in at the Mac, so install updates when you're home. Security data files
#    and security responses still install automatically.
#  - FileVault is only checked, never changed.
#
# Usage: scripts/host-setup.sh [--dry-run]
set -euo pipefail
[ "$(uname)" = Darwin ] || { echo "macOS only" >&2; exit 1; }

dry=0
[ "${1:-}" = --dry-run ] && dry=1
run() {
    echo "+ $*"
    [ "$dry" = 1 ] || "$@"
}
SU=/Library/Preferences/com.apple.SoftwareUpdate

echo "Power: on AC never sleep; display sleeps after 10 minutes"
run sudo pmset -c sleep 0 disksleep 0 displaysleep 10 womp 1

echo
echo "Software updates: check and download automatically, install manually"
run sudo defaults write "$SU" AutomaticCheckEnabled -bool true
run sudo defaults write "$SU" AutomaticDownload -bool true
run sudo defaults write "$SU" AutomaticallyInstallMacOSUpdates -bool false
run sudo defaults write "$SU" ConfigDataInstall -bool true
run sudo defaults write "$SU" CriticalUpdateInstall -bool true

echo
echo "FileVault: $(fdesetup status)"
case $(fdesetup status) in
    *"is On"*) ;;
    *) echo "  Recommended: turn it on in System Settings → Privacy & Security → FileVault." ;;
esac

cat <<'EOF'

Still to do by hand (once):
  - Docker Desktop → Settings → General → "Start Docker Desktop when you sign in"
  - BlueBubbles Server → Settings → "Start at login"
  - Tailscale: signed in, "Launch at login" on
  - System Settings → General → Sharing: Remote Login and Screen Sharing on
  - Keep the lid open and stay logged in; screen lock is fine

Then run: make check
EOF
