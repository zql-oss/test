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
gcc_ok() {
  "$1" --version 2>/dev/null | grep -qE '\b(1[2-9]|[2-9][0-9])\.'
}
if [ -n "${RISCV_GCC:-}" ] && gcc_ok "$RISCV_GCC"; then
  echo "[1/4] RISCV_GCC=$RISCV_GCC"
else
  if [ -n "${RISCV_GCC:-}" ]; then
    echo "[1/4] WARN: RISCV_GCC=$RISCV_GCC too old (<12), using xPack GCC instead"
  fi
  if [ ! -x "$GCC_DIR/bin/riscv-none-elf-gcc" ]; then
    echo "[1/4] Downloading xPack RISC-V GCC $GCC_VER ..."
    mkdir -p "$TOOL_DIR"
    if ! wget -q "$GCC_URL" -O "$TOOL_DIR/gcc.tar.gz"; then
      echo "ERROR: download failed, install a GCC>=12 toolchain and export RISCV_GCC" >&2
      exit 1
    fi
    tar xzf "$TOOL_DIR/gcc.tar.gz" -C "$TOOL_DIR"
    rm -f "$TOOL_DIR/gcc.tar.gz"
  fi
  export RISCV_GCC="$GCC_DIR/bin/riscv-none-elf-gcc"
  export RISCV_OBJCOPY="$GCC_DIR/bin/riscv-none-elf-objcopy"
  echo "[1/4] RISCV_GCC=$RISCV_GCC (xPack $GCC_VER)"
fi

# ---- [2/4] generate + simulate with coverage ------------------------------
echo "[2/4] run.py: $TEST x$ITER (vcs, -cm $COV_TYPES)"
python3 run.py --test "$TEST" -i "$ITER" --cov \
  --cmp_opts "-cm $COV_TYPES"

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
