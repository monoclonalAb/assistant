#!/usr/bin/env bash
# Read-only health and safety audit of the Jarvis setup (make check).
# Changes nothing. Exits non-zero if anything is actually wrong (✗).
set -uo pipefail
. "$(dirname "$0")/lib.sh"
load_env
cd "$REPO"

DATA=${HERMES_DATA_DIR:-}
VAULT=${HERMES_PROJECT_DIR:-}
HENV="$DATA/.env"
henv() { env_get "$HENV" "$1"; }
count() { printf '%s\n' "$1" | tr ',' '\n' | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '; }
running() { [ -n "$(docker compose ps --status running -q gateway 2>/dev/null)" ]; }
hcfg() { docker compose exec -T gateway hermes config get "$1" 2>/dev/null | tail -n 1; }

# --- Config -------------------------------------------------------------------
heading "Config"
if [ -f .env ]; then pass ".env present"; else warn "no .env in $REPO (cp .env.example .env)"; fi
if out=$(scripts/preflight.sh 2>&1); then
    pass "vault: $VAULT"
    [ -z "$out" ] || warn "$out"
else
    fail "$(printf '%s' "$out" | head -n 1)"
fi
if [ -f "$VAULT/.dream/watermark" ]; then
    wm=$(cut -d. -f1 "$VAULT/.dream/watermark")
    pass "nightly job has processed messages up to $(date -r "$wm" '+%a %Y-%m-%d %H:%M')"
else
    warn "the nightly job hasn't completed yet (make dream-run to try it now)"
fi

# --- Who can talk to Jarvis ---------------------------------------------------
heading "Who can talk to Jarvis"
if [ ! -f "$HENV" ]; then
    warn "no Hermes .env at $HENV yet (make setup)"
else
    truthy "$(henv GATEWAY_ALLOW_ALL_USERS)" && fail "GATEWAY_ALLOW_ALL_USERS=true: anyone on any platform can use Jarvis"

    if [ -n "$(henv BLUEBUBBLES_SERVER_URL)" ]; then
        if truthy "$(henv BLUEBUBBLES_ALLOW_ALL_USERS)"; then
            fail "iMessage: BLUEBUBBLES_ALLOW_ALL_USERS=true, so anyone who texts Jarvis can use it"
        elif [ -n "$(henv BLUEBUBBLES_ALLOWED_USERS)" ]; then
            pass "iMessage: allowlist of $(count "$(henv BLUEBUBBLES_ALLOWED_USERS)") address(es)"
        else
            warn "iMessage: no BLUEBUBBLES_ALLOWED_USERS, so strangers who text Jarvis get pairing codes. Set it to your number/iCloud address."
        fi
    else
        warn "iMessage (BlueBubbles) isn't configured yet"
    fi

    if [ -n "$(henv DISCORD_BOT_TOKEN)" ]; then
        users=$(henv DISCORD_ALLOWED_USERS)
        roles=$(henv DISCORD_ALLOWED_ROLES)
        channels=$(henv DISCORD_ALLOWED_CHANNELS)
        if truthy "$(henv DISCORD_ALLOW_ALL_USERS)"; then
            fail "Discord: DISCORD_ALLOW_ALL_USERS=true, so anyone who can reach the bot can use Jarvis and feed its memory"
        elif [ -n "$users" ]; then
            pass "Discord: allowlist of $(count "$users") user(s)"
            [ -z "$roles" ] || warn "Discord: anyone with a role in DISCORD_ALLOWED_ROLES can also use Jarvis"
        elif [ -n "$roles" ]; then
            warn "Discord: anyone with a role in DISCORD_ALLOWED_ROLES can use Jarvis; prefer DISCORD_ALLOWED_USERS=<your user id>"
        elif [ -n "$channels" ]; then
            warn "Discord: anyone in DISCORD_ALLOWED_CHANNELS can use Jarvis; add DISCORD_ALLOWED_USERS=<your user id>"
        else
            pass "Discord: only pairing-approved users (Hermes denies everyone else by default)"
        fi
    fi

    if running; then
        for key in allow_all_users gateway.allow_all_users; do
            truthy "$(hcfg "$key")" && fail "config.yaml $key is true: anyone on any platform can use Jarvis"
        done
        approved=$(docker compose exec -T gateway hermes pairing list 2>/dev/null | sed '/^[[:space:]]*$/d')
        if [ -n "$approved" ]; then
            info "pairing state (approved users can talk to Jarvis):"
            printf '%s\n' "$approved" | sed 's/^/      /'
        fi
    fi
fi

# --- Jarvis ---------------------------------------------------------------------
heading "Jarvis"
if running; then
    pass "gateway container is running"
    [ "$(hcfg terminal.cwd)" = /workspace ] && pass "sessions start in the vault" ||
        fail "terminal.cwd isn't /workspace (make configure)"
    truthy "$(hcfg memory.memory_enabled)" && warn "built-in MEMORY.md is on (make configure turns it off)"
else
    fail "gateway container isn't running (make gateway-up)"
fi

if [ -f "$DATA/cron/jobs.json" ] && command -v python3 >/dev/null; then
    job_report=$(python3 - "$DATA/cron/jobs.json" <<'EOF'
import json, sys
jobs = [j for j in json.load(open(sys.argv[1])).get("jobs", []) if j.get("name") == "jarvis-dream"]
if not jobs:
    print("WARN nightly job isn't installed (make dream-install)")
for j in jobs:
    model = j.get("model") or "main model"
    print(f"PASS nightly job: {j.get('schedule_display')} · {model} · reasoning {j.get('reasoning_effort') or 'default'} · next {j.get('next_run_at')}")
    status = j.get("last_status")
    if status not in (None, "ok"):
        print(f"FAIL last nightly run: {status}: {(j.get('last_error') or '')[:200]}")
EOF
)
else
    job_report="WARN nightly job isn't installed (make dream-install)"
fi
while IFS= read -r line; do
    case $line in
        PASS*) pass "${line#PASS }" ;;
        WARN*) warn "${line#WARN }" ;;
        FAIL*) fail "${line#FAIL }" ;;
        ?*) info "$line" ;;
    esac
done <<<"$job_report"

[ -n "${JARVIS_NOTIFY:-}" ] && pass "failure alerts go to $JARVIS_NOTIFY" ||
    warn "JARVIS_NOTIFY is empty: failed nightly runs and backups are silent"

backup_status=$(scripts/vault-backup.sh status 2>/dev/null)
case $backup_status in
    *"last backup: ok"*) pass "$(printf '%s' "$backup_status" | head -n 1)" ;;
    *"last backup: fail"*) fail "$(printf '%s' "$backup_status" | head -n 1)" ;;
    *) warn "vault isn't backed up yet (make vault-backup-setup)" ;;
esac
case $backup_status in *"schedule: not installed"*) warn "daily backup isn't scheduled (make vault-backup-setup)" ;; esac

# --- This Mac -----------------------------------------------------------------
if [ "$(uname)" = Darwin ]; then
    heading "This Mac"
    case $(fdesetup status 2>/dev/null) in
        *"is On"*) pass "FileVault is on" ;;
        *) warn "FileVault is off: the vault, Hermes logins and Apple ID session sit unencrypted on disk" ;;
    esac
    ac_sleep=$(pmset -g custom 2>/dev/null | awk '/^AC Power:/{ac=1;next} /^[A-Za-z].*:$/{ac=0} ac && $1=="sleep"{print $2}')
    [ "$ac_sleep" = 0 ] && pass "never sleeps on AC power" || warn "sleeps on AC after ${ac_sleep:-?} min (make host-setup)"
    auto=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 2>/dev/null)
    [ "$auto" = 0 ] && pass "macOS updates download but wait for you to install" ||
        warn "macOS may install updates and reboot on its own; with FileVault that leaves Jarvis offline until you log in (make host-setup)"
    docker info >/dev/null 2>&1 && pass "Docker is running" || fail "Docker isn't running"
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        pass "Tailscale is connected"
    else
        warn "Tailscale isn't connected (or its CLI isn't installed)"
    fi
    url=$(henv BLUEBUBBLES_SERVER_URL)
    if [ -n "$url" ]; then
        host_url=$(printf %s "$url" | sed 's#host\.docker\.internal#127.0.0.1#')
        if curl -fsS -m 5 -o /dev/null "$host_url/api/v1/ping?password=$(henv BLUEBUBBLES_PASSWORD)" 2>/dev/null; then
            pass "BlueBubbles Server answers at $host_url"
        else
            fail "BlueBubbles Server doesn't answer at $host_url (is it running and logged in?)"
        fi
    fi
fi

printf '\n%s problem(s), %s warning(s)\n' "$FAILURES" "$WARNINGS"
[ "$FAILURES" -eq 0 ]
