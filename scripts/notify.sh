#!/bin/sh
# Send an alert to JARVIS_NOTIFY from the host (backup failures, make notify-test).
# Usage: scripts/notify.sh "message"
#
# BlueBubbles targets (bluebubbles:+64… or bluebubbles:you@icloud.com) go straight
# to the BlueBubbles Server on this Mac. `hermes send` can't be used for them while
# the gateway runs: it starts a second BlueBubbles adapter, which fails to bind the
# webhook port. Other platforms (e.g. discord:<channel id>) go through `hermes send`.
set -eu
. "$(dirname "$0")/lib.sh"
load_env
cd "$REPO"

message=${1:?usage: $0 "message"}
target=${JARVIS_NOTIFY:-}
[ -n "$target" ] || die "JARVIS_NOTIFY is not set in .env"

case $target in
    bluebubbles:*)
        HENV="${HERMES_DATA_DIR:?}/.env" ADDRESS=${target#bluebubbles:} MESSAGE=$message python3 - <<'EOF'
import json, os, re, sys, time, urllib.parse, urllib.request

def env(key):
    value = ""
    for line in open(os.environ["HENV"], encoding="utf-8"):
        if line.startswith(key + "="):
            value = line.split("=", 1)[1].strip().strip("'\"")
    return value

base = env("BLUEBUBBLES_SERVER_URL").replace("host.docker.internal", "127.0.0.1").rstrip("/")
password = env("BLUEBUBBLES_PASSWORD")
if not base or not password:
    sys.exit("BlueBubbles isn't configured in the Hermes .env (make setup)")
auth = "?password=" + urllib.parse.quote(password, safe="")

def post(path, payload):
    req = urllib.request.Request(base + path + auth, json.dumps(payload).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as res:
        return json.load(res)

address = os.environ["ADDRESS"].strip()
chats = post("/api/v1/chat/query", {"limit": 1000, "offset": 0}).get("data") or []
guid = next((c.get("guid") for c in chats
             if (c.get("chatIdentifier") or c.get("identifier")) == address and ";-;" in (c.get("guid") or "")), None)
if not guid:
    sys.exit(f"no iMessage chat with {address} yet; text Jarvis from it once first")
post("/api/v1/message/text", {"chatGuid": guid, "tempGuid": f"temp-{time.time()}", "message": os.environ["MESSAGE"]})
EOF
        ;;
    *)
        docker compose exec -T gateway hermes send -q -t "$target" "$message"
        ;;
esac
