#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

UVS_HOME=${UVS_HOME:?set UVS_HOME to the UVS installation root}
UV_LICENSE=${UV_LICENSE:?set UV_LICENSE (port@license-server)}
export UVS_HOME UV_LICENSE
export PATH="$UVS_HOME/bin:$PATH"

TEST=${TEST:-l2_smoke_read_test}
SEED=${SEED:-1}
VERBOSITY=${VERBOSITY:-UVM_MEDIUM}
WAVES=${WAVES:-0}
COV=${COV:-1}
TIMEOUT_S=${TIMEOUT_S:-1800}
CM_OPTS="stmt,cond,fsm,tgl,assert,group"

SIMOUT=sim/uvs/l2_cache_top_sim_smoke
COVDIR=sim/uvs/coverage_smoke/${TEST}_s${SEED}.cdb
DPI_SO=sim/uvs/dpi/ecc_inject.so
LOG_DIR=logs/uvs_smoke
COMPILE_LOG=$LOG_DIR/compile.log
SIM_LOG=$LOG_DIR/${TEST}_${SEED}.log

mkdir -p "$LOG_DIR" "$(dirname "$DPI_SO")" "$(dirname "$COVDIR")"
rm -rf "$SIMOUT" "$SIMOUT.db" "$SIMOUT.cdb" "$COVDIR"

echo "=== [1/3] DPI lib ===================================================="
gcc -shared -fPIC -O2 -I"$UVS_HOME/pli_incs" tb/dpi/ecc_inject.c -o "$DPI_SO"
echo ">>> DPI lib: $DPI_SO"

echo "=== [2/3] UVS compile ================================================"
if [ "$WAVES" = 1 ]; then
    DEBUG_OPT=(-debug all)
else
    DEBUG_OPT=(-debug assert)
fi
COV_CFLAGS=()
COV_SIM=()
if [ "$COV" = 1 ]; then
    COV_CFLAGS=(-cov "$CM_OPTS")
    COV_SIM=(-cov "$CM_OPTS" -covdir "$COVDIR" -covtest "${TEST}_s${SEED}")
fi

uvs -sv -uvm1.2 \
    "${DEBUG_OPT[@]}" \
    -timescale 1ns/1ps \
    -file sim/uvs/uvs_filelist_smoke.f \
    "${COV_CFLAGS[@]}" \
    -sv_lib "$DPI_SO" \
    -o "$SIMOUT" \
    -logfile "$COMPILE_LOG"

echo "=== [3/3] UVS smoke run: $TEST seed=$SEED ==========================="
set +e
timeout "$TIMEOUT_S" "$SIMOUT" \
    +UVM_TESTNAME="$TEST" \
    -fixed_seed "$SEED" \
    +UVM_VERBOSITY="$VERBOSITY" \
    "${COV_SIM[@]}" \
    -logfile "$SIM_LOG"
rc=$?
set -e

echo "=== Summary =========================================================="
COMP_ERR=$(grep -cE '^Error-|^Error[[:space:]]' "$COMPILE_LOG" || true)
COMP_WARN=$(grep -cE '^Warning-|^Warning[[:space:]]' "$COMPILE_LOG" || true)
UVM_ERR=$(grep -E '^UVM_ERROR[[:space:]]*:' "$SIM_LOG" | tail -1 | awk '{print $3}' || true)
UVM_FATAL=$(grep -E '^UVM_FATAL[[:space:]]*:' "$SIM_LOG" | tail -1 | awk '{print $3}' || true)
echo "compile: error=$COMP_ERR warning=$COMP_WARN"
echo "runtime: UVM_ERROR=${UVM_ERR:-NA} UVM_FATAL=${UVM_FATAL:-NA} exit=$rc"
grep -E '^UVM_(ERROR|FATAL|WARNING)[[:space:]]*:|\* There were|Simulation completes|\$finish' "$SIM_LOG" | tail -10 || true

if [ "$rc" -ne 0 ]; then
    echo "RESULT: FAIL (exit=$rc)"
    exit "$rc"
fi
if [ "${UVM_ERR:-1}" != "0" ] || [ "${UVM_FATAL:-1}" != "0" ]; then
    echo "RESULT: FAIL (UVM_ERROR=${UVM_ERR:-NA} UVM_FATAL=${UVM_FATAL:-NA})"
    exit 1
fi
echo "RESULT: PASS"
