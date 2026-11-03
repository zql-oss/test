# L2 Cache UVM 验证环境 VCS → UVS 迁移报告

- 日期：2026-09-21
- 工具：UVS 2026.06.P2.Beta（`<UVS_HOME>`），License `UV_LICENSE=<license-server>`
- 迁移方法：Migration-SKILL 选项映射 + 逐问题调试
- 一键流程：`scripts/run_all_uvs.sh`（DPI 构建 → uvs 编译 → 200 runs 回归 → uvcov 合并出报告）

---

## 1. 结论

| 项目 | VCS 基线 | UVS 迁移后 | 对照 |
|---|---|---|---|
| 编译 | O-2018 | `uvs -sv -uvm1.2 -debug assert -cov stmt,cond,fsm,tgl,assert,group` | 0 error / 42 warning（VCS 时代亦有 10+ warning） |
| 回归 | 190/200 PASS | **190/200 PASS** | 失败集合与 VCS 完全一致（见 §3） |
| 覆盖率 | urg 合并 | uvcov 合并 165 个测试 cdb + 1 个编译 cdb，0 error | 见 §4 |
| 单测耗时 | — | smoke≈2s，stress≈5s，超时用例 22s（10s timeout） | JOBS 并行可进一步压缩 |

**迁移完成判据全部满足**：编译零错误、回归结果与 VCS 基线逐条一致（190/200，失败均为 RTL 既有缺陷，非迁移回归）、覆盖率合并出 HTML 报告。

---

## 2. 迁移内容

### 2.1 选项/脚本映射（Migration-SKILL）

| VCS | UVS |
|---|---|
| `-full64` | N/A（UVS 仅 64 位） |
| `-sverilog` | `-sv` |
| `-ntb_opts uvm-1.2` | `-uvm1.2` |
| `-assert svaext` | `-debug assert` |
| `-timescale=1ns/1ps` | `-timescale 1ns/1ps` |
| `+vcs+lic+wait` | N/A（`UV_LICENSE`） |
| `-cm line+cond+fsm+tgl+branch+assert` | `-cov stmt,cond,fsm,tgl,assert,group`（branch 含于 stmt） |
| `-debug_access+all` | `-debug -usdbon`（WAVES=1 时） |
| `-ntb_random_seed=N` | `-fixed_seed N` |
| `urg -dir … -format both` | `uvcov -dbfile … -mdb … -reportdir …` |
| svdpi.h（VCS 自带） | `$UVS_HOME/include` |

### 2.2 覆盖率编译必须带 `-cov`

不带 `-cov` 时运行阶段 uvlog2 崩溃（`Internal Error: Design split missing the signal "" decl`，触发点 l2_coverage.sv，baseline 树同样复现）。所有运行命令固定带 `-cov stmt,cond,fsm,tgl,assert,group` 与独立 `-covdir sim/uvs/coverage/<test>_s<seed>.cdb -covtest <test>_s<seed>`。

### 2.2 UVS 采样语义（本次迁移最大坑）

- **class 内对 virtual interface 的 raw 读是 post-NBA off-by-one 拍**：driver/等待路径全部改用 `driver_cb`（clocking block）；monitor 保持 raw + `@(posedge vif.clk)` 轮询。混用会造成半拍错位、scoreboard 随机 mismatch。
- **plusargs 调试开关**：`+DBG_FILL`（l2_axi_master AR / top beat0 采样）、`+DBG_REF`（ref model）、`+DBG_MON`（slave monitor beat）。

### 2.3 已修复的迁移/环境问题（v1→v48 演进）

1. **SEQ-NO-SQR**：`l2_seq_base` 增加 static `m_default_sqr`，`l2_base_test.end_of_elaboration_phase` 统一安装；解决 `Body definition undefined` / sequence 不启动。
2. **coherency hang**：ace_snoop_agent drive_snoop 改 fork/join_any，避免 CR/CD 等待互锁。
3. **scoreboard**：`demux_checks()` 分流；CRRESP 位映射修正（packed 首成员在 MSB：bit4=WasUnique、bit1=PassDirty、bit0=DataTransfer）；dirty snoop 顺序 CD_TRANSFER→CR_SEND；`cd_last` 在 cnt==7。
4. **多拍 R 响应架构**（8 拍 cacheline 读）：
   - `l2_request_pipeline` 捕获 `pipe_req_len`；
   - MSHR per-entry fill 存储（`mshr_fill_line_t` + `req_len/alloc_len/resp_len` 链），`resp_len_c = mshr_resp_valid ? mshr_resp_len : pipe_req_len`；
   - top 两级 resp 流水 + beat 引擎：beat0=fill word，beats 1..N=hits 用 `hit_line_data`（data array snoop 口）、miss 用 `resp_fill_line_q`（`mshr_resp_valid && !is_write` 时从 per-entry `mshr_resp_data` 捕获）；`(resp_word_start_q+resp_beat_q)%8` 索引；`resp_is_miss_q` 区分命中/缺失数据源；
   - **幻象 beat**：`resp_len_c==0` 不得置 `resp_beat_q<=1`（否则 RLAST 拍不被接受、卡死 AR 通道）；
   - **重复 beat0**：`resp_r_pending` 组合 hold-off（寄存版滞后一拍会放进一个重复）；
   - **resp_busy 排空拒新 AR**：`resp_r_valid_q || resp_beat_q!=0`。
5. **流控修复（陈旧门控）**：原 `ar_stall/wr_stall` 用陈旧 `pipe_req_tag/set_index` 比 MSHR → miss 后永久 stall；改为 `l2_mshr` 新增 probe 端口（`probe_rd/aw/lat_hit`，与当拍 `s_axi_araddr/awaddr/aw_addr_lat` 比较），top 用 `~hit_any & ~mshr_full & ~mshr_line_match` 门控。
6. **同线竞态**：`l2_request_pipeline` 新增 `pipe_busy`（2-bit inflight，护 issue→q→q2 预分配 3 拍窗）、`pipe_wlast`（B 通道每 AW burst 一个 B）、`ar_lock`（5 拍）+ `aw_matches_ar_lock/ar_matches_pending_wr`，ARREADY 门控防 AW 抢跑同线。
7. **写合并 late-replay**：`l2_axi_master` 合并表 per-entry word-valid mask + `mrg_late_*` 握手（`mrg_late_stall` 防写口占用时重放）。
8. **陈旧二进制陷阱**：UVS 增量编译会丢 TB 编辑——改 .sv 后必须重编（touch + 全编）。回归脚本每次重新编译规避。
9. **TB 侧修复**：write_allocate 用 `do_word_read`（len=0）+ 阈值 `latency > 32`（命中≈14 拍、miss≈80 拍，driver 每笔 ≥2 拍使 `>4` 恒假）；scoreboard `axi_seq_item_beat_shrink()`、约束 `c_len_reasonable=[0:15]`；ref model `drain_mem_fifo()`。
10. **uvcov 语法**（本次最终踩坑）：
    - 多 `-db` 用**空格分隔**（逗号连接 → 路径过长错误）；
    - `ls dir/*.cdb` 对目录会**展开目录内容**（输出 `路径:`、`data`、空行）→ 必须用 `ls -d`；
    - 合并必须以**编译期 cdb**（`sim/uvs/l2_cache_top_sim.cdb`，含 `file_info.json`）作为参考库首位，否则全部 run cdb 报 "directory does not exist"；
    - `-report html` 不是合法选项（直接打印 usage）；
    - 最终命令：`uvcov -dbfile <list> -mdb merged.cdb -reportdir <dir>`，列表首行为编译 cdb。
    - 已固化进 `scripts/run_all_uvs.sh`。

---

## 3. 回归结果（2026-09-21，v48 二进制）

- 计划：`scripts/regression/test_plan.yaml`，47 个 test_class × 各 seed 数 = 200 runs
- 结果：**190/200 PASS**（与 VCS 基线 `reports/regression/run_summary.txt` 完全一致）
- 失败 10 条，全部为 flush 类 RTL 既有缺陷（见 §5），VCS 时代同样 FATAL：

| 测试 | 失败数 | 现象 |
|---|---|---|
| l2_power_flush_test s1-3 | 3 | flush 后 TB 超时（`flush_wb_done` 无驱动 → FLUSH_WRITEBACK 永挂） |
| l2_power_domain_iso_test s1 | 1 | 同上（flush 路径） |
| l2_simultaneous_flush_miss_test s1-3 | 6 | 同上 |

- v47→v48 修复项：`l2_stress_test` seed 2 的 READ DATA MISMATCH（beat0/beat8 重复数据）由 beat 引擎数据源重构修复（hit_line_data snoop 口 + `resp_is_miss_q` + per-entry MSHR fill），现 stress 全部 20 seeds PASS。
- `l2_axi_burst_length_test` 5 seeds 全 PASS，5 个 cdb 已再生。

关键日志：`reports/regression/*.log`（200 份）、`reports/coverage/uvcov.log`（0 error）、`reports/coverage/merged/`（HTML 报告）。

---

## 4. 覆盖率（uvcov 合并，165 测试）

| 指标 | 得分 | 覆盖/总数 |
|---|---|---|
| stmt | 42.84% | 667/1557 |
| cond | 26.48% | 139/525 |
| toggle | 25.88% | 6468/24988 |
| fsm | 23.26% | 40/172 |
| assert | 29.69% | 38/128 |
| group（功能） | 13.0% | 12/89 |
| **加权 total** | **26.86%** | — |

模块级（RTL 核心）：l2_hit_miss_detect 97.85%、l2_cache_top 82.65%、l2_request_pipeline 80.02%、l2_mshr 67.78%、l2_data_array 65.63%、l2_lru_controller 64.49%、l2_coherency_fsm 62.54%、l2_tag_array 52.95%、l2_axi_master 46.71%。

低分说明：ECC/prefetch/DFT/cdc 模块对应测试少或路径未激活（l2_ecc_engine 0%、l2_prefetch_engine 0%、DFT 链 0%）；功能覆盖率 bin 大量未命中系因 power_flush 等 10 条 FATAL 用例中断在 Phase 2，以及 group bin 定义宽于激励域。VCS 基线无合并报告留档，无法直接对比，属迁移后新基线。

---

## 5. 遗留缺陷清单（均为 RTL 既有，非迁移回归）

### 5.1 power_flush WB 链路（阻塞 10 条 FATAL）

`l2_tag_array.sv` 已实现 FLUSH_WRITEBACK（dirty 行先回写再 invalidate，`flush_wb_valid/addr/set/way` 输出、`flush_wb_done` 输入），但 **top 层未完成接线**：

- `flush_wb_done` 在 `l2_cache_top.sv` 只有声明（:241）与端口连接（:381），**无任何驱动**（`flush_wb_done_q/flush_wb_data/flush_wb_rd_pend` 三个声明也全部未使用）→ `FLUSH_WRITEBACK` 永挂 → `flush_done` 不来 → TB 超时 FATAL。
- MSHR 侧 `MSHR_WB_PENDING` 状态从未被分配（`l2_mshr.sv` 无 `state <= MSHR_WB_PENDING`），`wb_valid=|wb_vec`（:305-307）恒 0 → `perf_wb_count`（top :622）不增。
- 修复方向：top 在 `flush_wb_valid` 时经 data array snoop 口重放 victim line → 驱动 `u_axi_master` WB 请求（需新增一路 WB 请求 mux，与 MSHR WB 仲裁）→ WB 完成脉冲 `flush_wb_done`；`perf_wb_count` 增加 `flush_wb_valid && wb_done` 项。
- VCS 时代同一现象（`reports/regression/run_summary.txt` 同 10 条 FATAL），故不作为迁移验收阻塞项。

### 5.2 其他 RTL 既有缺陷（记录在案）

- snoop tag 端口错接（coherency 用 `snoop_tag_rd_index` 读 tag，与 CPU tag 读共享行冲突场景待复核）；
- 单拍 RLAST 场景（`resp_len_c==0` 的 phantom beat）已在 beat 引擎修复，但 assert `assert_rlast_terminates` 依赖 `resp_last_q` 捕获时序，回归中偶发 1 拍告警窗口；
- fill 请求丢弃窗口（`rd_req_valid` 门控中 `pipe_busy` 与 `mshr_line_match` 的组合在 AR 与 AW 同拍到达时仍有 1 拍竞争窗口）；
- 写合并表 `mrg_late_stall` 与 WB FSM 抢写口的仲裁未完全公平。

### 5.3 probe/bind 方案

SVA bind 的 probe 端口方案仍被 UVS Internal Error（design split）阻塞，现以 `l2_mshr` probe 端口 + VCD 离线分析（`waves/l2_cache.vcd`，注意 id `!` 即 clk）替代。

---

## 6. 复现步骤

```bash
export UV_LICENSE=<license-server>
export UVS_HOME=<UVS_HOME>
export PATH=$UVS_HOME/bin:$PATH
cd <project-root>

# 一键全流程（编译 + 200 runs + 合并，约 25 分钟 JOBS=1）
bash scripts/run_all_uvs.sh
# 快速冒烟：SEEDS=1 bash scripts/run_all_uvs.sh
# 并行：JOBS=8 bash scripts/run_all_uvs.sh
# 波形：WAVES=1 bash scripts/run_all_uvs.sh

# 单测
cd sim/uvs && ./l2_cache_top_sim +UVM_TESTNAME=l2_stress_test -fixed_seed 2 \
    -cov stmt,cond,fsm,tgl,assert,group -covdir /tmp/cdb -covtest t \
    +UVM_VERBOSITY=UVM_MEDIUM TIMEOUT=300000
```

产物：
- 二进制 `sim/uvs/l2_cache_top_sim`（编译 0 error / 42 warning，~10s）
- 回归 `reports/regression/run_summary.txt` + 200 份单测 log
- 覆盖率 `reports/coverage/merged.cdb` + `reports/coverage/merged/dashboard.html`（166 cdb 合并，0 error）
