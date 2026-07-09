// =============================================================================
// apb_pkg.sv  --  APB Universal Verification Component (UVC)
//
// Contains:
//   apb_seq_item  – transaction object (addr/data/write/slverr)
//   apb_config    – agent configuration (virtual interface + active mode)
//   apb_sequencer – extends uvm_sequencer #(apb_seq_item)
//   apb_driver    – SETUP → ACCESS → PREADY handshake; uses clocking block
//   apb_monitor   – samples completed ACCESS phase; writes to analysis port
//   apb_agent     – aggregates driver + monitor + sequencer
// =============================================================================

`ifndef APB_PKG_SV
`define APB_PKG_SV

// uvm_macros.svh must be included at file scope (outside the package) so
// that preprocessor `define constants like UVM_ALL_ON are visible when the
// uvm_field_* macros expand inside the package body.
`include "uvm_macros.svh"

package apb_pkg;

    import uvm_pkg::*;

    // =========================================================================
    // apb_seq_item
    // =========================================================================
    class apb_seq_item extends uvm_sequence_item;

        // Field declarations must come BEFORE the uvm_object_utils macros so
        // that the macro expansions can reference them by name.
        rand logic [9:0]  addr;
        rand logic [31:0] data;
        rand bit          write;   // 1 = write, 0 = read
        bit               slverr;  // captured by driver from PSLVERR

        `uvm_object_utils_begin(apb_seq_item)
            `uvm_field_int(addr,   UVM_ALL_ON)
            `uvm_field_int(data,   UVM_ALL_ON)
            `uvm_field_int(write,  UVM_ALL_ON)
            `uvm_field_int(slverr, UVM_ALL_ON)
        `uvm_object_utils_end

        // Word-aligned address
        constraint c_word_align { addr[1:0] == 2'b00; }

        function new(string name = "apb_seq_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("APB %s addr=0x%03x data=0x%08x slverr=%b",
                             write ? "WRITE" : "READ", addr, data, slverr);
        endfunction

    endclass : apb_seq_item

    // =========================================================================
    // apb_config
    // =========================================================================
    class apb_config extends uvm_object;

        `uvm_object_utils(apb_config)

        virtual apb_if              vif;
        uvm_active_passive_enum     is_active = UVM_ACTIVE;

        function new(string name = "apb_config");
            super.new(name);
        endfunction

    endclass : apb_config

    // =========================================================================
    // apb_sequencer
    // =========================================================================
    class apb_sequencer extends uvm_sequencer #(apb_seq_item);

        `uvm_component_utils(apb_sequencer)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

    endclass : apb_sequencer

    // =========================================================================
    // apb_driver
    //
    // Timing (all edges are posedge clk via driver_cb):
    //   cycle 0 : get item; drive PADDR/PWDATA/PWRITE; PSEL=1, PENABLE=0  (SETUP)
    //   cycle 1 : PENABLE=1                                                 (ACCESS)
    //   cycle 2+: sample PREADY; stay in ACCESS if PREADY=0
    //   capture : once PREADY=1 capture PRDATA/PSLVERR; deassert PSEL/PENABLE
    // =========================================================================
    class apb_driver extends uvm_driver #(apb_seq_item);

        `uvm_component_utils(apb_driver)

        virtual apb_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF",
                    $sformatf("apb_driver: no virtual interface for '%s'", get_full_name()))
        endfunction

        virtual task run_phase(uvm_phase phase);
            apb_seq_item req;
            // Idle bus before reset de-asserts
            vif.driver_cb.PSEL    <= 1'b0;
            vif.driver_cb.PENABLE <= 1'b0;
            vif.driver_cb.PWRITE  <= 1'b0;
            vif.driver_cb.PADDR   <= '0;
            vif.driver_cb.PWDATA  <= '0;
            // Wait for reset to de-assert
            wait (!vif.reset_int);
            @(vif.driver_cb);
            forever begin
                seq_item_port.get_next_item(req);
                drive_apb(req);
                seq_item_port.item_done();
            end
        endtask

        protected task drive_apb(apb_seq_item item);
            // ---- SETUP phase ------------------------------------------------
            @(vif.driver_cb);
            vif.driver_cb.PADDR   <= item.addr;
            vif.driver_cb.PWDATA  <= item.write ? item.data : 32'h0;
            vif.driver_cb.PWRITE  <= item.write;
            vif.driver_cb.PSEL    <= 1'b1;
            vif.driver_cb.PENABLE <= 1'b0;

            // ---- ACCESS phase -----------------------------------------------
            @(vif.driver_cb);
            vif.driver_cb.PENABLE <= 1'b1;

            // ---- Wait PREADY ------------------------------------------------
            @(vif.driver_cb);
            while (!vif.driver_cb.PREADY)
                @(vif.driver_cb);

            // ---- Capture response -------------------------------------------
            item.slverr = vif.driver_cb.PSLVERR;
            if (!item.write)
                item.data = vif.driver_cb.PRDATA;

            // ---- De-assert --------------------------------------------------
            vif.driver_cb.PSEL    <= 1'b0;
            vif.driver_cb.PENABLE <= 1'b0;
        endtask

    endclass : apb_driver

    // =========================================================================
    // apb_monitor
    //
    // Samples the bus every clock.  Fires once per completed ACCESS phase
    // (PSEL & PENABLE & PREADY all high simultaneously).
    // For a READ the captured data field holds PRDATA; for a WRITE it holds PWDATA.
    // =========================================================================
    class apb_monitor extends uvm_monitor;

        `uvm_component_utils(apb_monitor)

        virtual apb_if                   vif;
        uvm_analysis_port #(apb_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF",
                    $sformatf("apb_monitor: no virtual interface for '%s'", get_full_name()))
        endfunction

        virtual task run_phase(uvm_phase phase);
            apb_seq_item item;
            wait (!vif.reset_int);
            forever begin
                @(vif.monitor_cb);
                if (vif.monitor_cb.PSEL    === 1'b1 &&
                    vif.monitor_cb.PENABLE === 1'b1 &&
                    vif.monitor_cb.PREADY  === 1'b1) begin
                    item        = apb_seq_item::type_id::create("mon_item");
                    item.addr   = vif.monitor_cb.PADDR;
                    item.write  = vif.monitor_cb.PWRITE;
                    item.data   = vif.monitor_cb.PWRITE ?
                                      vif.monitor_cb.PWDATA : vif.monitor_cb.PRDATA;
                    item.slverr = vif.monitor_cb.PSLVERR;
                    `uvm_info("APB_MON", item.convert2string(), UVM_HIGH)
                    ap.write(item);
                end
            end
        endtask

    endclass : apb_monitor

    // =========================================================================
    // apb_agent
    //
    // When UVM_ACTIVE: instantiates driver + sequencer + monitor.
    // When UVM_PASSIVE: monitor only (useful for passive snooping).
    // The agent forwards the monitor's analysis port via its own ap port so
    // env components can subscribe without knowing the internal hierarchy.
    // =========================================================================
    class apb_agent extends uvm_agent;

        `uvm_component_utils(apb_agent)

        apb_sequencer seqr;
        apb_driver    drv;
        apb_monitor   mon;

        uvm_analysis_port #(apb_seq_item) ap;  // forwarded from monitor.ap

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap  = new("ap", this);
            mon = apb_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                seqr = apb_sequencer::type_id::create("seqr", this);
                drv  = apb_driver::type_id::create("drv",  this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(seqr.seq_item_export);
            mon.ap.connect(ap);
        endfunction

    endclass : apb_agent

endpackage : apb_pkg

`endif // APB_PKG_SV
