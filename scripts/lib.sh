# Shared helpers for scripts/*.sh (POSIX sh). Source with:
#   . "$(dirname "$0")/lib.sh"

REPO=$(cd "$(dirname "$0")/.." && pwd)

# Export KEY=VALUE pairs from the repo's .env for every variable that isn't
# already set, so scripts behave the same under make, launchd and a bare shell.
load_env() {
    [ -f "$REPO/.env" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in '' | '#'*) continue ;; esac
        key=${line%%=*}
        value=${line#*=}
        case $key in '' | [0-9]* | *[!A-Za-z0-9_]*) continue ;; esac
        eval "already=\${$key+set}"
        [ "$already" = set ] && continue
        value=${value#\"}; value=${value%\"}; value=${value#\'}; value=${value%\'}
        export "$key=$value"
    done <"$REPO/.env"
}

# env_get FILE KEY: last value of KEY in a dotenv file, quotes stripped ("" if absent).
env_get() {
    [ -f "$1" ] || return 0
    sed -n "s/^[[:space:]]*$2=//p" "$1" | tail -n 1 | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

truthy() {
    case $(printf %s "${1:-}" | tr '[:upper:]' '[:lower:]') in true | 1 | yes) return 0 ;; esac
    return 1
}

if [ -t 1 ]; then
    C_OK='\033[32m' C_WARN='\033[33m' C_BAD='\033[31m' C_BOLD='\033[1m' C_OFF='\033[0m'
else
    C_OK='' C_WARN='' C_BAD='' C_BOLD='' C_OFF=''
fi
FAILURES=0
WARNINGS=0
heading() { printf "\n${C_BOLD}%s${C_OFF}\n" "$*"; }
pass() { printf "  ${C_OK}✓${C_OFF} %s\n" "$*"; }
warn() { printf "  ${C_WARN}!${C_OFF} %s\n" "$*"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf "  ${C_BAD}✗${C_OFF} %s\n" "$*"; FAILURES=$((FAILURES + 1)); }
info() { printf "    %s\n" "$*"; }
die() { echo "error: $*" >&2; exit 1; }
