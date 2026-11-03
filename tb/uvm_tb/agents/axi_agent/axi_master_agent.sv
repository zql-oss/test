// =============================================================================
// File       : axi_master_agent.sv
// Description: UVM AXI4 master agent for the memory side of the L2 cache DUT.
//              Acts as a slave to the DUT's AXI master interface — it receives
//              fill read requests and dirty write-backs, responds with
//              configurable latency, and monitors all transactions for the
//              scoreboard.
//
//              Modes:
//                ACTIVE  — drives RDATA responses and BVALID
//                PASSIVE — monitor only (for snoop-on-memory-bus scenarios)
//
//              Configurable via uvm_config_db:
//                "mem_latency" (int) — cycles of read latency before RVALID
//                "mem_data_mode" (string) — "random" | "address_based"
// =============================================================================

`ifndef AXI_MASTER_AGENT_SV
`define AXI_MASTER_AGENT_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
`include "l2_seq_items.sv"

// Reuse axi4_if from axi_slave_agent.sv (already compiled via +incdir)
// Sequencer reuse
// sequencer typedef moved to l2_seq_items.sv (compile-order dependency)

// =============================================================================
// Memory responder driver  (AXI slave side — responds to DUT master)
// =============================================================================
class axi_master_driver extends uvm_driver #(axi_seq_item);
  `uvm_component_utils(axi_master_driver)

  virtual axi4_if.mem vif;

  // Configurable latency (cycles before RVALID is asserted after ARVALID)
  int mem_latency     = 20;
  // Data generation mode
  string data_mode    = "address_based";

  // Internal memory model — stores data written by DUT write-backs
  logic [63:0] mem_model [logic[39:3]];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi4_if.mem)::get(
          this, "", "axi_vif", vif))
      `uvm_fatal("MEM_DRV", "No virtual interface for axi_master_driver")
    void'(uvm_config_db #(int)::get(this, "", "mem_latency", mem_latency));
    void'(uvm_config_db #(string)::get(this, "", "mem_data_mode", data_mode));
  endfunction

  task run_phase(uvm_phase phase);
    // Idle defaults
    vif.mem_cb.arready <= 1'b0;
    vif.mem_cb.rdata   <= '0;
    vif.mem_cb.rresp   <= 2'b00;
    vif.mem_cb.rlast   <= 1'b0;
    vif.mem_cb.rid     <= '0;
    vif.mem_cb.rvalid  <= 1'b0;
    vif.mem_cb.awready <= 1'b0;
    vif.mem_cb.wready  <= 1'b0;
    vif.mem_cb.bresp   <= 2'b00;
    vif.mem_cb.bid     <= '0;
    vif.mem_cb.bvalid  <= 1'b0;

    @(posedge vif.clk iff vif.rst_n);

    // Handle reads and writes concurrently
    fork
      handle_reads();
      handle_writes();
    join
  endtask

  // ---------------------------------------------------------------------------
  // Handle fill read transactions from the DUT AXI master
  // ---------------------------------------------------------------------------
  task handle_reads();
    logic [39:0]  req_addr;
    logic [7:0]   req_len;
    logic [7:0]   req_id;

    forever begin
      // ── Accept AR ────────────────────────────────────────────────────
      @(vif.mem_cb);
      vif.mem_cb.arready <= 1'b1;
      do @(vif.mem_cb); while (!vif.mem_cb.arvalid);

      req_addr = vif.mem_cb.araddr;
      req_len  = vif.mem_cb.arlen;
      req_id   = vif.mem_cb.arid;

      vif.mem_cb.arready <= 1'b0;

      // ── Simulated memory latency ──────────────────────────────────────
      repeat (mem_latency) @(vif.mem_cb);

      // ── Return R beats ────────────────────────────────────────────────
      vif.mem_cb.rvalid <= 1'b1;
      for (int beat = 0; beat <= req_len; beat++) begin
        logic [63:0] rdata_word;
        logic [39:0] beat_addr;

        beat_addr  = req_addr + 40'(beat * 8);

        // Return stored data if DUT previously wrote it, else synthesize
        if (mem_model.exists(beat_addr[39:3]))
          rdata_word = mem_model[beat_addr[39:3]];
        else if (data_mode == "address_based")
          rdata_word = {beat_addr[39:8], 8'(beat_addr[7:0] ^ 8'hAB)};
        else
          rdata_word = $urandom_range(0, 32'hFFFFFFFF) |
                       ({$urandom_range(0, 32'hFFFFFFFF)} << 32);

        vif.mem_cb.rdata  <= rdata_word;
        vif.mem_cb.rresp  <= 2'b00;   // OKAY
        vif.mem_cb.rid    <= req_id;
        vif.mem_cb.rlast  <= (beat == req_len);

        do @(vif.mem_cb); while (!vif.mem_cb.rready);
      end

      vif.mem_cb.rvalid <= 1'b0;
      vif.mem_cb.rlast  <= 1'b0;

      `uvm_info("MEM_DRV", $sformatf(
        "Fill served: addr=0x%0h len=%0d lat=%0d", req_addr, req_len, mem_latency),
        UVM_HIGH)
    end
  endtask

  // ---------------------------------------------------------------------------
  // Handle dirty write-back transactions from the DUT AXI master
  // ---------------------------------------------------------------------------
  task handle_writes();
    logic [39:0]  wr_addr;
    logic [7:0]   wr_len;
    logic [7:0]   wr_id;
    int           beat_cnt;

    forever begin
      // Accept AW
      @(vif.mem_cb);
      vif.mem_cb.awready <= 1'b1;
      do @(vif.mem_cb); while (!vif.mem_cb.awvalid);
      wr_addr = vif.mem_cb.awaddr;
      wr_len  = vif.mem_cb.awlen;
      wr_id   = vif.mem_cb.awid;
      vif.mem_cb.awready <= 1'b0;

      // Accept W beats
      beat_cnt = 0;
      vif.mem_cb.wready <= 1'b1;
      forever begin
        do @(vif.mem_cb); while (!vif.mem_cb.wvalid);
        begin
          logic [39:0] word_addr = wr_addr + 40'(beat_cnt * 8);
          mem_model[word_addr[39:3]] = vif.mem_cb.wdata;
        end
        if (vif.mem_cb.wlast) break;
        beat_cnt++;
      end
      vif.mem_cb.wready <= 1'b0;

      // B response — 2 cycle delay
      repeat(2) @(vif.mem_cb);
      vif.mem_cb.bid    <= wr_id;
      vif.mem_cb.bresp  <= 2'b00;
      vif.mem_cb.bvalid <= 1'b1;
      do @(vif.mem_cb); while (!vif.mem_cb.bready);
      vif.mem_cb.bvalid <= 1'b0;

      `uvm_info("MEM_DRV", $sformatf(
        "Write-back accepted: addr=0x%0h beats=%0d", wr_addr, beat_cnt+1),
        UVM_HIGH)
    end
  endtask

endclass

// =============================================================================
// Memory-side monitor — captures all fills and write-backs
// =============================================================================
class axi_master_monitor extends uvm_monitor;
  `uvm_component_utils(axi_master_monitor)

  virtual axi4_if.monitor_raw vif;
  uvm_analysis_port #(axi_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual axi4_if.monitor_raw)::get(
          this, "", "axi_vif_mon", vif))
      `uvm_fatal("MEM_MON", "No virtual interface for axi_master_monitor")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_fills();
      monitor_writebacks();
    join
  endtask

  task monitor_fills();
    axi_seq_item item;
    // Reset guard — avoid phantom handshakes while DUT outputs are X
    wait (vif.rst_n === 1'b1);
    @(posedge vif.clk);
    forever begin
      // Wait for AR handshake (raw wire sampling)
      while (!(vif.arvalid === 1'b1 && vif.arready === 1'b1))
        @(posedge vif.clk);
      item          = axi_seq_item::type_id::create("fill_mon");
      item.addr     = vif.araddr;
      item.len      = vif.arlen;
      item.id       = vif.arid;
      item.is_write = 1'b0;
      item.rdata    = new[item.len + 1];

      // Collect R beats until RLAST
      for (int b = 0; b <= item.len; b++) begin
        while (!(vif.rvalid === 1'b1 && vif.rready === 1'b1))
          @(posedge vif.clk);
        item.rdata[b] = vif.rdata;
        item.resp     = vif.rresp;
        if (vif.rlast || b == item.len) begin
          if (b < item.len) begin
            // Early termination — shrink but PRESERVE collected beats
            axi_seq_item_beat_shrink(item.rdata, b + 1);
          end
          break;
        end
        @(posedge vif.clk);
      end
      ap.write(item);
      `uvm_info("MEM_MON", $sformatf(
        "Fill monitored: addr=0x%0h len=%0d", item.addr, item.len), UVM_HIGH)
    end
  endtask

  task monitor_writebacks();
    axi_seq_item item;
    // Reset guard — see monitor_fills
    wait (vif.rst_n === 1'b1);
    @(posedge vif.clk);
    forever begin
      while (!(vif.awvalid === 1'b1 && vif.awready === 1'b1))
        @(posedge vif.clk);
      item          = axi_seq_item::type_id::create("wb_mon");
      item.addr     = vif.awaddr;
      item.len      = vif.awlen;
      item.id       = vif.awid;
      item.is_write = 1'b1;
      item.wdata    = new[item.len + 1];
      item.wstrb    = new[item.len + 1];

      for (int b = 0; b <= item.len; b++) begin
        while (!(vif.wvalid === 1'b1 && vif.wready === 1'b1))
          @(posedge vif.clk);
        item.wdata[b] = vif.wdata;
        item.wstrb[b] = vif.wstrb;
        if (vif.wlast || b == item.len) begin
          if (b < item.len) begin
            item.wdata = new[b + 1];
            item.wstrb = new[b + 1];
          end
          break;
        end
        @(posedge vif.clk);
      end

      while (!(vif.bvalid === 1'b1 && vif.bready === 1'b1))
        @(posedge vif.clk);
      item.resp = vif.bresp;
      ap.write(item);
      `uvm_info("MEM_MON", $sformatf(
        "Writeback monitored: addr=0x%0h beats=%0d", item.addr, item.len+1), UVM_HIGH)
    end
  endtask

endclass

// =============================================================================
// AXI Master Agent (memory-side)
// =============================================================================
class axi_master_agent extends uvm_agent;
  `uvm_component_utils(axi_master_agent)

  axi_master_driver  driver;
  axi_master_monitor monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = axi_master_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE)
      driver = axi_master_driver::type_id::create("driver", this);
  endfunction

endclass

`endif // AXI_MASTER_AGENT_SV
