// =============================================================================
// Module     : l2_cache_top
// Project    : L2 Cache Controller — Industrial Grade RTL
// Author     : Bibin N Biji
// Description: Top-level wrapper for the parameterized L2 cache controller.
//              Integrates tag array, data array, LRU controller, coherency FSM,
//              and AXI4 / AXI-ACE master/slave interfaces.
//
// Parameters:
//   CACHE_SIZE_KB  - Total cache size in KB (default: 256)
//   WAYS           - Number of cache ways (default: 4)
//   LINE_SIZE_B    - Cache line size in bytes (default: 64)
//   ADDR_WIDTH     - Physical address width (default: 40)
//   DATA_WIDTH     - Data bus width in bits (default: 64)
//   MSHR_DEPTH     - Number of MSHR entries (default: 16)
//   NUM_BANKS      - Number of data SRAM banks (default: 4)
//
// Coherency : MESI protocol, compatible with AXI-ACE snoop channels
// ECC       : SECDED per 64-bit word
// =============================================================================

`ifndef L2_CACHE_TOP_SV
`define L2_CACHE_TOP_SV

`include "l2_cache_pkg.sv"

module l2_cache_top
  import l2_cache_pkg::*;
#(
  parameter int unsigned CACHE_SIZE_KB = 256,
  parameter int unsigned WAYS          = 4,
  parameter int unsigned LINE_SIZE_B   = 64,
  parameter int unsigned ADDR_WIDTH    = 40,
  parameter int unsigned DATA_WIDTH    = 64,
  parameter int unsigned MSHR_DEPTH    = 16,
  parameter int unsigned NUM_BANKS     = 4,
  parameter int unsigned ID_WIDTH      = 8,

  // Derived — do not override
  localparam int unsigned NUM_SETS     = (CACHE_SIZE_KB * 1024) / (WAYS * LINE_SIZE_B),
  localparam int unsigned INDEX_BITS   = $clog2(NUM_SETS),
  localparam int unsigned OFFSET_BITS  = $clog2(LINE_SIZE_B),
  localparam int unsigned TAG_BITS     = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS,
  localparam int unsigned WORDS_PER_LINE = LINE_SIZE_B / (DATA_WIDTH / 8),
  localparam int unsigned ECC_BITS     = 8  // SECDED for 64-bit
)(
  // -------------------------------------------------------------------------
  // Global signals
  // -------------------------------------------------------------------------
  input  logic                    clk,
  input  logic                    rst_n,

  // -------------------------------------------------------------------------
  // CPU-side AXI4-Lite slave interface (L1 miss port)
  // -------------------------------------------------------------------------
  input  logic [ADDR_WIDTH-1:0]   s_axi_araddr,
  input  logic [7:0]              s_axi_arlen,
  input  logic [2:0]              s_axi_arsize,
  input  logic [1:0]              s_axi_arburst,
  input  logic [ID_WIDTH-1:0]     s_axi_arid,
  input  logic                    s_axi_arvalid,
  output logic                    s_axi_arready,

  output logic [DATA_WIDTH-1:0]   s_axi_rdata,
  output logic [1:0]              s_axi_rresp,
  output logic                    s_axi_rlast,
  output logic [ID_WIDTH-1:0]     s_axi_rid,
  output logic                    s_axi_rvalid,
  input  logic                    s_axi_rready,

  input  logic [ADDR_WIDTH-1:0]   s_axi_awaddr,
  input  logic [7:0]              s_axi_awlen,
  input  logic [2:0]              s_axi_awsize,
  input  logic [1:0]              s_axi_awburst,
  input  logic [ID_WIDTH-1:0]     s_axi_awid,
  input  logic                    s_axi_awvalid,
  output logic                    s_axi_awready,

  input  logic [DATA_WIDTH-1:0]   s_axi_wdata,
  input  logic [DATA_WIDTH/8-1:0] s_axi_wstrb,
  input  logic                    s_axi_wlast,
  input  logic                    s_axi_wvalid,
  output logic                    s_axi_wready,

  output logic [1:0]              s_axi_bresp,
  output logic [ID_WIDTH-1:0]     s_axi_bid,
  output logic                    s_axi_bvalid,
  input  logic                    s_axi_bready,

  // -------------------------------------------------------------------------
  // Memory-side AXI4 master interface (to L3/DRAM)
  // -------------------------------------------------------------------------
  output logic [ADDR_WIDTH-1:0]   m_axi_araddr,
  output logic [7:0]              m_axi_arlen,
  output logic [2:0]              m_axi_arsize,
  output logic [1:0]              m_axi_arburst,
  output logic [ID_WIDTH-1:0]     m_axi_arid,
  output logic                    m_axi_arvalid,
  input  logic                    m_axi_arready,

  input  logic [DATA_WIDTH-1:0]   m_axi_rdata,
  input  logic [1:0]              m_axi_rresp,
  input  logic                    m_axi_rlast,
  input  logic [ID_WIDTH-1:0]     m_axi_rid,
  input  logic                    m_axi_rvalid,
  output logic                    m_axi_rready,

  output logic [ADDR_WIDTH-1:0]   m_axi_awaddr,
  output logic [7:0]              m_axi_awlen,
  output logic [2:0]              m_axi_awsize,
  output logic [1:0]              m_axi_awburst,
  output logic [ID_WIDTH-1:0]     m_axi_awid,
  output logic                    m_axi_awvalid,
  input  logic                    m_axi_awready,

  output logic [DATA_WIDTH-1:0]   m_axi_wdata,
  output logic [DATA_WIDTH/8-1:0] m_axi_wstrb,
  output logic                    m_axi_wlast,
  output logic                    m_axi_wvalid,
  input  logic                    m_axi_wready,

  input  logic [1:0]              m_axi_bresp,
  input  logic [ID_WIDTH-1:0]     m_axi_bid,
  input  logic                    m_axi_bvalid,
  output logic                    m_axi_bready,

  // -------------------------------------------------------------------------
  // AXI-ACE snoop channels (coherency)
  // -------------------------------------------------------------------------
  input  logic [ADDR_WIDTH-1:0]   ac_addr,
  input  logic [3:0]              ac_snoop,   // snoop type encoding
  input  logic                    ac_valid,
  output logic                    ac_ready,

  output logic [4:0]              cr_resp,    // CRRESP[4:0]
  output logic                    cr_valid,
  input  logic                    cr_ready,

  output logic [DATA_WIDTH-1:0]   cd_data,
  output logic                    cd_last,
  output logic                    cd_valid,
  input  logic                    cd_ready,

  // -------------------------------------------------------------------------
  // Status & performance counters
  // -------------------------------------------------------------------------
  output logic                    cache_hit,
  output logic                    cache_miss,
  output logic                    wb_pending,
  output logic [31:0]             perf_hit_count,
  output logic [31:0]             perf_miss_count,
  output logic [31:0]             perf_wb_count,

  // -------------------------------------------------------------------------
  // Power management
  // -------------------------------------------------------------------------
  input  logic                    cache_flush_req,
  output logic                    cache_flush_done,
  input  logic                    cache_power_down
);

  // =========================================================================
  // Internal signal declarations
  // =========================================================================

  // Pipeline stage 0→1: address decode
  logic [INDEX_BITS-1:0]     pipe_set_index;
  logic [TAG_BITS-1:0]       pipe_req_tag;
  logic [OFFSET_BITS-1:0]    pipe_offset;
  logic                      pipe_req_valid;
  logic                      pipe_req_is_write;
  logic [DATA_WIDTH-1:0]     pipe_req_wdata;
  logic [DATA_WIDTH/8-1:0]   pipe_req_wstrb;
  logic [ID_WIDTH-1:0]       pipe_req_id;
  logic [7:0]                pipe_req_len;

  // Stage-1 request qualifier: tag/data array outputs are registered, so all
  // hit/miss resolution and downstream enables are qualified with the
  // request delayed by one cycle (same cycle the tag lookup result is valid).
  //   pipe_req_q  (cycle N+1): tag array rd_en — tag_rd_data valid in N+2
  //   pipe_req_q2 (cycle N+2): aligned with hit_any, qualifies all
  //                             hit/miss-dependent enables
  logic                      pipe_req_q;
  logic                      pipe_req_is_write_q;
  logic                      pipe_req_q2;
  logic                      pipe_req_is_write_q2;

  // Data array read port (CPU-side read path)
  logic [DATA_WIDTH-1:0]     s_axi_rdata_array;

  // Snoop-side tag read port (dedicated, indexed by the snoop address)
  logic                      snoop_tag_rd_en;
  logic [INDEX_BITS-1:0]     snoop_tag_rd_index;
  logic [TAG_BITS-1:0]       snoop_tag_data  [WAYS];
  logic                      snoop_tag_valid [WAYS];
  logic                      snoop_tag_dirty [WAYS];
  mesi_state_t               snoop_tag_mesi  [WAYS];

  // Hit-line replay buffer (whole line captured 1 cycle after a read hit)
  logic [DATA_WIDTH-1:0]     hit_line_data [WORDS_PER_LINE];
  ecc_status_t               rd_ecc_status_w;

  // Tag array outputs
  logic [TAG_BITS-1:0]       tag_rd_data  [WAYS];
  logic                      tag_valid_bit[WAYS];
  logic                      tag_dirty_bit[WAYS];
  mesi_state_t               tag_mesi_state[WAYS];

  // Hit/miss resolution
  logic                      hit_any;
  logic [WAYS-1:0]           hit_way_oh;   // one-hot hit way
  logic [$clog2(WAYS)-1:0]   hit_way_bin;

  // LRU
  logic [WAYS-2:0]           lru_state    [NUM_SETS];
  logic [$clog2(WAYS)-1:0]   lru_victim_way;

  // MSHR
  mshr_entry_t               mshr         [MSHR_DEPTH];
  logic                      mshr_full;
  logic                      mshr_line_match;
  logic                      mshr_alloc_req;
  logic [$clog2(MSHR_DEPTH)-1:0] mshr_alloc_idx;
  // Current-address probes: stall the AR/AW front door when the line of
  // the INCOMING address is already tracked (or in the pre-alloc window)
  logic                      probe_rd_hit, probe_aw_hit, probe_lat_hit;
  logic                      pipe_busy;
  // Latched write address (AW accepted, W beats still arriving) — probed
  // against the MSHR so an AR to the same line waits until the write's
  // entry exists (and its response/fill completes) instead of racing it
  logic [ADDR_WIDTH-1:0]     aw_addr_lat;
  logic                      pipe_wlast;
  logic                      pipe_wlast_q;
  logic                      pipe_wlast_q2;

  // Flush write-back (dirty lines evicted by cache_flush_req)
  logic                      flush_wb_valid;
  logic [ADDR_WIDTH-1:0]     flush_wb_addr;
  logic [INDEX_BITS-1:0]     flush_wb_set;
  logic [$clog2(WAYS)-1:0]   flush_wb_way;
  logic                      flush_wb_done;
  logic                      flush_wb_done_q;
  logic [DATA_WIDTH-1:0]     flush_wb_data [WORDS_PER_LINE];
  // Flush WB data read: the data array's snoop port replays the victim line
  logic                      flush_wb_rd_pend;

  // MSHR response port (fill complete → CPU-side R/B response)
  logic                      mshr_resp_valid;
  logic [ID_WIDTH-1:0]       mshr_resp_id;
  logic                      mshr_resp_is_write;
  logic [7:0]                mshr_resp_len;
  logic                      mshr_resp_accepted;
  logic [DATA_WIDTH-1:0]     mshr_resp_data [WORDS_PER_LINE];

  // Fill buffer
  logic [DATA_WIDTH-1:0]     fill_data    [WORDS_PER_LINE];
  logic                      fill_valid;
  logic [ADDR_WIDTH-1:0]     fill_addr;
  // Write-allocate merge backpressure (free slot in the merge table)
  logic                      wr_merge_ready;
  logic                      mrg_late_valid;
  logic                      mrg_late_stall;
  logic [ADDR_WIDTH-1:0]     mrg_late_addr;
  logic [2:0]                mrg_late_word;
  logic [DATA_WIDTH-1:0]     mrg_late_data;
  logic [DATA_WIDTH/8-1:0]   mrg_late_strb;
  // Late-merge replay uses the fill's way (the replayed line IS the filled
  // line); lru_victim_way moves on with later LRU updates, so latch it at
  // fill_valid. Replay pauses while a live pipeline hit-write needs the
  // port (single write port) or while a fill is writing the whole line.
  logic [1:0]                mrg_late_way_r;
  logic                      mrg_late_way_v;
  logic                      pipe_hit_wr;
  assign pipe_hit_wr = pipe_req_q2 & hit_any & pipe_req_is_write_q2;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                     mrg_late_way_v <= 1'b0;
    else if (fill_valid) begin
      mrg_late_way_r <= lru_victim_way;
      mrg_late_way_v <= 1'b1;
    end else if (!mrg_late_valid)   mrg_late_way_v <= 1'b0;
  end
  assign mrg_late_stall = pipe_hit_wr || fill_valid;

  // Write-back buffer
  logic [DATA_WIDTH-1:0]     wb_data      [WORDS_PER_LINE];
  logic [ADDR_WIDTH-1:0]     wb_addr;
  logic                      wb_valid;
  logic                      wb_done;

  // =========================================================================
  // Sub-module instantiations
  // =========================================================================

  l2_request_pipeline #(
    .ADDR_WIDTH   (ADDR_WIDTH),
    .DATA_WIDTH   (DATA_WIDTH),
    .INDEX_BITS   (INDEX_BITS),
    .TAG_BITS     (TAG_BITS),
    .OFFSET_BITS  (OFFSET_BITS),
    .ID_WIDTH     (ID_WIDTH)
  ) u_req_pipe (
    .clk             (clk),
    .rst_n           (rst_n),
    .s_axi_araddr    (s_axi_araddr),
    .s_axi_arlen     (s_axi_arlen),
    .s_axi_arsize    (s_axi_arsize),
    .s_axi_arburst   (s_axi_arburst),
    .s_axi_arid      (s_axi_arid),
    .s_axi_arvalid   (s_axi_arvalid),
    .s_axi_arready   (s_axi_arready),
    .s_axi_awaddr    (s_axi_awaddr),
    .s_axi_awid      (s_axi_awid),
    .s_axi_awvalid   (s_axi_awvalid),
    .s_axi_awready   (s_axi_awready),
    .s_axi_wdata     (s_axi_wdata),
    .s_axi_wstrb     (s_axi_wstrb),
    .s_axi_wlast     (s_axi_wlast),
    .s_axi_wvalid    (s_axi_wvalid),
    .s_axi_wready    (s_axi_wready),
    .pipe_set_index  (pipe_set_index),
    .pipe_req_tag    (pipe_req_tag),
    .pipe_offset     (pipe_offset),
    .pipe_req_valid  (pipe_req_valid),
    .pipe_req_is_write(pipe_req_is_write),
    .pipe_req_wdata  (pipe_req_wdata),
    .pipe_req_wstrb  (pipe_req_wstrb),
    .pipe_req_id     (pipe_req_id),
    .pipe_req_len    (pipe_req_len),
    .pipe_wlast      (pipe_wlast),
    .mshr_full       (mshr_full || ~wr_merge_ready),
    .resp_busy       (resp_busy),
    // Same-line gating on the CURRENT incoming addresses: an in-flight
    // request's line (still in the pre-alloc window or already in the
    // MSHR) forces a retry so every burst gets its own fill + response
    .ar_stall        (probe_rd_hit || probe_lat_hit || pipe_busy),
    .wr_stall        (probe_aw_hit || probe_lat_hit || pipe_busy),
    .wr_inflight_stall (1'b0),
    .pipe_busy       (pipe_busy)
  );

  l2_tag_array #(
    .NUM_SETS   (NUM_SETS),
    .WAYS       (WAYS),
    .TAG_BITS   (TAG_BITS),
    .INDEX_BITS (INDEX_BITS)
  ) u_tag_array (
    .clk            (clk),
    .rst_n          (rst_n),
    .rd_index       (pipe_set_index),
    .rd_en          (pipe_req_q),
    .tag_rd_data    (tag_rd_data),
    .valid_rd       (tag_valid_bit),
    .dirty_rd       (tag_dirty_bit),
    .mesi_rd        (tag_mesi_state),
    // write back from fill
    .wr_en          (fill_valid),
    .wr_index       (fill_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]),
    .wr_way         (lru_victim_way),
    .wr_tag         (fill_addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS]),
    .wr_valid       (1'b1),
    .wr_dirty       (1'b0),
    .wr_mesi        (MESI_EXCLUSIVE),
    // write hit: set dirty + MESI Modified
    .dirty_wr_en    (pipe_req_q2 & hit_any & pipe_req_is_write_q2),
    .dirty_wr_index (pipe_set_index),
    .dirty_wr_way   (hit_way_bin),
    // snoop-side tag read port
    .snoop_rd_en    (snoop_tag_rd_en),
    .snoop_rd_index (snoop_tag_rd_index),
    .snoop_tag_data (snoop_tag_data),
    .snoop_valid    (snoop_tag_valid),
    .snoop_dirty    (snoop_tag_dirty),
    .snoop_mesi     (snoop_tag_mesi),
    // flush (with dirty-line write-back)
    .flush_req      (cache_flush_req),
    .flush_done     (cache_flush_done),
    .flush_wb_valid (flush_wb_valid),
    .flush_wb_addr  (flush_wb_addr),
    .flush_wb_set   (flush_wb_set),
    .flush_wb_way   (flush_wb_way),
    .flush_wb_done  (flush_wb_done)
  );

  l2_hit_miss_detect #(
    .WAYS     (WAYS),
    .TAG_BITS (TAG_BITS)
  ) u_hit_miss (
    .req_tag      (pipe_req_tag),
    .tag_rd_data  (tag_rd_data),
    .valid_bit    (tag_valid_bit),
    .hit_any      (hit_any),
    .hit_way_oh   (hit_way_oh),
    .hit_way_bin  (hit_way_bin)
  );

  l2_lru_controller #(
    .NUM_SETS (NUM_SETS),
    .WAYS     (WAYS)
  ) u_lru (
    .clk          (clk),
    .rst_n        (rst_n),
    .access_valid (pipe_req_q2 & hit_any),
    .access_set   (pipe_set_index),
    .access_way   (hit_way_bin),
    .victim_set   (pipe_set_index),
    .victim_way   (lru_victim_way),
    .lru_state    (lru_state)
  );

  l2_data_array #(
    .NUM_SETS     (NUM_SETS),
    .WAYS         (WAYS),
    .DATA_WIDTH   (DATA_WIDTH),
    .WORDS_PER_LINE(WORDS_PER_LINE),
    .NUM_BANKS    (NUM_BANKS),
    .ECC_BITS     (ECC_BITS)
  ) u_data_array (
    .clk           (clk),
    .rst_n         (rst_n),
    .rd_index      (pipe_set_index),
    .rd_way        (hit_way_bin),
    .rd_word_sel   (pipe_offset[OFFSET_BITS-1:$clog2(DATA_WIDTH/8)]),
    .rd_en         (pipe_req_q2 & hit_any & ~pipe_req_is_write_q2),
    .rd_data       (s_axi_rdata_array),
    // Hit-line replay: capture the whole line one cycle after a read hit so
    // multi-beat responses can source beats 1..N without re-driving rd_en
    .snoop_rd_index (pipe_set_index),
    .snoop_rd_way   (hit_way_bin),
    .snoop_rd_en    (pipe_req_q2 & hit_any & ~pipe_req_is_write_q2),
    .snoop_rd_data  (hit_line_data),
    .rd_ecc_status  (rd_ecc_status_w),
    .wr_index      (mrg_late_valid ? mrg_late_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]
                                   : pipe_set_index),
    .wr_way        (mrg_late_valid ? mrg_late_way_r : hit_way_bin),
    .wr_word_sel   (mrg_late_valid ? mrg_late_word
                                   : pipe_offset[OFFSET_BITS-1:$clog2(DATA_WIDTH/8)]),
    .wr_data       (mrg_late_valid ? mrg_late_data : pipe_req_wdata),
    .wr_strb       (mrg_late_valid ? mrg_late_strb : pipe_req_wstrb),
    .wr_en         (mrg_late_valid | pipe_hit_wr),
    // fill path
    .fill_en       (fill_valid),
    .fill_index    (fill_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]),
    .fill_way      (lru_victim_way),
    .fill_data     (fill_data),
    // power
    .power_down    (cache_power_down)
  );

  l2_mshr #(
    .DEPTH      (MSHR_DEPTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .WORDS_PER_LINE (WORDS_PER_LINE)
  ) u_mshr (
    .clk           (clk),
    .rst_n         (rst_n),
    .alloc_req     (pipe_req_q2 & ~hit_any),
    .alloc_addr    ({pipe_req_tag, pipe_set_index, pipe_offset}),
    .alloc_id      (pipe_req_id),
    .alloc_len     (pipe_req_len),
    .alloc_is_write(pipe_req_is_write_q),
    .alloc_idx     (mshr_alloc_idx),
    .full          (mshr_full),
    .line_match_hit (mshr_line_match),
    .fill_valid    (fill_valid),
    .fill_addr     (fill_addr),
    .fill_data     (fill_data),
    .fill_req_offset (fill_req_offset),
    .wb_valid      (wb_valid),
    .wb_addr       (wb_addr),
    .wb_data       (wb_data),
    .wb_done       (wb_done),
    .resp_valid    (mshr_resp_valid),
    .resp_id       (mshr_resp_id),
    .resp_is_write (mshr_resp_is_write),
    .resp_len      (mshr_resp_len),
    .resp_data     (mshr_resp_data),
    .resp_accepted (mshr_resp_accepted),
    // Front-door same-line probes (current incoming addresses)
    .probe_rd_addr  (s_axi_araddr),
    .probe_rd_hit   (probe_rd_hit),
    .probe_aw_addr  (s_axi_awaddr),
    .probe_aw_hit   (probe_aw_hit),
    .probe_lat_addr (aw_addr_lat),
    .probe_lat_hit  (probe_lat_hit)
  );

  l2_axi_master #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .LINE_SIZE_B(LINE_SIZE_B)
  ) u_axi_master (
    .clk           (clk),
    .rst_n         (rst_n),
    // fill read
    .rd_req_valid  (pipe_req_q2 & ~hit_any & ~mshr_full & ~mshr_line_match),
    .rd_req_addr   ({pipe_req_tag, pipe_set_index, {OFFSET_BITS{1'b0}}}),
    .rd_req_id     (pipe_req_id),
    .fill_valid    (fill_valid),
    .fill_addr     (fill_addr),
    .fill_data     (fill_data),
    // write-allocate merge (write-miss data captured into fill stream)
    .wr_merge_valid (pipe_req_q2 & ~hit_any &  pipe_req_is_write_q2 & ~mshr_full),
    .wr_merge_addr  ({pipe_req_tag, pipe_set_index, pipe_offset}),
    .wr_merge_wdata (pipe_req_wdata),
    .wr_merge_wstrb (pipe_req_wstrb),
    .wr_merge_ready (wr_merge_ready),
    .mrg_late_valid (mrg_late_valid),
    .mrg_late_stall (mrg_late_stall),
    .mrg_late_addr  (mrg_late_addr),
    .mrg_late_word  (mrg_late_word),
    .mrg_late_data  (mrg_late_data),
    .mrg_late_strb  (mrg_late_strb),
    // write-back
    .wb_req_valid  (wb_valid),
    .wb_req_addr   (wb_addr),
    .wb_req_data   (wb_data),
    .wb_done       (wb_done),
    // AXI master ports
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),
    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arid    (m_axi_arid),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),
    .m_axi_rlast   (m_axi_rlast),
    .m_axi_rid     (m_axi_rid),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready),
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awlen   (m_axi_awlen),
    .m_axi_awsize  (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),
    .m_axi_awid    (m_axi_awid),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wlast   (m_axi_wlast),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bid     (m_axi_bid),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready)
  );

  l2_coherency_fsm #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .NUM_SETS   (NUM_SETS),
    .WAYS       (WAYS),
    .TAG_BITS   (TAG_BITS),
    .INDEX_BITS (INDEX_BITS),
    .OFFSET_BITS(OFFSET_BITS)
  ) u_coherency (
    .clk             (clk),
    .rst_n           (rst_n),
    .ac_addr         (ac_addr),
    .ac_snoop        (ac_snoop),
    .ac_valid        (ac_valid),
    .ac_ready        (ac_ready),
    .cr_resp         (cr_resp),
    .cr_valid        (cr_valid),
    .cr_ready        (cr_ready),
    .cd_data         (cd_data),
    .cd_last         (cd_last),
    .cd_valid        (cd_valid),
    .cd_ready        (cd_ready),
    .snoop_rd_en     (snoop_tag_rd_en),
    .snoop_rd_index  (snoop_tag_rd_index),
    .tag_rd_data     (snoop_tag_data),
    .valid_bit       (snoop_tag_valid),
    .dirty_bit       (snoop_tag_dirty),
    .mesi_state      (snoop_tag_mesi),
    .hit_any         (hit_any),
    .hit_way_bin     (hit_way_bin),
    .wb_pending      (wb_pending)
  );

  // =========================================================================
  // Stage-0 → stage-1 request pipeline register
  // Tag/data array read outputs are registered, so hit/miss resolution is
  // only meaningful one cycle after pipe_req_valid. All consumers (hit path,
  // data array enables, MSHR allocation, fill request) are qualified with
  // pipe_req_q to keep the request aligned with the lookup result.
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pipe_req_q            <= 1'b0;
      pipe_req_is_write_q   <= 1'b0;
      pipe_req_q2           <= 1'b0;
      pipe_req_is_write_q2  <= 1'b0;
      pipe_wlast_q          <= 1'b0;
      pipe_wlast_q2         <= 1'b0;
    end else begin
      pipe_req_q            <= pipe_req_valid;
      pipe_req_is_write_q   <= pipe_req_is_write;
      pipe_req_q2           <= pipe_req_q;
      pipe_req_is_write_q2  <= pipe_req_is_write_q;
      pipe_wlast_q          <= pipe_wlast;
      pipe_wlast_q2         <= pipe_wlast_q;
    end
  end

  // =========================================================================
  // Performance counters
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      perf_hit_count  <= '0;
      perf_miss_count <= '0;
      perf_wb_count   <= '0;
    end else begin
      if (pipe_req_q2 &  hit_any) perf_hit_count  <= perf_hit_count  + 1;
      if (pipe_req_q2 & ~hit_any) perf_miss_count <= perf_miss_count + 1;
      if (wb_valid & wb_done)    perf_wb_count   <= perf_wb_count   + 1;
    end
  end

  assign cache_hit  = pipe_req_q2 &  hit_any;
  assign cache_miss = pipe_req_q2 & ~hit_any;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                              aw_addr_lat <= '0;
    else if (s_axi_awvalid && s_axi_awready) aw_addr_lat <= s_axi_awaddr;
  end

  // =========================================================================
  // CPU-side R/B response path (read miss returns via R; write miss via B;
  // read/write hits respond combinationally on the next cycle)
  // =========================================================================
  // Read response: RDATA carries the single beat word from the data array;
  // resp_valid with resp_is_write=0 drives the R channel.
  // Write response: B channel OKAY after write is accepted (hit or miss-alloc).
  logic               resp_r_valid_q;
  logic               resp_r_valid_d;   // stage-1 response valid (data lands next edge)
  logic [ID_WIDTH-1:0] resp_r_id_q;
  logic               resp_b_valid_q;
  logic [ID_WIDTH-1:0] resp_b_id_q;

  // Multi-beat R response: ARLEN+1 beats per read burst. Burst length and
  // start offset are captured at the response-source cycle (resp_r_valid_d)
  // so back-to-back requests can't corrupt them before beat0 is accepted.
  logic [7:0]         resp_beat_q;      // current beat index
  logic [7:0]         resp_last_q;      // beat index of RLAST (== ARLEN)
  logic [2:0]         resp_word_q;      // word selector for current beat
  logic [7:0]         resp_len_c;       // ARLEN captured at resp cycle
  logic [2:0]         resp_start_c;     // start word captured at resp cycle

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_len_c    <= '0;
      resp_start_c  <= '0;
    end else if (resp_r_valid_d) begin
      // Hit responses: burst length is the pipeline's current request.
      // Miss responses: the MSHR entry carries the CPU burst length of
      // the request that issued the fill — pipe_req_len is unrelated
      // (it holds whatever request was issued LAST) and using it caused
      // phantom beats / wrong RLAST timing on single-beat miss bursts.
      resp_len_c   <= mshr_resp_valid ? mshr_resp_len : pipe_req_len;
      resp_start_c <= pipe_offset[OFFSET_BITS-1:$clog2(DATA_WIDTH/8)];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_beat_q <= '0;
      resp_last_q <= '0;
    end else if (resp_r_valid_q && !resp_beat_q && s_axi_rready) begin
      // First beat accepted → latch burst length for the remaining beats.
      // Single-beat burst (ARLEN=0): beat0 IS the whole burst — stay idle,
      // otherwise a phantom beat (rvalid&&rlast, never accepted) would
      // wedge resp_busy and deadlock the AR channel.
      resp_last_q <= resp_len_c;
      if (resp_len_c != 8'd0) resp_beat_q <= 8'd1;
    end else if (resp_beat_q != '0 && s_axi_rready) begin
      // RLAST beat accepted → burst done, return to idle (no phantom beat)
      if (resp_beat_q >= resp_last_q) resp_beat_q <= '0;
      else                            resp_beat_q <= resp_beat_q + 8'd1;
    end
  end

  // Beat words: walk sequentially through the line from the request offset.
  logic [2:0] resp_word_start_q;   // starting word index of the burst
  always_ff @(posedge clk) begin
    if (resp_r_valid_q && !resp_beat_q)
      resp_word_q      <= resp_start_c;
    else if (resp_beat_q != '0 && s_axi_rready)
      resp_word_q      <= resp_word_q + 3'd1;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) resp_word_start_q <= '0;
    else if (resp_r_valid_q && !resp_beat_q)
      resp_word_start_q <= resp_start_c;
  end

  // New burst may only start when the beat engine is idle — serializes
  // multi-beat responses when several misses complete back-to-back.
  // One burst per response pulse: while a beat0 is in flight (resp_r_valid_q
  // high, beat engine idle — waiting for rready or being accepted this very
  // cycle), the still-high mshr_resp_valid must NOT re-arm a duplicate
  // burst. Duplicate beat0s produced back-to-back RLAST and wedged the
  // beat engine when the driver had already dropped rready.
  // Combinational hold-off: covers BOTH the waiting cycle and the accept
  // cycle (a registered flag would lag one cycle and let one duplicate in).
  logic resp_r_pending;
  assign resp_r_pending = resp_r_valid_q && (resp_beat_q == '0);

  assign resp_r_valid_d = ((pipe_req_q2 & hit_any & ~pipe_req_is_write_q2) ||
                           (mshr_resp_valid & ~mshr_resp_is_write)) &&
                          (resp_beat_q == '0) &&
                          !resp_r_pending;

  // A response waiting for rready (rvalid_q high, beat engine idle) must
  // block new AR handshakes — otherwise the driver, holding rready low
  // while it issues the next AR, would interleave a second burst into
  // this one's beat stream (this is what produced phantom RLAST pairs).
  assign resp_busy = resp_r_valid_q || (resp_beat_q != '0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_r_valid_q <= 1'b0;
      resp_r_id_q    <= '0;
      resp_b_valid_q <= 1'b0;
      resp_b_id_q    <= '0;
    end else begin
      // ---- R channel ----
      // Hit read: data array rd_data is registered one cycle after the
      // stage-1 lookup → respond two cycles after request acceptance.
      // Miss read: respond when the MSHR signals fill-complete.
      // One extra stage: fill-line capture registers update on the same
      // edge as mshr_resp_valid; serving beat0 a cycle later guarantees
      // resp_fill_word_q/resp_fill_line_q hold the current fill.
      resp_r_valid_q <= resp_r_valid_d;
      resp_r_id_q    <= (mshr_resp_valid & ~mshr_resp_is_write)
                          ? mshr_resp_id : pipe_req_id;

      // ---- B channel ----
      // Hit write: respond one cycle after the write lands in the array.
      // Miss write: write-allocate fill completes first, then the MSHR
      //             response closes the transaction.
      // Multi-beat writes: only the WLAST beat of the burst opens a B —
      // intermediate beats must not (one B per AW burst per AXI spec).
      resp_b_valid_q <= (pipe_req_q2 & hit_any & pipe_req_is_write_q2 & pipe_wlast_q2) ||
                        (mshr_resp_valid &  mshr_resp_is_write);
      resp_b_id_q    <= (mshr_resp_valid & mshr_resp_is_write)
                          ? mshr_resp_id : pipe_req_id;
    end
  end

  always_ff @(posedge clk) begin
    if ($test$plusargs("DBG_FILL") && s_axi_rvalid && s_axi_rready && (resp_beat_q == '0))
      $display("[DBG_FILL] t=%0t beat0 serve w0=%h", $time, s_axi_rdata);
  end

  assign s_axi_rvalid = resp_r_valid_q || (resp_beat_q != '0);
  assign s_axi_rid    = resp_r_id_q;
  // s_axi_rdata driven by data array read port (u_data_array.rd_data)
  assign s_axi_rresp  = 2'b00;         // OKAY (SLVERR only on ECC double-bit)
  assign s_axi_rlast  = (resp_beat_q == '0)
                        ? (resp_len_c == 8'd0)
                        : (resp_beat_q >= resp_last_q);

  assign s_axi_bvalid = resp_b_valid_q;
  assign s_axi_bid    = resp_b_id_q;
  assign s_axi_bresp  = 2'b00;         // OKAY

  // Response accepted when the CPU-side master is ready
  assign mshr_resp_accepted = (~mshr_resp_is_write & s_axi_rvalid & s_axi_rready & (resp_beat_q == '0)) |
                              ( mshr_resp_is_write & s_axi_bvalid & s_axi_bready);

  // -------------------------------------------------------------------------
  // Read-miss response data: the data array read port only tracks CPU-side
  // reads, so a miss response would carry stale array output. Capture the
  // fill word (at the missing request's offset) when its fill completes.
  // -------------------------------------------------------------------------
  logic [2:0] fill_req_offset;
  logic [DATA_WIDTH-1:0] resp_fill_word_q;
  // Full line captured from the MSHR's per-entry fill storage at response
  // time — stable per entry even with multiple outstanding fills.
  logic [DATA_WIDTH-1:0] resp_fill_line_q [WORDS_PER_LINE];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) resp_fill_word_q <= '0;
    else if (mshr_resp_valid && !mshr_resp_is_write) begin
      if ($test$plusargs("DBG_FILL")) $display("[DBG_FILL] t=%0t cap off=%0d w0=%h", $time, fill_req_offset, mshr_resp_data[0]);
      resp_fill_word_q <= mshr_resp_data[fill_req_offset];
      resp_fill_line_q[0] <= mshr_resp_data[0];
      resp_fill_line_q[1] <= mshr_resp_data[1];
      resp_fill_line_q[2] <= mshr_resp_data[2];
      resp_fill_line_q[3] <= mshr_resp_data[3];
      resp_fill_line_q[4] <= mshr_resp_data[4];
      resp_fill_line_q[5] <= mshr_resp_data[5];
      resp_fill_line_q[6] <= mshr_resp_data[6];
      resp_fill_line_q[7] <= mshr_resp_data[7];
    end
  end

  // MUX: hit responses use the array read port; miss responses use the fill
  // word/line. Held for the whole multi-beat burst (mshr_resp_valid is a
  // 1-cycle pulse; the beat engine consumes it across ARLEN+1 cycles).
  logic resp_is_miss_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                                                   resp_is_miss_q <= 1'b0;
    else if (mshr_resp_valid & ~mshr_resp_is_write)                resp_is_miss_q <= 1'b1;
    else if ((resp_beat_q == '0) && !mshr_resp_valid)              resp_is_miss_q <= 1'b0;
  end
  assign s_axi_rdata = resp_is_miss_q
                       ? ((resp_beat_q == '0) ? resp_fill_word_q
                                              : resp_fill_line_q[(resp_word_start_q + resp_beat_q) % WORDS_PER_LINE])
                       : ((resp_beat_q == '0) ? s_axi_rdata_array
                                              : hit_line_data[(resp_word_start_q + resp_beat_q) % WORDS_PER_LINE]);

  // -------------------------------------------------------------------------
  // Data array read port: only the original hit path drives it. Multi-beat
  // responses source beats 1..N from hit_line_data (hits) or resp_fill_line_q
  // (misses) — no port replay, no skew.
  // -------------------------------------------------------------------------

endmodule

`endif // L2_CACHE_TOP_SV
