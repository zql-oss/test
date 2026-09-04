#!/usr/bin/env bash
# One-shot riscv-dv VCS flow with code coverage.
# Usage: ./run_cov.sh [test_name] [iterations]
#   default test: riscv_arithmetic_basic_test, iterations: 3
#
# Handles two baseline blockers:
#   1) Ubuntu jammy gcc-riscv64-unknown-elf (10.2) rejects
#      -march=rv32imc_zicsr_zifencei  ->  uses xPack RISC-V GCC 13.x
#   2) VCS needs -cm <types> at compile time, --cov alone only adds
#      -cm_dir (no .vdb produced)     ->  injects --cmp_opts "-cm ..."
#
# Requires: VCS (urg), python3, wget/tar (only if GCC needs downloading).
set -euo pipefail
cd "$(dirname "$0")"

TEST="${1:-riscv_arithmetic_basic_test}"
ITER="${2:-3}"

TOOL_DIR="$(cd .. && pwd)/tools"
GCC_VER="13.2.0-3"
GCC_DIR="$TOOL_DIR/xpack-riscv-none-elf-gcc-$GCC_VER-linux-x64"
GCC_URL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$GCC_VER/xpack-riscv-none-elf-gcc-$GCC_VER-linux-x64.tar.gz"
COV_TYPES="line+cond+tgl+branch"

# ---- [1/4] toolchain -------------------------------------------------------
# Accept RISCV_GCC only if it is a GCC >= 12 (old < 12 cannot parse
# '-march=rv32imc_zicsr_zifencei', e.g. Ubuntu jammy ships 10.2).
# Fallback (no download, offline-friendly): keep the old GCC but pass
# '-march=rv32imc' via --isa so the zicsr/zifencei suffix is dropped.
gcc_ok() {
  "$1" --version 2>/dev/null | grep -qE '\b(1[2-9]|[2-9][0-9])\.'
}
ISA_ARGS=""
if [ -n "${RISCV_GCC:-}" ] && gcc_ok "$RISCV_GCC"; then
  echo "[1/4] RISCV_GCC=$RISCV_GCC (new enough, official march)"
else
  if [ -z "${RISCV_GCC:-}" ]; then
    export RISCV_GCC="riscv64-unknown-elf-gcc"
    export RISCV_OBJCOPY="riscv64-unknown-elf-objcopy"
  fi
  echo "[1/4] WARN: ${RISCV_GCC:-unset} is GCC<12, using downgraded -march=rv32imc"
  echo "      (upgrade later: xpack GCC 13.2 or any riscv GCC>=12, then unset RISCV_GCC)"
  ISA_ARGS="--isa rv32imc --mabi ilp32"
fi

# ---- [2/4] generate + simulate with coverage ------------------------------
echo "[2/4] run.py: $TEST x$ITER (vcs, -cm $COV_TYPES) $ISA_ARGS"
python3 run.py --test "$TEST" -i "$ITER" --cov \
  --cmp_opts "-cm $COV_TYPES" $ISA_ARGS

# ---- [3/4] locate .vdb -----------------------------------------------------
VDB="$(find out_* -type d -name '*.vdb' 2>/dev/null | sort | tail -1)"
if [ -z "$VDB" ]; then
  echo "ERROR: no .vdb found under out_* - did simulation run?" >&2
  exit 1
fi
echo "[3/4] VDB=$VDB"

# ---- [4/4] coverage report -------------------------------------------------
echo "[4/4] urg -> coverage_report/index.html"
rm -rf coverage_report
urg -dir "$VDB" -report coverage_report
echo "DONE. Open coverage_report/index.html"
