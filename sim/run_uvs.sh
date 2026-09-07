#!/bin/bash
# 一键 UVS 流程: inst.data -> uvs 编译 -> uvsim 仿真 -> uvcov 覆盖率报告
# 用法: ./run_uvs.sh [bin文件路径]   (默认 ../tests/isa/generated/rv32ui-p-simple.bin)
# 需保证 uvs / uvsim / uvcov 在 PATH 中, 从 sim/ 目录执行或由脚本自行切换
set -e
cd "$(dirname "$0")"

BIN=${1:-../tests/isa/generated/rv32ui-p-simple.bin}
EXT=${BIN##*.}

# 1. 生成 inst.data
if [ "$EXT" = "bin" ]; then
    python ../tools/BinToMem_CLI.py "$BIN" inst.data
else
    cp "$BIN" inst.data
fi

# 2. uvs 编译 (SIM_TOOL=uvs 走 compile_rtl.py 的 uvs 分支)
export SIM_TOOL=uvs
python compile_rtl.py ..

# 3. uvsim 仿真 (含覆盖率收集)
TESTNAME=$(basename "$BIN" | sed 's/\..*$//')
./uvsim -cov stmt,cond,tgl,fsm,assert -covtest "$TESTNAME" -logfile run_uvs.log
RESULT=$(grep -oE "TEST_PASS|TEST_FAIL|Time Out" run_uvs.log | head -1)
ENDTIME=$(grep -oE "at time [0-9]+ ps" run_uvs.log | grep -oE "[0-9]+")
echo "Result: ${RESULT:-unknown}   End time: ${ENDTIME:-unknown} ps"
echo "Run log: sim/run_uvs.log"

# 4. uvcov 覆盖率报告
rm -rf cov_report
uvcov --db uvsim.cdb --cov stmt,cond,tgl,fsm,assert --reportdir cov_report 2>&1 | grep -E "Complete|error" || true
echo "Coverage report: sim/cov_report/dashboard.html"