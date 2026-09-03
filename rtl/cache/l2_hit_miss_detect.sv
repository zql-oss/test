// =============================================================================
// Module     : l2_hit_miss_detect
// Description: Parallel tag comparator for N-way set-associative L2 cache.
//              One comparator per way, results OR'd for hit_any.
//              One-hot → binary encoder for hit_way_bin.
//              Checks: valid bit AND tag match.
//
// Timing note: This is on the critical path (tag RAM Q → hit_any → data MUX).
//              For 8/16-way designs, register the output and use a 2-cycle
//              MCP constraint: set_multicycle_path -setup 2.
// =============================================================================

`ifndef L2_HIT_MISS_DETECT_SV
`define L2_HIT_MISS_DETECT_SV

module l2_hit_miss_detect #(
  parameter int unsigned WAYS     = 4,
  parameter int unsigned TAG_BITS = 26,

  localparam int unsigned WAY_W = $clog2(WAYS)
)(
  // Request tag (from pipeline stage 0)
  input  logic [TAG_BITS-1:0]   req_tag,

  // Tag array outputs (registered, 1-cycle after request)
  input  logic [TAG_BITS-1:0]   tag_rd_data [WAYS],
  input  logic                  valid_bit   [WAYS],

  // Hit/miss outputs
  output logic                  hit_any,
  output logic [WAYS-1:0]       hit_way_oh,   // one-hot, one bit per way
  output logic [WAY_W-1:0]      hit_way_bin   // binary encoded hit way
);

  // =========================================================================
  // Per-way comparators — fully combinational
  // One comparator tree per way; synthesis can parallelize all WAYS
  // =========================================================================
  always_comb begin : tag_compare
    for (int w = 0; w < WAYS; w++) begin
      hit_way_oh[w] = valid_bit[w] && (tag_rd_data[w] == req_tag);
    end
  end

  // =========================================================================
  // Aggregate hit — OR reduction
  // =========================================================================
  assign hit_any = |hit_way_oh;

  // =========================================================================
  // One-hot to binary encoder — priority: lowest matching way wins
  // (in a well-formed cache at most one way should hit; this handles
  //  any temporary multi-hit during fill for safety)
  // =========================================================================
  always_comb begin : oh2bin_encode
    hit_way_bin = '0;
    for (int w = WAYS-1; w >= 0; w--) begin
      if (hit_way_oh[w]) hit_way_bin = WAY_W'(w);
    end
  end

  // =========================================================================
  // Assertions
  // =========================================================================
`ifdef SIMULATION

  // NOTE: purely combinational module — no clock port, so the invariants are
  // checked as immediate assertions (equivalent to the original global-clock
  // properties, which were illegal SV outside a global clocking block).
  always_comb begin
    // At most one way should hit (MESI protocol maintains this invariant)
    assert ($onehot0(hit_way_oh))
      else $error("HIT_MISS: multi-way hit detected (oh=0b%0b) — MESI violation!",
                  hit_way_oh);
    // hit_way_bin must be zero when no hit
    if (!hit_any)
      assert (hit_way_bin == '0)
        else $error("HIT_MISS: hit_way_bin non-zero on miss");
  end

`endif

endmodule

`endif // L2_HIT_MISS_DETECT_SV
