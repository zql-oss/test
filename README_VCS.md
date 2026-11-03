# L2 Cache UVM — VCS 回归与覆盖率包

本包是 `17-l2_cache_RTL_FV_TB_UVM_DFT` 的 VCS 交付快照。源码、test plan、
seed、plusargs、timeout 与 UVS 侧完全一致；VCS 与 UVS 两个一键脚本共用
`scripts/regression/plan_runs.py` 生成的同一份 run list。

## 1. 已验证的 UVS 基线

- 工具：UVS 2026.06.P2.Beta，`JOBS=16 bash scripts/run_all_uvs.sh`
- 计划：47 个 test 条目，展开 200 次仿真
- 结果：**190/200 PASS，10 FATAL**（均为既有 RTL 场景超时，不是迁移回归）
- 覆盖率（uvcov 合并 201 个 DB）：stmt 42.84%、cond 26.48%、tgl 25.88%、
  assert 29.69%、fsm 23.26%、group 13.00%，等权 total 26.86%

基线明细在 `reports/uvs_baseline/`。

## 2. 一条命令跑回归并打开 scoreboard

把目录拷到任意机器（路径可任意），装好 VCS/URG 和 PyYAML 后：

```bash
./run_vcs.sh
```

它会依次完成：

1. 编译 DPI + VCS（`-cm` 覆盖率插桩）
2. 按 test plan 跑完 200 个 run（`JOBS=16 ./run_vcs.sh` 可并行）
3. 生成 `reports/regression/scoreboard.html`（每个 run 的 PASS/FATAL/FAIL、
   UVM_ERROR/FATAL/WARNING 计数、首条失败信息、日志链接）
4. 生成 `reports/coverage/merged/dashboard.html`（URG 覆盖率）
5. 自动用浏览器打开 scoreboard；无 DISPLAY 时打印 `file://` 路径

常用变体：

```bash
SEEDS=1 ./run_vcs.sh            # 冒烟
JOBS=16 ./run_vcs.sh            # 16 路并行
TAG=ci ./run_vcs.sh             # 只跑 ci 标签
NO_OPEN=1 ./run_vcs.sh          # 不自动开浏览器
make run                        # 等价于 ./run_vcs.sh
```

scoreboard 顶部有状态统计、过滤框和 per-test 汇总；点每行 `log` 可看完整
UVM 日志，点 `Coverage dashboard` 进入覆盖率报告。回归有失败时命令返回
非 0（与 UVS 基线一致的 10 个 FATAL 也会返回 1）。

## 3. 环境要求

- Synopsys VCS **O-2018.09+**（推荐 2023.03+）与 URG，含有效 license
- `gcc`、`python3`、PyYAML（`pip install pyyaml`）
- `VCS_HOME` 指向 VCS 安装根目录（需存在 `$VCS_HOME/include/svdpi.h`）

```bash
source /path/to/vcs/setup.sh        # 或 source ~/.bashrc
cd l2_cache_RTL_FV_TB_UVM_DFT
bash scripts/check_vcs_env.sh
```

## 4. 一键回归 + 覆盖率

```bash
# 全量：47 个 plan 条目 / 200 runs
bash scripts/run_all_vcs.sh

# 快速冒烟
SEEDS=1 bash scripts/run_all_vcs.sh

# 只跑带 ci 标签的条目
TAG=ci JOBS=8 bash scripts/run_all_vcs.sh

# 并行 + VCD 波形
JOBS=16 WAVES=1 bash scripts/run_all_vcs.sh
```

可用环境变量：

| 变量 | 默认 | 说明 |
|---|---|---|
| `JOBS` | 8 | 并行仿真数 |
| `SEEDS` | 0（不限） | 每个 plan 条目的 seed 上限 |
| `TAG` | 空 | 只跑带该 tag 的条目 |
| `TIMEOUT_S` | 0（用 plan） | 覆盖每个 run 的墙钟超时 |
| `WAVES` | 0 | 1 = 生成 `waves/l2_cache.vcd` |
| `CM` | `line+cond+fsm+tgl+branch+assert` | VCS 覆盖率指标 |
| `PLAN` | `scripts/regression/test_plan.yaml` | 测试计划 |

流程：

1. 用 `$VCS_HOME/include/svdpi.h` 重新编译 `tb/dpi/ecc_inject.so`
2. `vcs -full64 -sverilog -ntb_opts uvm-1.2 -assert svaext -cm ...`
3. 按 plan 顺序展开 run list，逐个 `simv`，每个 run 独立 `.vdb`、日志、
   `+ntb_random_seed`、`+UVM_TESTNAME`、plan 里的 plusargs 与 timeout
4. `urg -dir sim/vcs/coverage -format both -report reports/coverage/merged`

输出：

```
reports/regression/run_summary.txt     # PASS/FATAL/FAIL/TIMEOUT/NORUN 逐条统计
reports/regression/compile.log         # VCS 编译日志
reports/regression/tNNN_*_sN.log       # 每个 run 的 UVM 日志
reports/coverage/merged/dashboard.html # URG HTML（line/cond/fsm/tgl/branch/assert/group）
reports/coverage/urg.log               # URG 文本日志
```

## 5. Makefile 入口

```bash
make run                   # 回归 + scoreboard + 覆盖率（等价 ./run_vcs.sh）
make sim TEST=l2_smoke_read_test SEED=1 COV=1 WAVES=1
make regression            # 委托给 scripts/run_all_vcs.sh
make regression_ci         # TAG=ci，SEEDS=1
make regression_nightly    # SEEDS=10，JOBS=16
make cov_all               # 回归 + urg 合并
```

`TOOL=vcs` 为默认值；`TOOL=xcelium` 保留原 Python 回归路径。

## 6. 覆盖率 1:1 对应关系

| UVS | VCS | 说明 |
|---|---|---|
| `-cov stmt` | `-cm line` | 语句/行覆盖 |
| `-cov cond` | `-cm cond` | 条件覆盖 |
| `-cov fsm` | `-cm fsm` | 状态机覆盖 |
| `-cov tgl` | `-cm tgl` | 翻转覆盖 |
| `-cov assert` | `-cm assert` | SVA/断言覆盖 |
| `-cov group` | VCS 默认收集 | covergroup 无需单独开关 |
| `-cov stmt` 内含分支 | `-cm branch` | 单独列出 branch，粒度更细 |
| `uvcov -dbfile ... -mdb ...` | `urg -dir ... -format both -report ...` | 合并/报告 |

注意：两个工具的计数规则和插桩范围不同，**覆盖率百分比不会逐位相同**；
应在同一 run list 下按 metric 对比，而不是要求数字相等。

## 7. 期望结果与已知失败

预期与 UVS 基线一致：**190/200 PASS**，10 个 FATAL：

```
t022_l2_simultaneous_flush_miss seed=1..3
t045_l2_simultaneous_flush_miss seed=1..3   (plan 中重复条目)
t033_l2_power_flush             seed=1..3
t034_l2_power_domain_iso        seed=1
```

这些 run 都在 `TB_TOP: Simulation timeout at 10000000000` 结束，属于既有 RTL
场景未收敛；`docs/uvs_migration_report.md` 记录的 VCS 基线也是同一失败集合。
如果 VCS 出现其它失败，优先检查：UVM 版本是否为 1.2、`-assert svaext` 是否
使能、DPI `.so` 是否由本机 `$VCS_HOME/include` 重建、timescale 是否 1ns/1ps。

逐条对比 VCS 与 UVS 基线（run ID / seed / 状态）：

```bash
python3 scripts/compare_results.py
# VCS: reports/regression/run_summary.txt
# UVS: reports/uvs_baseline/run_summary.txt
# 输出 MATCH 表示 200 个 run 的状态完全一致
```

## 8. 目录说明

```
run_vcs.sh                    一条命令：回归 + scoreboard + 覆盖率 + 打开浏览器
rtl/                          RTL（含 UVS 迁移期间的 v48 功能修复）
tb/uvm_tb/                    UVM agents / env / sequences / scoreboard / coverage
tb/top/l2_cache_tb_top.sv     TB top（portable VCD dump，DUMP_WAVES plusarg）
tb/dpi/ecc_inject.c           ECC 故障注入 DPI（VCS 侧现场编译）
sim/vcs/vcs_filelist.f        VCS 编译源清单（与 UVS filelist 同源文件集）
sim/waves/                    Verdi/VCS 波形配置
scripts/run_all_vcs.sh        VCS 回归 + urg 覆盖率（底层脚本）
scripts/run_all_uvs.sh        UVS 回归（对照用）
scripts/regression/plan_runs.py      UVS/VCS 共用的 run list 展开器
scripts/regression/make_scoreboard.py 由 run_summary + 日志生成 scoreboard.html
scripts/regression/test_plan.yaml   47 个条目 / 200 runs
scripts/compare_results.py    VCS 结果 vs UVS 基线逐 run 对比
reports/uvs_baseline/         UVS 基线结果与覆盖率摘要
```

## 9. 已知限制

- 打包环境没有 VCS/URG 安装与 license，因此 **VCS 命令未在本机实际执行**；
  已完成：VCS 文件清单/路径校验、`bash -n`、Python 语法检查、用 stub
  `vcs`/`simv`/`urg` 跑通 200-run 编排与统计/覆盖率输出。首次在 VCS 机器上
  运行时若遇到环境差异，按第 6 节的检查项定位。
- test plan 中 `t022`/`t045`、`t042` 等是重复条目（同一 class 不同/相同配置），
  脚本按 plan 原样执行，因此总数是 200 而不是 180。若要“每 class 一次”，
  先清理 `test_plan.yaml`。
- UVS 迁移时为规避 UVS clocking-block 采样问题，monitor 改为 raw wire 采样；
  这些是可移植 SV，但两个工具的 cycle 级时序可能有细微差异，功能判定以
  scoreboard / ref model 为准。
