// =============================================================================
// Module     : l2_axi_master
// Description: AXI4 master interface on the memory side of the L2 cache.
//              Handles:
//                (a) Read transactions — cache line fills from L3/DRAM
//                (b) Write transactions — dirty line write-backs
//
// Transaction ordering rule:
//   If a fill and write-back target the same cache-line address,
//   the write-back is issued first, ACK'd, then the fill is issued.
//   This prevents stale data from being re-read after a write-back.
//
// Burst size:  Always 8 beats × 8 bytes = 64-byte cache line (INCR burst)
// Outstanding: Up to MSHR_DEPTH simultaneous fill reads in flight
// =============================================================================

`ifndef L2_AXI_MASTER_SV
`define L2_AXI_MASTER_SV

`include "l2_cache_pkg.sv"

module l2_axi_master
  import l2_cache_pkg::*;
#(
  parameter int unsigned ADDR_WIDTH  = 40,
  parameter int unsigned DATA_WIDTH  = 64,
  parameter int unsigned ID_WIDTH    = 8,
  parameter int unsigned LINE_SIZE_B = 64,

  localparam int unsigned BEAT_CNT_W = $clog2(LINE_SIZE_B / (DATA_WIDTH/8)),
  localparam int unsigned BEATS      = LINE_SIZE_B / (DATA_WIDTH/8),
  localparam int unsigned WORDS_PER_LINE = BEATS
)(
  input  logic                    clk,
  input  logic                    rst_n,

  // -------------------------------------------------------------------------
  // Fill request — from MSHR (read from L3/DRAM)
  // -------------------------------------------------------------------------
  input  logic                    rd_req_valid,
  input  logic [ADDR_WIDTH-1:0]   rd_req_addr,    // cache-line aligned
  input  logic [ID_WIDTH-1:0]     rd_req_id,
  output logic                    rd_req_accepted, // ARVALID && ARREADY

  // Fill data returned to cache arrays
  output logic                    fill_valid,
  output logic [ADDR_WIDTH-1:0]   fill_addr,
  output logic [DATA_WIDTH-1:0]   fill_data [WORDS_PER_LINE],
  output logic [ID_WIDTH-1:0]     fill_id,

  // Pending CPU write-merge (write-allocate: capture write-miss data here and
  // merge it into the fill beats, since the fill would otherwise overwrite it)
  input  logic                    wr_merge_valid,   // write-miss acceptance pulse
  input  logic [ADDR_WIDTH-1:0]   wr_merge_addr,    // full request address
  input  logic [DATA_WIDTH-1:0]   wr_merge_wdata,   // single-beat write data
  input  logic [DATA_WIDTH/8-1:0] wr_merge_wstrb,   // single-beat strobes
  output logic                    wr_merge_ready,   // merge table has a free slot
  // Late merge replay: W words captured after the fill beat passed. The top
  // level applies these to the data array like a hit write, using the fill's
  // latched way. mrg_late_stall defers replay while the write port is busy.
  output logic                    mrg_late_valid,
  input  logic                    mrg_late_stall,
  output logic [ADDR_WIDTH-1:0]   mrg_late_addr,
  output logic [$clog2(WORDS_PER_LINE)-1:0] mrg_late_word,
  output logic [DATA_WIDTH-1:0]   mrg_late_data,
  output logic [DATA_WIDTH/8-1:0] mrg_late_strb,

  // -------------------------------------------------------------------------
  // Write-back request — from dirty eviction path
  // -------------------------------------------------------------------------
  input  logic                    wb_req_valid,
  input  logic [ADDR_WIDTH-1:0]   wb_req_addr,
  input  logic [DATA_WIDTH-1:0]   wb_req_data [WORDS_PER_LINE],
  output logic                    wb_req_accepted,
  output logic                    wb_done,         // BVALID && BRESP==OK

  // -------------------------------------------------------------------------
  // AXI4 master ports
  // -------------------------------------------------------------------------
  // Read address
  output logic [ADDR_WIDTH-1:0]   m_axi_araddr,
  output logic [7:0]              m_axi_arlen,
  output logic [2:0]              m_axi_arsize,
  output logic [1:0]              m_axi_arburst,
  output logic [ID_WIDTH-1:0]     m_axi_arid,
  output logic                    m_axi_arvalid,
  input  logic                    m_axi_arready,

  // Read data
  input  logic [DATA_WIDTH-1:0]   m_axi_rdata,
  input  logic [1:0]              m_axi_rresp,
  input  logic                    m_axi_rlast,
  input  logic [ID_WIDTH-1:0]     m_axi_rid,
  input  logic                    m_axi_rvalid,
  output logic                    m_axi_rready,

  // Write address
  output logic [ADDR_WIDTH-1:0]   m_axi_awaddr,
  output logic [7:0]              m_axi_awlen,
  output logic [2:0]              m_axi_awsize,
  output logic [1:0]              m_axi_awburst,
  output logic [ID_WIDTH-1:0]     m_axi_awid,
  output logic                    m_axi_awvalid,
  input  logic                    m_axi_awready,

  // Write data
  output logic [DATA_WIDTH-1:0]   m_axi_wdata,
  output logic [DATA_WIDTH/8-1:0] m_axi_wstrb,
  output logic                    m_axi_wlast,
  output logic                    m_axi_wvalid,
  input  logic                    m_axi_wready,

  // Write response
  input  logic [1:0]              m_axi_bresp,
  input  logic [ID_WIDTH-1:0]     m_axi_bid,
  input  logic                    m_axi_bvalid,
  output logic                    m_axi_bready
);

  // =========================================================================
  // Read (fill) channel FSM
  // =========================================================================
  typedef enum logic [1:0] {
    RD_IDLE    = 2'b00,
    RD_ADDR    = 2'b01,   // issue ARVALID
    RD_DATA    = 2'b10,   // receive R beats
    RD_DONE    = 2'b11    // pulse fill_valid
  } rd_state_t;

  rd_state_t rd_state;
  logic [ADDR_WIDTH-1:0]           fill_addr_r;
  logic [ID_WIDTH-1:0]             fill_id_r;
  logic [DATA_WIDTH-1:0]           fill_buf [WORDS_PER_LINE];
  logic [BEAT_CNT_W-1:0]           rd_beat_cnt;

  // -----------------------------------------------------------------------
  // Fill request FIFO — rd_req pulses are one-cycle acceptances from the
  // pipeline; a fill takes many cycles, so concurrent requests must be
  // queued or they are silently dropped (MSHR entries would never complete).
  // -----------------------------------------------------------------------
  localparam int unsigned REQ_FIFO_DEPTH = 8;
  localparam int unsigned REQ_FIFO_W = $clog2(REQ_FIFO_DEPTH);

  logic [ADDR_WIDTH-1:0]          reqq_addr [REQ_FIFO_DEPTH];
  logic [ID_WIDTH-1:0]            reqq_id   [REQ_FIFO_DEPTH];
  logic [REQ_FIFO_W-1:0]          reqq_wr, reqq_rd;
  logic                           reqq_full, reqq_empty;
  logic                           reqq_we;

  assign reqq_full  = (reqq_wr + 1'b1) == reqq_rd;
  assign reqq_empty = reqq_wr == reqq_rd;
  // Accept a request when not full (1 we / 1 rd pointer, holds one slot slack)
  assign reqq_we    = rd_req_valid && !reqq_full;

  always_ff @(posedge clk or negedge rst_n) begin : reqq_wr_ptr
    if (!rst_n) reqq_wr <= '0;
    else if (reqq_we) reqq_wr <= reqq_wr + 1'b1;
  end

  always_ff @(posedge clk) begin : reqq_mem
    if (reqq_we) begin
      reqq_addr[reqq_wr] <= rd_req_addr;
      reqq_id  [reqq_wr] <= rd_req_id;
    end
  end

  // -----------------------------------------------------------------------
  // Write-merge table — one entry per pending write-miss line. Multiple
  // words of the same line are OR-merged into one entry.
  // -----------------------------------------------------------------------
  localparam int unsigned OFFSET_W = 6;  // 64B line
  logic [ADDR_WIDTH-1:0]          mrg_line  [WORDS_PER_LINE];
  logic [WORDS_PER_LINE-1:0]      mrg_word_v [WORDS_PER_LINE]; // per-entry word-valid mask
  logic [DATA_WIDTH-1:0]          mrg_data  [WORDS_PER_LINE][WORDS_PER_LINE];
  logic [DATA_WIDTH/8-1:0]        mrg_strb  [WORDS_PER_LINE][WORDS_PER_LINE];
  logic [WORDS_PER_LINE-1:0]      mrg_entry_v;   // entry occupied
  logic                           mrg_hit, mrg_hit_v;
  logic [$clog2(WORDS_PER_LINE)-1:0] mrg_hit_idx, mrg_free_idx, mri;

  always_comb begin
    mrg_hit     = 1'b0;
    mrg_hit_idx = '0;
    mrg_free_idx= '0;
    mrg_hit_v   = 1'b0;
    for (int e = 0; e < WORDS_PER_LINE; e++) begin
      if (mrg_entry_v[e] && !mrg_hit &&
          mrg_line[e][ADDR_WIDTH-1:OFFSET_W] ==
          {wr_merge_addr[ADDR_WIDTH-1:OFFSET_W]}) begin
        mrg_hit     = 1'b1;
        mrg_hit_idx = e[$clog2(WORDS_PER_LINE)-1:0];
      end
      if (!mrg_entry_v[e] && !mrg_hit_v) begin
        mrg_free_idx = e[$clog2(WORDS_PER_LINE)-1:0];
        mrg_hit_v    = 1'b1;
      end
    end
  end

  assign wr_merge_ready = mrg_hit || mrg_hit_v;   // existing entry or free slot

  // Word index within line from the request address
  logic [$clog2(WORDS_PER_LINE)-1:0] wr_merge_word;
  assign wr_merge_word = wr_merge_addr[$clog2(WORDS_PER_LINE)-1+3:3];

  // Fill beat overlay consume signal — the rd_fsm consumes one word per
  // fill beat; mrg_table clears that bit so late_merge only replays words
  // the fill never saw.
  logic mrg_consume_en;
  logic [$clog2(WORDS_PER_LINE)-1:0] mrg_consume_word;
  assign mrg_consume_en   = (rd_state == RD_DATA) && m_axi_rvalid && m_axi_rready &&
                            cur_mrg_en && mrg_word_v[cur_mrg_idx][rd_beat_cnt];
  assign mrg_consume_word = rd_beat_cnt;

  always_ff @(posedge clk or negedge rst_n) begin : mrg_table
    if (!rst_n) begin
      mrg_entry_v <= '0;
      for (int e0 = 0; e0 < WORDS_PER_LINE; e0++)
        mrg_word_v[e0] <= '0;
    end else begin
      // capture write-miss word (into matching entry or a free slot)
      if (wr_merge_valid && wr_merge_ready) begin
        if (!mrg_hit) begin
          mrg_entry_v[mrg_free_idx]                <= 1'b1;
          mrg_line  [mrg_free_idx]                 <= {wr_merge_addr[ADDR_WIDTH-1:OFFSET_W], {OFFSET_W{1'b0}}};
          for (int e1 = 0; e1 < WORDS_PER_LINE; e1++)
            mrg_word_v[mrg_free_idx][e1] <= 1'b0;
        end
        mrg_word_v[mrg_hit ? mrg_hit_idx : mrg_free_idx][wr_merge_word] <= 1'b1;
        mrg_data  [mrg_hit ? mrg_hit_idx : mrg_free_idx][wr_merge_word] <= wr_merge_wdata;
        mrg_strb  [mrg_hit ? mrg_hit_idx : mrg_free_idx][wr_merge_word] <= wr_merge_wstrb;
      end
      // consume: this word was overlaid into the in-flight fill beat
      if (mrg_consume_en)
        mrg_word_v[cur_mrg_idx][mrg_consume_word] <= 1'b0;
      // release entry when its fill completes
      if (fill_valid) begin
        for (int e = 0; e < WORDS_PER_LINE; e++) begin
          if (mrg_entry_v[e] &&
              mrg_line[e][ADDR_WIDTH-1:OFFSET_W] == fill_addr_r[ADDR_WIDTH-1:OFFSET_W])
            mrg_entry_v[e] <= 1'b0;
        end
      end
    end
  end

  // Merge values for the fill currently in flight (line = fill_addr_r)
  logic                          cur_mrg_en;
  logic [$clog2(WORDS_PER_LINE)-1:0] cur_mrg_idx;
  always_comb begin
    cur_mrg_en   = 1'b0;
    cur_mrg_idx  = '0;
    for (int e = 0; e < WORDS_PER_LINE; e++) begin
      if (mrg_entry_v[e] && !cur_mrg_en &&
          mrg_line[e][ADDR_WIDTH-1:OFFSET_W] == fill_addr_r[ADDR_WIDTH-1:OFFSET_W]) begin
        cur_mrg_en  = 1'b1;
        cur_mrg_idx = e[$clog2(WORDS_PER_LINE)-1:0];
      end
    end
  end

  // -----------------------------------------------------------------------
  // Late-merge engine — W beats of a CPU write burst trickle in ~10 cycles
  // apart while the fill returns beats every ~2 cycles. Any word captured
  // AFTER its fill beat was overlaid would be silently lost (the fill line
  // is already in the data array). The mrg_table clears a word bit when the
  // fill consumes it, so at fill_valid the entry mask holds exactly the
  // words the fill never saw. Those are snapshotted here and replayed into
  // the data array one word per cycle via mrg_late_* (top gates them into
  // the hit-write port with the fill's way). mrg_late_stall defers a replay
  // word when the top-level write port is busy with a live hit/other source.
  // -----------------------------------------------------------------------
  logic [WORDS_PER_LINE-1:0] late_word_v;    // words still to apply
  logic [WORDS_PER_LINE-1:0] late_snap_v;    // snapshot mask (read-only)
  logic [DATA_WIDTH-1:0]     late_data  [WORDS_PER_LINE];
  logic [DATA_WIDTH/8-1:0]   late_strb  [WORDS_PER_LINE];
  logic [ADDR_WIDTH-1:0]     late_line;
  logic [$clog2(WORDS_PER_LINE)-1:0] late_idx;
  logic                      late_active;    // replay in progress
  logic                      mrg_late_stall; // from top: write port busy

  always_comb begin
    late_idx = '0;
    for (int w3 = WORDS_PER_LINE-1; w3 >= 0; w3--) begin
      if (late_word_v[w3]) late_idx = w3[$clog2(WORDS_PER_LINE)-1:0];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin : late_merge
    if (!rst_n) begin
      late_active <= 1'b0;
      late_word_v <= '0;
      late_snap_v <= '0;
      late_line   <= '0;
    end else begin
      // Start: fill completed and the merge entry still holds unconsumed words
      if (fill_valid && cur_mrg_en && (|mrg_word_v[cur_mrg_idx])) begin
        late_active <= 1'b1;
        late_line   <= fill_addr_r;
        late_snap_v <= mrg_word_v[cur_mrg_idx];
        late_word_v <= mrg_word_v[cur_mrg_idx];
        for (int w = 0; w < WORDS_PER_LINE; w++) begin
          late_data[w] <= mrg_data[cur_mrg_idx][w];
          late_strb[w] <= mrg_strb[cur_mrg_idx][w];
        end
      end else if (late_active) begin
        if (mrg_late_valid && !mrg_late_stall)
          late_word_v[late_idx] <= 1'b0;   // this word was replayed
        if (!|late_word_v)
          late_active <= 1'b0;
      end
    end
  end

  assign mrg_late_valid = late_active && |late_word_v && !mrg_late_stall;
  assign mrg_late_addr  = late_line;
  assign mrg_late_word  = late_idx;
  assign mrg_late_data  = late_data[late_idx];
  assign mrg_late_strb  = late_strb[late_idx];

  always_ff @(posedge clk or negedge rst_n) begin : rd_fsm
    if (!rst_n) begin
      rd_state    <= RD_IDLE;
      fill_addr_r <= '0;
      fill_id_r   <= '0;
      rd_beat_cnt <= '0;
      fill_valid  <= 1'b0;
      reqq_rd     <= '0;
    end else begin
      fill_valid <= 1'b0;  // default: pulse for one cycle

      unique case (rd_state)
        RD_IDLE: begin
          if (!reqq_empty) begin
            if ($test$plusargs("DBG_FILL")) $display("[DBG_FILL] t=%0t AR addr=%h", $time, reqq_addr[reqq_rd]);
            fill_addr_r <= reqq_addr[reqq_rd];
            fill_id_r   <= reqq_id  [reqq_rd];
            reqq_rd     <= reqq_rd + 1'b1;
            rd_state    <= RD_ADDR;
          end
        end

        RD_ADDR: begin
          if (m_axi_arvalid && m_axi_arready) begin
            rd_beat_cnt <= '0;
            rd_state    <= RD_DATA;
          end
        end

        RD_DATA: begin
          if (m_axi_rvalid && m_axi_rready) begin
            logic [DATA_WIDTH-1:0] mrg_word_val;
            logic [DATA_WIDTH/8-1:0] mrg_word_strb;
            fill_buf[rd_beat_cnt] <= m_axi_rdata;
            // Write-allocate merge: overlay pending CPU write word for this line
            if (cur_mrg_en && mrg_word_v[cur_mrg_idx][rd_beat_cnt]) begin
              mrg_word_val  = mrg_data[cur_mrg_idx][rd_beat_cnt];
              mrg_word_strb = mrg_strb[cur_mrg_idx][rd_beat_cnt];
              for (int bi = 0; bi < DATA_WIDTH/8; bi++) begin
                if (mrg_word_strb[bi])
                  fill_buf[rd_beat_cnt][bi*8+:8] <= mrg_word_val[bi*8+:8];
              end
            end
            if (m_axi_rlast) begin
              rd_state   <= RD_DONE;
            end else begin
              rd_beat_cnt <= rd_beat_cnt + 1;
            end
          end
        end

        RD_DONE: begin
          fill_valid <= 1'b1;
          rd_state   <= RD_IDLE;
        end
      endcase
    end
  end

  // AXI read address channel
  assign m_axi_arvalid  = (rd_state == RD_ADDR);
  assign m_axi_araddr   = {fill_addr_r[ADDR_WIDTH-1:6], 6'b0};  // line-aligned
  assign m_axi_arlen    = 8'(BEATS - 1);   // burst length
  assign m_axi_arsize   = 3'b011;          // 8 bytes per beat
  assign m_axi_arburst  = 2'b01;           // INCR
  assign m_axi_arid     = fill_id_r;

  // AXI read data channel
  assign m_axi_rready   = (rd_state == RD_DATA);

  // Fill output
  assign fill_addr      = fill_addr_r;
  assign fill_id        = fill_id_r;
  assign fill_data      = fill_buf;
  assign rd_req_accepted = m_axi_arvalid && m_axi_arready;

  // =========================================================================
  // Write (write-back) channel FSM
  // =========================================================================
  typedef enum logic [2:0] {
    WB_IDLE    = 3'b000,
    WB_ADDR    = 3'b001,   // issue AWVALID
    WB_DATA    = 3'b010,   // send W beats
    WB_RESP    = 3'b011,   // wait for BVALID
    WB_DONE    = 3'b100    // pulse wb_done
  } wb_state_t;

  wb_state_t  wb_state;
  logic [ADDR_WIDTH-1:0]           wb_addr_r;
  logic [DATA_WIDTH-1:0]           wb_buf [WORDS_PER_LINE];
  logic [BEAT_CNT_W-1:0]           wb_beat_cnt;
  logic                            aw_done, w_done;

  always_ff @(posedge clk or negedge rst_n) begin : wb_fsm
    if (!rst_n) begin
      wb_state    <= WB_IDLE;
      wb_addr_r   <= '0;
      wb_beat_cnt <= '0;
      wb_done     <= 1'b0;
      aw_done     <= 1'b0;
      w_done      <= 1'b0;
    end else begin
      wb_done <= 1'b0;

      unique case (wb_state)
        WB_IDLE: begin
          if (wb_req_valid) begin
            wb_addr_r   <= wb_req_addr;
            wb_buf      <= wb_req_data;
            wb_beat_cnt <= '0;
            aw_done     <= 1'b0;
            w_done      <= 1'b0;
            wb_state    <= WB_ADDR;
          end
        end

        WB_ADDR: begin
          // AW and W can be issued simultaneously per AXI spec
          if (m_axi_awvalid && m_axi_awready) aw_done <= 1'b1;
          if (m_axi_wvalid  && m_axi_wready) begin
            wb_beat_cnt <= wb_beat_cnt + 1;
            if (m_axi_wlast) w_done <= 1'b1;
          end
          // Move to data state once AW is accepted (if W not done yet)
          if ((m_axi_awvalid && m_axi_awready) || aw_done)
            if (!w_done) wb_state <= WB_DATA;
          // Both done simultaneously
          if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
              (w_done  || (m_axi_wlast   && m_axi_wvalid && m_axi_wready)))
            wb_state <= WB_RESP;
        end

        WB_DATA: begin
          if (m_axi_wvalid && m_axi_wready) begin
            wb_beat_cnt <= wb_beat_cnt + 1;
            if (m_axi_wlast) wb_state <= WB_RESP;
          end
        end

        WB_RESP: begin
          if (m_axi_bvalid && m_axi_bready) begin
            wb_state <= WB_DONE;
          end
        end

        WB_DONE: begin
          wb_done  <= 1'b1;
          wb_state <= WB_IDLE;
        end
      endcase
    end
  end

  // AXI write address channel
  assign m_axi_awvalid  = (wb_state == WB_ADDR) && !aw_done;
  assign m_axi_awaddr   = {wb_addr_r[ADDR_WIDTH-1:6], 6'b0};
  assign m_axi_awlen    = 8'(BEATS - 1);
  assign m_axi_awsize   = 3'b011;
  assign m_axi_awburst  = 2'b01;
  assign m_axi_awid     = ID_WIDTH'(8'hFF);  // fixed WB ID (configurable)

  // AXI write data channel
  assign m_axi_wvalid   = (wb_state == WB_ADDR || wb_state == WB_DATA) && !w_done;
  assign m_axi_wdata    = wb_buf[wb_beat_cnt];
  assign m_axi_wstrb    = '1;              // all byte enables for full-line WB
  assign m_axi_wlast    = (wb_beat_cnt == BEAT_CNT_W'(BEATS - 1));

  // AXI write response channel
  assign m_axi_bready   = (wb_state == WB_RESP);

  assign wb_req_accepted = (wb_state == WB_IDLE) && wb_req_valid;

  // =========================================================================
  // Assertions
  // =========================================================================
`ifdef SIMULATION

  // ARVALID must remain asserted until ARREADY
  property p_arvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (m_axi_arvalid && !m_axi_arready) |=> m_axi_arvalid;
  endproperty
  ap_ar_stable: assert property (p_arvalid_stable)
    else $error("AXI_MASTER: ARVALID dropped before ARREADY");

  // AWVALID must remain asserted until AWREADY
  property p_awvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (m_axi_awvalid && !m_axi_awready) |=> m_axi_awvalid;
  endproperty
  ap_aw_stable: assert property (p_awvalid_stable)
    else $error("AXI_MASTER: AWVALID dropped before AWREADY");

  // WVALID must remain asserted until WREADY
  property p_wvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (m_axi_wvalid && !m_axi_wready) |=> m_axi_wvalid;
  endproperty
  ap_w_stable: assert property (p_wvalid_stable)
    else $error("AXI_MASTER: WVALID dropped before WREADY");

  // WLAST must be set exactly on the last beat
  property p_wlast_on_last_beat;
    @(posedge clk) disable iff (!rst_n)
    (m_axi_wvalid && m_axi_wready) |->
    (m_axi_wlast == (wb_beat_cnt == BEAT_CNT_W'(BEATS - 1)));
  endproperty
  ap_wlast: assert property (p_wlast_on_last_beat)
    else $error("AXI_MASTER: WLAST incorrect at beat %0d", wb_beat_cnt);

  // Fill address must be cache-line aligned
  property p_fill_addr_aligned;
    @(posedge clk) disable iff (!rst_n)
    m_axi_arvalid |-> (m_axi_araddr[5:0] == 6'b0);
  endproperty
  ap_fill_align: assert property (p_fill_addr_aligned)
    else $error("AXI_MASTER: fill address 0x%0h not cache-line aligned",
                m_axi_araddr);

  // No simultaneous fill and write-back to same address
  property p_no_fill_wb_same_addr;
    @(posedge clk) disable iff (!rst_n)
    (m_axi_arvalid && m_axi_awvalid) |->
    (m_axi_araddr[ADDR_WIDTH-1:6] != m_axi_awaddr[ADDR_WIDTH-1:6]);
  endproperty
  ap_no_conflict: assert property (p_no_fill_wb_same_addr)
    else $error("AXI_MASTER: simultaneous fill+WB to same cache line 0x%0h",
                m_axi_araddr[ADDR_WIDTH-1:6]);

`endif

endmodule

`endif // L2_AXI_MASTER_SV
