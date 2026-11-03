#!/usr/bin/env bash
###############################################################################
# run_all_vcs.sh — One-click VCS flow for the L2 cache project
#
#   Mirror of scripts/run_all_uvs.sh; both consume the same run list produced
#   by scripts/regression/plan_runs.py (same tests/seeds/timeouts/plusargs).
#
#   1. build DPI lib          (tb/dpi/ecc_inject.so, uses VCS_HOME/include)
#   2. compile once with VCS  (-cm line+cond+fsm+tgl+branch+assert)
#   3. run every entry in scripts/regression/test_plan.yaml (num_seeds each)
#   4. merge all .vdb with urg -> reports/coverage/merged (HTML + text)
#
# Coverage mapping vs UVS:
#   UVS -cov stmt,cond,fsm,tgl,assert,group
#     -> VCS -cm line+cond+fsm+tgl+branch+assert
#        (branch is counted inside UVS stmt; covergroups are collected by VCS
#         whenever -cm is enabled, so UVS "group" has no separate switch)
#
# Usage (after sourcing the VCS environment, e.g. source ~/.bashrc):
#   bash scripts/run_all_vcs.sh                 # full plan
#   SEEDS=1 bash scripts/run_all_vcs.sh         # cap seeds/test (fast smoke)
#   TAG=ci bash scripts/run_all_vcs.sh          # tag-filtered subset
#   JOBS=16 bash scripts/run_all_vcs.sh         # parallel simulation
#   WAVES=1 bash scripts/run_all_vcs.sh         # also dump VCD waves
###############################################################################
set -uo pipefail
cd "$(dirname "$0")/.."                      # repo root

# ── VCS environment ──────────────────────────────────────────────────────────
if ! command -v vcs >/dev/null 2>&1; then
    echo "ERROR: 'vcs' not found. Source your VCS environment first"
    echo "       (e.g. source /path/to/vcs/setup.sh or ~/.bashrc)."
    exit 1
fi
if ! command -v urg >/dev/null 2>&1; then
    echo "ERROR: 'urg' not found. VCS coverage merge requires the VCS/URG tools."
    exit 1
fi
VCS_HOME=${VCS_HOME:-$(dirname "$(dirname "$(command -v vcs)")")}
export VCS_HOME

CM=${CM:-line+cond+fsm+tgl+branch+assert}    # VCS -cm metrics
SIMOUT=sim/vcs/l2_cache_top_sim              # VCS executable
VDB_ROOT=sim/vcs/coverage                    # per-test coverage DB dirs
RPT_DIR=reports/coverage/merged
LOG_DIR=reports/regression
RESULTS=reports/regression/run_summary.txt
STATUS_DIR=reports/regression/.run_status
PLAN=${PLAN:-scripts/regression/test_plan.yaml}
JOBS=${JOBS:-8}
WAVES=${WAVES:-0}

mkdir -p "$VDB_ROOT" "$LOG_DIR" reports/coverage waves
rm -rf "$VDB_ROOT"; mkdir -p "$VDB_ROOT"
rm -rf "$STATUS_DIR"; mkdir -p "$STATUS_DIR"

echo "=== [1/4] DPI lib ===================================================="
gcc -shared -fPIC -O2 -I"$VCS_HOME/include" tb/dpi/ecc_inject.c \
    -o tb/dpi/ecc_inject.so \
    || { echo "DPI build failed: check svdpi.h under $VCS_HOME/include"; exit 1; }
echo ">>> DPI lib: tb/dpi/ecc_inject.so"

echo "=== [2/4] VCS compile (coverage on) =================================="
WAVE_CFLAGS=""
[ "$WAVES" = 1 ] && WAVE_CFLAGS="-debug_access+all"
vcs -full64 -sverilog -ntb_opts uvm-1.2 -assert svaext \
    +vcs+lic+wait \
    -f sim/vcs/vcs_filelist.f \
    -cm "$CM" \
    $WAVE_CFLAGS \
    -o "$SIMOUT" -Mdir=sim/vcs/csrc \
    -l "$LOG_DIR/compile.log" || { echo "COMPILE FAILED"; exit 1; }
grep -E "Error-|Compilation" "$LOG_DIR/compile.log" | tail -3 || true

echo "=== [3/4] Run the plan ==============================================="
RUNS=$(mktemp /tmp/vcs_runs.XXXXXX)
python3 scripts/regression/plan_runs.py \
    --plan "$PLAN" \
    --seeds-cap "${SEEDS:-0}" \
    --tag "${TAG:-}" \
    --timeout-override "${TIMEOUT_S:-0}" > "$RUNS"
echo ">>> $(wc -l < "$RUNS") runs from $PLAN"

run_one() {                                    # rid class seed timeout plusargs
    local rid=$1 tc=$2 seed=$3 to=$4 pa=$5
    local vdb="$VDB_ROOT/${rid}_s${seed}.vdb"
    local log="$LOG_DIR/${rid}_s${seed}.log"
    local wave_arg=""
    [ "${WAVES:-0}" = 1 ] && wave_arg="+DUMP_WAVES"
    rm -rf "$vdb"
    timeout "$to" "$SIMOUT" \
        +UVM_TESTNAME="$tc" +ntb_random_seed="$seed" \
        $pa \
        $wave_arg \
        -sv_lib tb/dpi/ecc_inject \
        -cm "$CM" -cm_dir "$vdb" -cm_name "${rid}_s${seed}" \
        -l "$log" > /dev/null 2>&1
    local rc=$?
    local status
    if [ $rc -eq 124 ]; then
        status=TIMEOUT
    elif [ ! -s "$log" ] || ! grep -qE '^[[:space:]]*UVM_(ERROR|FATAL)[[:space:]]*:' "$log"; then
        status=NORUN
    else
        local err fat
        err=$(grep -E '^[[:space:]]*UVM_ERROR[[:space:]]*:' "$log" | tail -1 | sed 's/.*:[[:space:]]*//' | tr -dc '0-9')
        fat=$(grep -E '^[[:space:]]*UVM_FATAL[[:space:]]*:' "$log" | tail -1 | sed 's/.*:[[:space:]]*//' | tr -dc '0-9')
        if [ "${fat:-0}" -gt 0 ]; then status=FATAL
        elif [ "${err:-0}" -gt 0 ]; then status=FAIL
        else status=PASS; fi
    fi
    printf '%-8s %s seed=%s\n' "$status" "$rid" "$seed" > "$STATUS_DIR/${rid}_s${seed}.txt"
}
export -f run_one
export SIMOUT VDB_ROOT LOG_DIR CM WAVES STATUS_DIR

while IFS=$'\t' read -r rid tc seed to pa; do
    run_one "$rid" "$tc" "$seed" "$to" "$pa" &
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
done < "$RUNS"
wait
rm -f "$RUNS"
cat "$STATUS_DIR"/*.txt | sort -k2,2 -k3,3V > "$RESULTS"

echo "--- non-PASS runs -----------------------------------------------------"
grep -v '^PASS' "$RESULTS" || true
echo "--- summary -----------------------------------------------------------"
awk '{print $1}' "$RESULTS" | sort | uniq -c
PASS_N=$(grep -c '^PASS' "$RESULTS" || true)
TOT_N=$(wc -l < "$RESULTS")
echo "=== $PASS_N/$TOT_N runs PASS ==="

echo "=== [4/4] Coverage merge (urg) ======================================="
rm -rf "$RPT_DIR"
VDB_N=$(find "$VDB_ROOT" -maxdepth 1 -name '*.vdb' | wc -l)
if [ "$VDB_N" -eq 0 ]; then
    echo "URG FAILED: no .vdb found in $VDB_ROOT"; exit 1
fi
urg -dir "$VDB_ROOT" -format both -report "$RPT_DIR" \
    -log reports/coverage/urg.log \
    | tee reports/coverage/urg_stdout.log | tail -15 || { echo "URG FAILED"; exit 1; }

echo "DONE. Coverage dashboard: $RPT_DIR/dashboard.html"
[ "$PASS_N" -eq "$TOT_N" ]
