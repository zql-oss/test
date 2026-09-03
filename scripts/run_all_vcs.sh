#!/usr/bin/env bash
###############################################################################
# run_all_vcs.sh — One-click VCS flow for the L2 cache project
#   1. build DPI lib          (tb/dpi/libecc_inject.so)
#   2. compile once with functional coverage switches (-cm ...)
#   3. run EVERY test in scripts/regression/test_plan.yaml (num_seeds each)
#   4. merge all .vdb with urg -> reports/coverage/merged/dashboard.html
#
# Usage (on a machine with VCS 2023.03+ and a license):
#   bash scripts/run_all_vcs.sh                 # full plan (47 tests)
#   SEEDS=1 bash scripts/run_all_vcs.sh         # cap seeds/test (fast smoke)
#   JOBS=8 bash scripts/run_all_vcs.sh          # parallel simulation
#   WAVES=1 bash scripts/run_all_vcs.sh         # also dump VPD waves
###############################################################################
set -uo pipefail
cd "$(dirname "$0")/.."                      # repo root

CM=${CM:-line+cond+fsm+tgl+branch+assert}
SIMOUT=sim/vcs/l2_cache_top_sim
VDB_ROOT=sim/vcs/coverage
RPT_DIR=reports/coverage/merged
LOG_DIR=reports/regression
RESULTS=reports/regression/run_summary.txt
SEEDS_CAP=${SEEDS:-}                          # empty = use plan's num_seeds
JOBS=${JOBS:-1}
WAVES=${WAVES:-0}
TIMEOUT_S=${TIMEOUT_S:-1800}

mkdir -p "$VDB_ROOT" "$LOG_DIR" reports/coverage

echo "=== [1/4] DPI lib ===================================================="
if [ ! -f tb/dpi/libecc_inject.so ]; then
    VCS_INC=${VCS_HOME:-$(dirname "$(dirname "$(command -v vcs)")")}/include
    gcc -shared -fPIC -O2 -I"$VCS_INC" tb/dpi/ecc_inject.c \
        -o tb/dpi/libecc_inject.so \
        || { echo "DPI build failed: set VCS_HOME (svdpi.h not found)"; exit 1; }
fi

echo "=== [2/4] VCS compile (coverage on) =================================="
WAVE_CFLAGS=""
[ "$WAVES" = 1 ] && WAVE_CFLAGS="-debug_access+all"
vcs -full64 -sverilog -ntb_opts uvm-1.2 -assert svaext \
    -timescale=1ns/1ps +vcs+lic+wait \
    -f sim/vcs/vcs_filelist.f \
    -cm "$CM" \
    $WAVE_CFLAGS \
    -o "$SIMOUT" -Mdir=sim/vcs/csrc \
    -l "$LOG_DIR/compile.log" || { echo "COMPILE FAILED"; exit 1; }

echo "=== [3/4] Run all tests =============================================="
# test_class num_seeds per line
mapfile -t TESTS < <(python3 - <<'PY'
import os, yaml
plan = yaml.safe_load(open("scripts/regression/test_plan.yaml"))
cap  = os.environ.get("SEEDS_CAP", "")
for t in plan["tests"]:
    n = int(t.get("num_seeds", plan["global"].get("default_seeds", 3)))
    if cap:
        n = min(n, int(cap))
    print(t["test_class"], n)
PY
)

run_one() {                                    # $1=test_class $2=seed
    local tc=$1 seed=$2
    local vdb="$VDB_ROOT/${tc}_s${seed}.vdb"
    local log="$LOG_DIR/${tc}_${seed}.log"
    local wave_arg=""
    [ "${WAVES:-0}" = 1 ] && wave_arg="+DUMP_WAVES"
    rm -rf "$vdb"
    timeout "$TIMEOUT_S" "$SIMOUT" \
        +UVM_TESTNAME="$tc" +ntb_random_seed="$seed" +UVM_VERBOSITY=UVM_MEDIUM \
        $wave_arg \
        -sv_lib tb/dpi/ecc_inject \
        -cm "$CM" -cm_dir "$vdb" \
        -l "$log" > /dev/null 2>&1
    local rc=$?
    if   [ $rc -eq 124 ]; then echo "TIMEOUT  $tc seed=$seed"
    elif grep -qE "UVM_FATAL[ :]" "$log" 2>/dev/null; then echo "FATAL    $tc seed=$seed"
    elif ! grep -qE "UVM_ERROR\s*:\s*0" "$log" 2>/dev/null; then echo "NORUN    $tc seed=$seed (no UVM summary — simv died before test end)"
    elif grep -E "UVM_ERROR\s*:\s*[1-9]" "$log" >/dev/null 2>&1; then echo "FAIL     $tc seed=$seed"
    else echo "PASS     $tc seed=$seed"; fi
}
export -f run_one
export SIMOUT VDB_ROOT LOG_DIR CM TIMEOUT_S WAVES

# "tc seed" lines -> parallel runs, one summary line per run
for entry in "${TESTS[@]}"; do
    set -- $entry
    for seed in $(seq 1 "$2"); do echo "$1 $seed"; done
done | xargs -P "$JOBS" -L1 bash -c 'run_one "$1" "$2"' _ \
     | tee "$RESULTS" | grep -v '^PASS' || true

echo "--- summary (full list in $RESULTS) ---"
sort -k2 "$RESULTS"
PASS_N=$(grep -c '^PASS' "$RESULTS" || true)
TOT_N=$(wc -l < "$RESULTS")
echo "=== $PASS_N/$TOT_N runs PASS ==="

echo "=== [4/4] Coverage merge (urg) ======================================="
rm -rf "$RPT_DIR"
urg -dir "$VDB_ROOT" -format both -report "$RPT_DIR" \
    | tee reports/coverage/urg.log | tail -15 || { echo "URG FAILED"; exit 1; }

echo "DONE. Coverage dashboard: $RPT_DIR/dashboard.html"
[ "$PASS_N" -eq "$TOT_N" ]
