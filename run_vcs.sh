#!/usr/bin/env bash
###############################################################################
# run_vcs.sh — one command: VCS regression + scoreboard + coverage dashboard
#
#   ./run_vcs.sh                 # full 200-run plan, then open the scoreboard
#   SEEDS=1 ./run_vcs.sh         # smoke
#   JOBS=16 ./run_vcs.sh         # parallel
#   TAG=ci ./run_vcs.sh          # tag-filtered
#   NO_OPEN=1 ./run_vcs.sh       # don't launch a browser
#
# Everything is relative to this script, so the directory can be moved/copied
# to another machine as-is.
###############################################################################
set -uo pipefail
cd "$(dirname "$0")"

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required."
    exit 1
fi
if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    echo "ERROR: PyYAML is required (pip install pyyaml)."
    exit 1
fi

echo "########################################################################"
echo "# L2 Cache VCS regression"
echo "#   JOBS=${JOBS:-8}  SEEDS=${SEEDS:-0}  TAG=${TAG:-<all>}  WAVES=${WAVES:-0}"
echo "########################################################################"

bash scripts/run_all_vcs.sh
REG_RC=$?

SCOREBOARD="$(pwd)/reports/regression/scoreboard.html"
if [ -f reports/regression/run_summary.txt ]; then
    python3 scripts/regression/make_scoreboard.py || true
else
    echo "WARN: no reports/regression/run_summary.txt (compile failed?)"
fi

open_report() {
    local f=$1
    [ -f "$f" ] || return 0
    [ "${NO_OPEN:-0}" = 1 ] && { echo "Open manually: file://$f"; return 0; }
    if [ -n "${OPEN_CMD:-}" ]; then
        eval "$OPEN_CMD \"$f\"" >/dev/null 2>&1 &
    elif command -v xdg-open >/dev/null 2>&1 && \
         [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        xdg-open "$f" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then
        open "$f" >/dev/null 2>&1 &
    else
        echo "Open manually: file://$f"
    fi
}

echo
echo "=== Results ==========================================================="
if [ -f reports/regression/run_summary.txt ]; then
    awk '{print $1}' reports/regression/run_summary.txt | sort | uniq -c
    grep -v '^PASS' reports/regression/run_summary.txt || true
fi
echo "Scoreboard : file://$SCOREBOARD"
echo "Coverage   : file://$(pwd)/reports/coverage/merged/dashboard.html"
echo "Logs       : $(pwd)/reports/regression/"

open_report "$SCOREBOARD"
exit "$REG_RC"
