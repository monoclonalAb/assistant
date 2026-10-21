#!/bin/sh
# Apply Jarvis's Hermes configuration inside the running gateway container.
# Idempotent; safe to re-run after `make update`.
set -eu
. "$(dirname "$0")/lib.sh"
load_env
cd "$REPO"

hermes() { docker compose exec -T gateway hermes "$@"; }

# Sessions start in the vault, so .hermes.md (profile/now/tasks) is injected.
hermes config set terminal.cwd /workspace

# Instinct-style memory: the vault is the single source of truth, written only
# by the nightly job. Turn off Hermes's built-in live-edited MEMORY.md/USER.md.
# session_search stays on for "what did I say earlier today".
hermes config set memory.memory_enabled false
hermes config set memory.user_profile_enabled false

# The jarvis-dream skill is mounted read-only from this repo.
hermes config set skills.external_dirs '["/opt/jarvis/skills"]'

# Jarvis identity (the previous SOUL.md is backed up once).
if [ -f "${HERMES_DATA_DIR}/SOUL.md" ] && ! cmp -s hermes/SOUL.md "${HERMES_DATA_DIR}/SOUL.md"; then
    cp "${HERMES_DATA_DIR}/SOUL.md" "${HERMES_DATA_DIR}/SOUL.md.bak.$(date +%Y%m%d%H%M%S)"
fi
cp hermes/SOUL.md "${HERMES_DATA_DIR}/SOUL.md"

docker compose restart gateway
echo "configured; gateway restarted"
