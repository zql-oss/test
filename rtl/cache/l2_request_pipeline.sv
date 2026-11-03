// =============================================================================
// Module     : l2_request_pipeline
// Description: Accepts AXI4 AR (read) and AW+W (write) transactions from the
//              CPU/L1 side and feeds a unified request into the 2-stage
//              tag-lookup pipeline.  Handles:
//                - AR/AW arbitration (reads preferred to avoid starvation)
//                - Burst-to-word decomposition (len+1 beats, INCR only)
//                - WSTRB capture for write-hit partial updates
//                - Back-pressure: de-asserts ARREADY/AWREADY when MSHR is full
//
//  Stage 0  (this module output):  set_index, req_tag, offset, is_write, id …
//  Stage 1  (in l2_cache_top):     tag compare → hit/miss decision
// =============================================================================

`ifndef L2_REQUEST_PIPELINE_SV
`define L2_REQUEST_PIPELINE_SV

`include "l2_cache_pkg.sv"

module l2_request_pipeline
  import l2_cache_pkg::*;
#(
  parameter int unsigned ADDR_WIDTH  = 40,
  parameter int unsigned DATA_WIDTH  = 64,
  parameter int unsigned INDEX_BITS  = 9,
  parameter int unsigned TAG_BITS    = 25,
  parameter int unsigned OFFSET_BITS = 6,
  parameter int unsigned ID_WIDTH    = 8
)(
  input  logic                     clk,
  input  logic                     rst_n,

  // ── AXI4 Slave read address channel ───────────────────────────────────
  input  logic [ADDR_WIDTH-1:0]    s_axi_araddr,
  input  logic [7:0]               s_axi_arlen,
  input  logic [2:0]               s_axi_arsize,
  input  logic [1:0]               s_axi_arburst,
  input  logic [ID_WIDTH-1:0]      s_axi_arid,
  input  logic                     s_axi_arvalid,
  output logic                     s_axi_arready,

  // ── AXI4 Slave write address channel ──────────────────────────────────
  input  logic [ADDR_WIDTH-1:0]    s_axi_awaddr,
  input  logic [7:0]               s_axi_awlen,
  input  logic [2:0]               s_axi_awsize,
  input  logic [1:0]               s_axi_awburst,
  input  logic [ID_WIDTH-1:0]      s_axi_awid,
  input  logic                     s_axi_awvalid,
  output logic                     s_axi_awready,

  // ── AXI4 Slave write data channel ─────────────────────────────────────
  input  logic [DATA_WIDTH-1:0]    s_axi_wdata,
  input  logic [DATA_WIDTH/8-1:0]  s_axi_wstrb,
  input  logic                     s_axi_wlast,
  input  logic                     s_axi_wvalid,
  output logic                     s_axi_wready,

  // ── Pipeline stage-0 output ───────────────────────────────────────────
  output logic [INDEX_BITS-1:0]    pipe_set_index,
  output logic [TAG_BITS-1:0]      pipe_req_tag,
  output logic [OFFSET_BITS-1:0]   pipe_offset,
  output logic                     pipe_req_valid,
  output logic                     pipe_req_is_write,
  output logic [DATA_WIDTH-1:0]    pipe_req_wdata,
  output logic [DATA_WIDTH/8-1:0]  pipe_req_wstrb,
  output logic [ID_WIDTH-1:0]      pipe_req_id,
  output logic [7:0]               pipe_req_len,   // ARLEN captured with the read
  output logic                     pipe_wlast,     // WLAST of the issued write beat

  // ── Back-pressure from MSHR ───────────────────────────────────────────
  input  logic                     mshr_full,
  // Response engine busy: no new AR accepted while a multi-beat R burst
  // is draining (prevents response/capture interleaving in the top level)
  input  logic                     resp_busy,
  // Incoming line already tracked in MSHR (pending/filling): stall the
  // AR/AW so the request retries after the fill lands and gets its own
  // response, instead of merging into an entry that answers only once
  input  logic                     ar_stall,
  input  logic                     wr_stall,
  // Same-line write already latched/in-flight (AW accepted, W not done):
  // block AR handshakes so a read cannot pass a write to the same line
  input  logic                     wr_inflight_stall,  // High while a request is in the 3-cycle pre-allocation window
  // (issued → stage1 → alloc): the MSHR probe cannot yet see its line,
  // so the front door must stay closed for same-line retries
  output logic                     pipe_busy
);

  // =========================================================================
  // Arbitration FSM
  // Priority: reads preferred when both arrive simultaneously
  //           to avoid CPU instruction-fetch starvation.
  //           After N consecutive reads, one write slot is forced.
  // =========================================================================
  typedef enum logic [1:0] {
    ARB_IDLE  = 2'b00,
    ARB_READ  = 2'b01,
    ARB_WRITE = 2'b10
  } arb_state_t;

  arb_state_t arb_state;
  logic [3:0]  read_streak;    // consecutive reads granted
  localparam   MAX_STREAK = 4'd8;

  // Captured AW+W registers (write address is latched when AW accepted)
  logic [ADDR_WIDTH-1:0]   aw_addr_r;
  logic [7:0]              aw_len_r;
  logic [ID_WIDTH-1:0]     aw_id_r;
  logic                    aw_pending;  // AW accepted, waiting for W
  // Beat walker for multi-beat writes: each accepted W beat advances the
  // word index within the 64B line (same in-line wrap convention as the
  // read response engine). Without it every beat landed on the first
  // beat's word and the last beat's data won.
  logic [2:0]              wr_beat_cnt;

  // Beat counter for burst decomposition
  logic [7:0]              burst_cnt;

  // In-flight window counter: covers issue (T) → stage-1 (T+1) → MSHR
  // alloc (T+2). The MSHR entry only registers at the end of T+2, so the
  // front door must stay closed through the alloc cycle; from T+3 the
  // probe inputs catch same-line retries. Also spaces pipeline issues by
  // ≥4 cycles so payload registers stay stable until q2 consumers run.
  logic [1:0]              inflight_cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      inflight_cnt <= 2'd0;
    end else begin
      if (arb_state == ARB_READ ||
          (arb_state == ARB_WRITE && s_axi_wvalid && s_axi_wready))
        inflight_cnt <= 2'd3;          // request issued → 3 guarded cycles
      else if (inflight_cnt != 2'd0)
        inflight_cnt <= inflight_cnt - 2'd1;
    end
  end

  // AR-handshake lock: an accepted read's line is invisible to the MSHR
  // probe for ~4 cycles; an AW to the same line must not slip in during
  // that window (it would merge into the read's entry and lose its B).
  logic [2:0]              ar_lock;
  logic [ADDR_WIDTH-1:0]   ar_lock_addr;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ar_lock      <= 3'd0;
      ar_lock_addr <= '0;
    end else if (s_axi_arready) begin
      ar_lock      <= 3'd5;            // handshake → entry probe-visible
      ar_lock_addr <= s_axi_araddr;
    end else if (ar_lock != 3'd0) begin
      ar_lock      <= ar_lock - 3'd1;
    end
  end

  // Same-line helpers (64B lines)
  logic ar_matches_pending_wr, aw_matches_ar_lock;
  assign ar_matches_pending_wr = aw_pending &&
      (s_axi_araddr[ADDR_WIDTH-1:6] == aw_addr_r[ADDR_WIDTH-1:6]);
  assign aw_matches_ar_lock    = (ar_lock != 3'd0) &&
      (s_axi_awaddr[ADDR_WIDTH-1:6] == ar_lock_addr[ADDR_WIDTH-1:6]);

  // Per-beat WLAST is captured at issue (pipe_wlast) and aligned to the
  // q2 consumer cycle by the top level — one B per AW burst, not per beat.

  // =========================================================================
  // AW capture
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_pending <= 1'b0;
      aw_addr_r  <= '0;
      aw_len_r   <= '0;
      aw_id_r    <= '0;
      wr_beat_cnt<= 3'd0;
    end else begin
      if (s_axi_awvalid && s_axi_awready) begin
        aw_addr_r  <= s_axi_awaddr;
        aw_len_r   <= s_axi_awlen;
        aw_id_r    <= s_axi_awid;
        aw_pending <= 1'b1;
        wr_beat_cnt<= s_axi_awaddr[5:3];   // word index of the first W beat
      end
      // Advance the word index on every accepted W beat (in-line wrap at 8)
      if (aw_pending && s_axi_wvalid && s_axi_wready) begin
        wr_beat_cnt <= wr_beat_cnt + 3'd1;
      end
      // Clear when write completes (last W beat accepted by pipeline)
      if (aw_pending && s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
        aw_pending <= 1'b0;
      end
    end
  end

  // =========================================================================
  // Arbitration + pipeline output
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      arb_state       <= ARB_IDLE;
      read_streak     <= '0;
      burst_cnt       <= '0;
      pipe_req_len    <= '0;
      pipe_req_valid  <= 1'b0;
      pipe_req_is_write <= 1'b0;
      pipe_set_index  <= '0;
      pipe_req_tag    <= '0;
      pipe_offset     <= '0;
      pipe_req_wdata  <= '0;
      pipe_req_wstrb  <= '0;
      pipe_req_id     <= '0;
      pipe_wlast      <= 1'b0;
    end else begin
      pipe_req_valid <= 1'b0;  // default: no request this cycle

      unique case (arb_state)
        ARB_IDLE: begin
          if (!mshr_full && !pipe_busy) begin
            // Read preferred; break streak to serve write
            if (s_axi_arvalid &&
                (read_streak < MAX_STREAK || !aw_pending)) begin
              arb_state <= ARB_READ;
            end else if (aw_pending && s_axi_wvalid) begin
              arb_state <= ARB_WRITE;
            end
          end
        end

        ARB_READ: begin
          pipe_req_valid    <= 1'b1;
          pipe_req_is_write <= 1'b0;
          pipe_set_index    <= s_axi_araddr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
          pipe_req_tag      <= s_axi_araddr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS];
          pipe_offset       <= s_axi_araddr[OFFSET_BITS-1:0];
          pipe_req_id       <= s_axi_arid;
          pipe_req_len      <= s_axi_arlen;
          read_streak       <= read_streak + 1;
          burst_cnt         <= s_axi_arlen;
          arb_state         <= ARB_IDLE;
        end

        ARB_WRITE: begin
          if (s_axi_wvalid) begin
            pipe_req_valid    <= 1'b1;
            pipe_req_is_write <= 1'b1;
            pipe_set_index    <= aw_addr_r[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
            pipe_req_tag      <= aw_addr_r[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS];
            pipe_offset       <= {3'(wr_beat_cnt), 3'b000};
            pipe_req_wdata    <= s_axi_wdata;
            pipe_req_wstrb    <= s_axi_wstrb;
            pipe_req_id       <= aw_id_r;
            pipe_wlast        <= s_axi_wlast;
            read_streak       <= '0;  // reset read streak
            arb_state         <= ARB_IDLE;
          end
        end

        default: arb_state <= ARB_IDLE;
      endcase
    end
  end

  // =========================================================================
  // READY signals
  // ARREADY: accept when idle + not MSHR full + read selected
  // AWREADY: accept new AW when no AW pending
  // WREADY:  accept W beat when AW pending and pipeline ready for write
  // =========================================================================
  assign s_axi_arready = (arb_state == ARB_IDLE) &&
                         s_axi_arvalid            &&
                         !mshr_full               &&
                         !resp_busy               &&
                         !ar_stall                &&
                         !aw_matches_ar_lock      &&
                         !ar_matches_pending_wr   &&
                         !pipe_busy               &&
                         (read_streak < MAX_STREAK || !aw_pending);

  assign s_axi_awready = !aw_pending && !mshr_full && !wr_stall && !pipe_busy;

  assign s_axi_wready  = aw_pending &&
                         (arb_state == ARB_WRITE) &&
                         !mshr_full;

  // Pre-allocation window: from issue (valid) through stage-1 (q) to the
  // MSHR allocation cycle (q2, entry registers the NEXT edge). During this
  // window the probe inputs cannot see the request's line, so new AR/AW
  // handshakes are held off entirely.
  assign pipe_busy = (inflight_cnt != 2'd0);

  // =========================================================================
  // Assertions
  // =========================================================================
`ifdef SIMULATION

  property p_arready_not_when_mshr_full;
    @(posedge clk) disable iff (!rst_n)
    mshr_full |-> !s_axi_arready;
  endproperty
  ap_ar_bp: assert property (p_arready_not_when_mshr_full)
    else $error("REQ_PIPE: ARREADY asserted while MSHR full");

  property p_awready_not_when_pending;
    @(posedge clk) disable iff (!rst_n)
    aw_pending |-> !s_axi_awready;
  endproperty
  ap_aw_pending: assert property (p_awready_not_when_pending)
    else $error("REQ_PIPE: AWREADY while AW already pending");

`endif

endmodule

`endif // L2_REQUEST_PIPELINE_SV
