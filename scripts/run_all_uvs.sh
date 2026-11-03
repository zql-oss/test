#!/usr/bin/env bash
###############################################################################
# run_all_uvs.sh — One-click UVS flow for the L2 cache project
#   Mirror of scripts/run_all_vcs.sh; both consume the same run list produced
#   by scripts/regression/plan_runs.py (same tests/seeds/timeouts/plusargs).
#
#   1. build DPI lib          (tb/dpi/ecc_inject.so, uses UVS_HOME/include)
#   2. compile once with uvs (functional + code coverage switches -cov ...)
#   3. run every entry in scripts/regression/test_plan.yaml (num_seeds each)
#   4. merge all .cdb with uvcov -> reports/coverage/merged
#
# Usage (with UVS 2026.06.P2 and UV_LICENSE set):
#   bash scripts/run_all_uvs.sh                 # full plan
#   SEEDS=1 bash scripts/run_all_uvs.sh         # cap seeds/test (fast smoke)
#   TAG=ci bash scripts/run_all_uvs.sh          # tag-filtered subset
#   JOBS=16 bash scripts/run_all_uvs.sh         # parallel simulation
#   WAVES=1 bash scripts/run_all_uvs.sh         # also dump USDB waves
###############################################################################
set -uo pipefail
cd "$(dirname "$0")/.."                      # repo root

# UVS environment (non-interactive shells do not source ~/.bashrc)
export UVS_HOME=${UVS_HOME:?set UVS_HOME to the UVS installation root}
export UV_LICENSE=${UV_LICENSE:?set UV_LICENSE (port@license-server)}
export PATH="$UVS_HOME/bin:$PATH"

CM=${CM:-stmt,cond,fsm,tgl,assert,group}      # UVS -cov metrics
SIMOUT=sim/uvs/l2_cache_top_sim               # UVS executable
CDB_ROOT=sim/uvs/coverage                     # per-test coverage DB dirs
RPT_DIR=reports/coverage/merged
LOG_DIR=reports/regression
RESULTS=reports/regression/run_summary.txt
STATUS_DIR=reports/regression/.run_status
PLAN=${PLAN:-scripts/regression/test_plan.yaml}
JOBS=${JOBS:-8}
WAVES=${WAVES:-0}

mkdir -p "$CDB_ROOT" "$LOG_DIR" reports/coverage
rm -rf "$CDB_ROOT"; mkdir -p "$CDB_ROOT"
rm -rf "$STATUS_DIR"; mkdir -p "$STATUS_DIR"

echo "=== [1/4] DPI lib ===================================================="
UVS_INC=${UVS_HOME}/include
gcc -shared -fPIC -O2 -I"$UVS_INC" tb/dpi/ecc_inject.c \
    -o tb/dpi/ecc_inject.so \
    || { echo "DPI build failed: check svdpi.h under $UVS_INC"; exit 1; }
echo ">>> DPI lib: tb/dpi/ecc_inject.so"

echo "=== [2/4] UVS compile (coverage on) =================================="
WAVE_CFLAGS=""
[ "$WAVES" = 1 ] && WAVE_CFLAGS="-debug -usdbon"
uvs -sv -uvm1.2 -debug assert \
    -timescale 1ns/1ps \
    -file sim/uvs/uvs_filelist.f \
    -cov "$CM" \
    $WAVE_CFLAGS \
    -sv_lib tb/dpi/ecc_inject.so \
    -o "$SIMOUT" \
    -logfile "$LOG_DIR/compile.log" || { echo "COMPILE FAILED"; exit 1; }
grep -E "Compilation: .*error" "$LOG_DIR/compile.log" | tail -1 || true

echo "=== [3/4] Run the plan ==============================================="
RUNS=$(mktemp /tmp/uvs_runs.XXXXXX)
python3 scripts/regression/plan_runs.py \
    --plan "$PLAN" \
    --seeds-cap "${SEEDS:-0}" \
    --tag "${TAG:-}" \
    --timeout-override "${TIMEOUT_S:-0}" > "$RUNS"
echo ">>> $(wc -l < "$RUNS") runs from $PLAN"

run_one() {                                    # rid class seed timeout plusargs
    local rid=$1 tc=$2 seed=$3 to=$4 pa=$5
    local cdb="$CDB_ROOT/${rid}_s${seed}.cdb"
    local log="$LOG_DIR/${rid}_s${seed}.log"
    local wave_arg=""
    [ "${WAVES:-0}" = 1 ] && wave_arg="-usdbon"
    rm -rf "$cdb"
    timeout "$to" "$SIMOUT" \
        +UVM_TESTNAME="$tc" -fixed_seed "$seed" \
        $pa \
        $wave_arg \
        -cov "$CM" -covdir "$cdb" -covtest "${rid}_s${seed}" \
        -logfile "$log" > /dev/null 2>&1
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
export SIMOUT CDB_ROOT LOG_DIR CM WAVES STATUS_DIR

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

echo "=== [4/4] Coverage merge (uvcov) ====================================="
rm -rf "$RPT_DIR" reports/coverage/merged.cdb
CDB_FILE=/tmp/uvs_cdb_list.$$
{
    echo "sim/uvs/l2_cache_top_sim.cdb"
    find "$CDB_ROOT" -maxdepth 1 -name '*.cdb' | sort
} > "$CDB_FILE"
[ "$(wc -l < "$CDB_FILE")" -le 1 ] && { rm -f "$CDB_FILE"; echo "UVCOV FAILED: no cdb found in $CDB_ROOT"; exit 1; }
uvcov -dbfile "$CDB_FILE" \
    -mdb reports/coverage/merged.cdb \
    -reportdir "$RPT_DIR" \
    | tee reports/coverage/uvcov.log || { rm -f "$CDB_FILE"; echo "UVCOV FAILED"; exit 1; }
rm -f "$CDB_FILE"

echo "DONE. Coverage report: $RPT_DIR"
[ "$PASS_N" -eq "$TOT_N" ]
