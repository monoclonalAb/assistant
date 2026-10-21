#!/bin/sh
# Manage the nightly memory consolidation cron job inside the gateway container.
# Usage: scripts/dream.sh install | reinstall | run | status | remove
#
# Settings (in .env):
#   JARVIS_DREAM_SCHEDULE   cron expression in JARVIS_TIMEZONE (default: 0 4 * * *)
#   JARVIS_DREAM_REASONING  reasoning effort for the job (default: high)
#   JARVIS_DREAM_MODEL      optional: pin a stronger model than chat uses
#   JARVIS_DREAM_PROVIDER   provider for that model (default: openai-codex)
#   JARVIS_NOTIFY           optional: where failure notices go, e.g. bluebubbles:+64…
set -eu
. "$(dirname "$0")/lib.sh"
load_env

NAME=jarvis-dream
SCHEDULE=${JARVIS_DREAM_SCHEDULE:-0 4 * * *}
REASONING=${JARVIS_DREAM_REASONING:-high}
PROMPT="Run tonight's memory consolidation for the Jarvis vault at /workspace. Follow the jarvis-dream skill exactly; the Script Output above is your input."

job_id() { # job_id NAME
    docker compose exec -T gateway python3 -c '
import json, sys
try:
    jobs = json.load(open("/opt/data/cron/jobs.json")).get("jobs", [])
except FileNotFoundError:
    jobs = []
print(next((j["id"] for j in jobs if j.get("name") == sys.argv[1]), ""))
' "$1"
}

create() { # create NAME SCHEDULE
    set -- cron create "$2" "$PROMPT" \
        --name "$1" \
        --skill jarvis-dream \
        --script jarvis_dream_collect.py \
        --deliver local \
        --reasoning-effort "$REASONING"
    if [ -n "${JARVIS_DREAM_MODEL:-}" ]; then
        set -- "$@" --model "$JARVIS_DREAM_MODEL" --provider "${JARVIS_DREAM_PROVIDER:-openai-codex}"
    fi
    if [ -n "${JARVIS_NOTIFY:-}" ]; then
        set -- "$@" --failure-deliver "$JARVIS_NOTIFY"
    fi
    docker compose exec -T gateway hermes "$@"
}

remove() { # remove NAME
    id=$(job_id "$1")
    [ -n "$id" ] || { echo "$1 is not installed"; return 0; }
    docker compose exec -T gateway hermes cron remove "$id"
}

install() {
    id=$(job_id "$NAME")
    if [ -n "$id" ]; then
        echo "$NAME already installed ($id); use 'make dream-reinstall' to apply new settings"
        return 0
    fi
    create "$NAME" "$SCHEDULE"
}

case "${1:-}" in
    install) install ;;
    reinstall) remove "$NAME" && install ;;
    run)
        # A one-shot copy fired by the gateway's own scheduler. (`hermes cron run` runs the job
        # inside this CLI process instead, where iMessage failure alerts can't be delivered.)
        remove "$NAME-now" >/dev/null
        create "$NAME-now" "in 1m" >/dev/null
        echo "queued: the gateway runs it within ~2 minutes. Then: make dream-status"
        ;;
    status)
        docker compose exec -T gateway hermes cron list --all
        docker compose exec -T gateway hermes cron runs --limit 10 2>/dev/null || true
        ;;
    remove) remove "$NAME" ;;
    *)
        echo "usage: $0 install | reinstall | run | status | remove" >&2
        exit 1
        ;;
esac
