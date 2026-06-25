// =============================================================================
// accel_env_pkg.sv  --  Accelerator-specific UVM environment package
//
// Accelerator memory map (APB_AW=10):
//   0x000   A data FIFO  (write, auto-increment ptr)
//   0x040   B data FIFO  (write, auto-increment ptr)
//   0x080   AB CTRL      (write bit[0]=1 resets A/B write ptrs)
//   0x100   CTRL         (bit[0]=start SC, bit[1]=softrst SC)
//   0x104   STATUS       (bit[0]=busy RO, bit[1]=done W1C)
//   0x108   M_DIM        (RW, runtime row count)
//   0x10C   N_DIM        (RW, runtime column count)
//   0x110   INT_EN       (bit[0]=done_en RW)
//   0x114   INT_STAT     (bit[0]=done_irq W1C)
//   0x118   K_DIM        (RW, runtime reduction depth)
//   0x200   C data FIFO  (read, auto-increment ptr)
//   0x280   C CTRL       (write bit[0]=1 resets C read ptr)
//
// Contains (in order):
//   1. RAL: accel_ctrl_reg, accel_status_reg, accel_dim_reg,
//           accel_inten_reg, accel_intstat_reg, accel_reg_block
//   2. Register adapter: accel_reg_adapter
//   3. Sequences: accel_base_seq, accel_load_ab_seq,
//                 accel_compute_seq, accel_read_c_seq
//   4. Scoreboard: accel_scoreboard
//   5. Coverage subscriber: accel_coverage
//   6. Environment: accel_env
// =============================================================================

`ifndef ACCEL_ENV_PKG_SV
`define ACCEL_ENV_PKG_SV

`include "uvm_macros.svh"

package accel_env_pkg;

    import uvm_pkg::*;
    import apb_pkg::*;

    // =========================================================================
    // Address constants
    // =========================================================================
    localparam logic [9:0] ADDR_A_DATA   = 10'h000;
    localparam logic [9:0] ADDR_B_DATA   = 10'h040;
    localparam logic [9:0] ADDR_AB_CTRL  = 10'h080;
    localparam logic [9:0] ADDR_CTRL     = 10'h100;
    localparam logic [9:0] ADDR_STATUS   = 10'h104;
    localparam logic [9:0] ADDR_M_DIM    = 10'h108;
    localparam logic [9:0] ADDR_N_DIM    = 10'h10C;
    localparam logic [9:0] ADDR_INT_EN   = 10'h110;
    localparam logic [9:0] ADDR_INT_STAT = 10'h114;
    localparam logic [9:0] ADDR_K_DIM    = 10'h118;
    localparam logic [9:0] ADDR_C_DATA   = 10'h200;
    localparam logic [9:0] ADDR_C_CTRL   = 10'h280;

    // =========================================================================
    // RAL: Register definitions
    // =========================================================================

    // --- CTRL (0x100): start[0] SC, softrst[1] SC ----------------------------
    class accel_ctrl_reg extends uvm_reg;
        `uvm_object_utils(accel_ctrl_reg)
        uvm_reg_field start;
        uvm_reg_field softrst;
        function new(string name = "accel_ctrl_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        virtual function void build();
            start   = uvm_reg_field::type_id::create("start");
            softrst = uvm_reg_field::type_id::create("softrst");
            // configure(parent, size, lsb, access, volatile, reset, has_reset, is_rand, individually_acc)
            start.configure  (this, 1, 0, "WO", 0, 1'b0, 1, 1, 0);
            softrst.configure(this, 1, 1, "WO", 0, 1'b0, 1, 1, 0);
        endfunction
    endclass : accel_ctrl_reg

    // --- STATUS (0x104): busy[0] RO, done[1] W1C -----------------------------
    class accel_status_reg extends uvm_reg;
        `uvm_object_utils(accel_status_reg)
        uvm_reg_field busy;
        uvm_reg_field done;
        function new(string name = "accel_status_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        virtual function void build();
            busy = uvm_reg_field::type_id::create("busy");
            done = uvm_reg_field::type_id::create("done");
            busy.configure(this, 1, 0, "RO",  1, 1'b0, 1, 0, 0);
            done.configure(this, 1, 1, "W1C", 1, 1'b0, 1, 0, 0);
        endfunction
    endclass : accel_status_reg

    // --- Generic 8-bit dimension register (M_DIM / N_DIM / K_DIM) -----------
    class accel_dim_reg extends uvm_reg;
        `uvm_object_utils(accel_dim_reg)
        uvm_reg_field value;
        function new(string name = "accel_dim_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        virtual function void build();
            value = uvm_reg_field::type_id::create("value");
            value.configure(this, 8, 0, "RW", 0, 8'h0, 1, 1, 0);
        endfunction
    endclass : accel_dim_reg

    // --- INT_EN (0x110): done_en[0] RW ----------------------------------------
    class accel_inten_reg extends uvm_reg;
        `uvm_object_utils(accel_inten_reg)
        uvm_reg_field done_en;
        function new(string name = "accel_inten_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        virtual function void build();
            done_en = uvm_reg_field::type_id::create("done_en");
            done_en.configure(this, 1, 0, "RW", 0, 1'b0, 1, 1, 0);
        endfunction
    endclass : accel_inten_reg

    // --- INT_STAT (0x114): done_irq[0] W1C -----------------------------------
    class accel_intstat_reg extends uvm_reg;
        `uvm_object_utils(accel_intstat_reg)
        uvm_reg_field done_irq;
        function new(string name = "accel_intstat_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        virtual function void build();
            done_irq = uvm_reg_field::type_id::create("done_irq");
            done_irq.configure(this, 1, 0, "W1C", 1, 1'b0, 1, 0, 0);
        endfunction
    endclass : accel_intstat_reg

    // =========================================================================
    // RAL: Register block (base address = 0x100)
    // =========================================================================
    class accel_reg_block extends uvm_reg_block;
        `uvm_object_utils(accel_reg_block)

        accel_ctrl_reg    ctrl;
        accel_status_reg  status_r;   // avoid SV reserved word "status"
        accel_dim_reg     m_dim;
        accel_dim_reg     n_dim;
        accel_inten_reg   int_en;
        accel_intstat_reg int_stat;
        accel_dim_reg     k_dim;

        function new(string name = "accel_reg_block");
            super.new(name, UVM_NO_COVERAGE);
        endfunction

        virtual function void build();
            uvm_reg_map default_map;
            // Base = 0x100 (byte address of CTRL register in APB space)
            // n_bytes = 4 (one 32-bit word per address slot)
            default_map = create_map("default_map", 32'h100, 4, UVM_LITTLE_ENDIAN);

            ctrl     = accel_ctrl_reg::type_id::create("ctrl");
            status_r = accel_status_reg::type_id::create("status_r");
            m_dim    = accel_dim_reg::type_id::create("m_dim");
            n_dim    = accel_dim_reg::type_id::create("n_dim");
            int_en   = accel_inten_reg::type_id::create("int_en");
            int_stat = accel_intstat_reg::type_id::create("int_stat");
            k_dim    = accel_dim_reg::type_id::create("k_dim");

            ctrl.build();     ctrl.configure(this, null, "");
            status_r.build(); status_r.configure(this, null, "");
            m_dim.build();    m_dim.configure(this, null, "");
            n_dim.build();    n_dim.configure(this, null, "");
            int_en.build();   int_en.configure(this, null, "");
            int_stat.build(); int_stat.configure(this, null, "");
            k_dim.build();    k_dim.configure(this, null, "");

            // Byte offsets from base 0x100
            default_map.add_reg(ctrl,     32'h00, "RW");
            default_map.add_reg(status_r, 32'h04, "RW");
            default_map.add_reg(m_dim,    32'h08, "RW");
            default_map.add_reg(n_dim,    32'h0C, "RW");
            default_map.add_reg(int_en,   32'h10, "RW");
            default_map.add_reg(int_stat, 32'h14, "RW");
            default_map.add_reg(k_dim,    32'h18, "RW");

            lock_model();
        endfunction

    endclass : accel_reg_block

    // =========================================================================
    // RAL: APB register adapter
    // =========================================================================
    class accel_reg_adapter extends uvm_reg_adapter;
        `uvm_object_utils(accel_reg_adapter)

        function new(string name = "accel_reg_adapter");
            super.new(name);
            supports_byte_enable = 0;
            provides_responses   = 0;
        endfunction

        // RAL → APB sequence item
        virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
            apb_seq_item item = apb_seq_item::type_id::create("reg2bus_item");
            item.write = (rw.kind == UVM_WRITE) ? 1'b1 : 1'b0;
            item.addr  = rw.addr[9:0];
            item.data  = (rw.kind == UVM_WRITE) ? rw.data[31:0] : 32'h0;
            return item;
        endfunction

        // APB sequence item → RAL
        virtual function void bus2reg(uvm_sequence_item bus_item,
                                      ref uvm_reg_bus_op rw);
            apb_seq_item item;
            if (!$cast(item, bus_item))
                `uvm_fatal("CAST", "bus2reg: failed to cast to apb_seq_item")
            rw.kind   = item.write ? UVM_WRITE : UVM_READ;
            rw.addr   = item.addr;
            rw.data   = item.data;
            rw.status = item.slverr ? UVM_NOT_OK : UVM_IS_OK;
        endfunction

    endclass : accel_reg_adapter

    // =========================================================================
    // accel_base_seq  –  helper tasks shared by all accelerator sequences
    // =========================================================================
    class accel_base_seq extends uvm_sequence #(apb_seq_item);
        `uvm_object_utils(accel_base_seq)

        function new(string name = "accel_base_seq");
            super.new(name);
        endfunction

        // Blocking APB write
        task do_write(input logic [9:0] addr, input logic [31:0] data);
            apb_seq_item item = apb_seq_item::type_id::create("wr_item");
            start_item(item);
            if (!item.randomize() with { write == 1'b1; addr == local::addr; data == local::data; })
                `uvm_fatal("RAND", "do_write: randomize failed")
            finish_item(item);
            if (item.slverr)
                `uvm_error("SLVERR", $sformatf("APB SLVERR on write addr=0x%03x", addr))
        endtask

        // Blocking APB read; returns PRDATA in `data`
        task do_read(input logic [9:0] addr, output logic [31:0] data);
            apb_seq_item item = apb_seq_item::type_id::create("rd_item");
            start_item(item);
            if (!item.randomize() with { write == 1'b0; addr == local::addr; })
                `uvm_fatal("RAND", "do_read: randomize failed")
            finish_item(item);
            if (item.slverr)
                `uvm_error("SLVERR", $sformatf("APB SLVERR on read addr=0x%03x", addr))
            data = item.data;
        endtask

    endclass : accel_base_seq

    // =========================================================================
    // accel_load_ab_seq  –  reset A/B write ptrs, then stream A and B row-major
    //
    // Caller must set a_flat[], b_flat[], and data_w before starting.
    // For DATA_W=16: two int16 elements are packed per 32-bit word, LSB-first.
    // =========================================================================
    class accel_load_ab_seq extends accel_base_seq;
        `uvm_object_utils(accel_load_ab_seq)

        logic signed [15:0] a_flat[];   // M*K signed 16-bit elements (row-major)
        logic signed [15:0] b_flat[];   // K*N signed 16-bit elements (row-major)
        int unsigned        data_w = 16;

        function new(string name = "accel_load_ab_seq");
            super.new(name);
        endfunction

        virtual task body();
            logic [31:0] word;
            int unsigned per_word;
            int unsigned words;

            if (a_flat.size() == 0 || b_flat.size() == 0)
                `uvm_fatal("CFG", "accel_load_ab_seq: a_flat/b_flat not set")

            per_word = 32 / data_w;

            // Reset A/B write pointers
            do_write(ADDR_AB_CTRL, 32'h1);

            // Write A (row-major, packed)
            words = a_flat.size() / per_word;
            for (int i = 0; i < words; i++) begin
                word = '0;
                case (data_w)
                    16: begin
                        word[15:0]  = a_flat[i*2];
                        word[31:16] = a_flat[i*2+1];
                    end
                    8: begin
                        word[ 7: 0] = a_flat[i*4  ][7:0];
                        word[15: 8] = a_flat[i*4+1][7:0];
                        word[23:16] = a_flat[i*4+2][7:0];
                        word[31:24] = a_flat[i*4+3][7:0];
                    end
                    32: word = a_flat[i];
                    default: `uvm_fatal("CFG", $sformatf("Unsupported DATA_W=%0d", data_w))
                endcase
                do_write(ADDR_A_DATA, word);
            end

            // Write B (row-major, packed)
            words = b_flat.size() / per_word;
            for (int i = 0; i < words; i++) begin
                word = '0;
                case (data_w)
                    16: begin
                        word[15:0]  = b_flat[i*2];
                        word[31:16] = b_flat[i*2+1];
                    end
                    8: begin
                        word[ 7: 0] = b_flat[i*4  ][7:0];
                        word[15: 8] = b_flat[i*4+1][7:0];
                        word[23:16] = b_flat[i*4+2][7:0];
                        word[31:24] = b_flat[i*4+3][7:0];
                    end
                    32: word = b_flat[i];
                    default: `uvm_fatal("CFG", $sformatf("Unsupported DATA_W=%0d", data_w))
                endcase
                do_write(ADDR_B_DATA, word);
            end

            `uvm_info("LOAD_AB",
                $sformatf("Loaded A[%0d] B[%0d] (DATA_W=%0d, %0d elem/word)",
                    a_flat.size(), b_flat.size(), data_w, per_word),
                UVM_MEDIUM)
        endtask

    endclass : accel_load_ab_seq

    // =========================================================================
    // accel_compute_seq  –  program dims, assert start, poll STATUS.done
    // =========================================================================
    class accel_compute_seq extends accel_base_seq;
        `uvm_object_utils(accel_compute_seq)

        int unsigned m            = 4;
        int unsigned n            = 4;
        int unsigned k            = 4;
        int unsigned timeout_polls = 500_000;

        function new(string name = "accel_compute_seq");
            super.new(name);
        endfunction

        virtual task body();
            logic [31:0] status_val;
            int poll;

            // Reset C read pointer for this run
            do_write(ADDR_C_CTRL, 32'h1);

            // Program tile dimensions
            do_write(ADDR_M_DIM, 32'(m));
            do_write(ADDR_N_DIM, 32'(n));
            do_write(ADDR_K_DIM, 32'(k));

            // Assert start (self-clearing)
            do_write(ADDR_CTRL, 32'h1);

            // Poll STATUS.done (bit[1]) with timeout
            status_val = '0;
            for (poll = 0; poll < timeout_polls; poll++) begin
                do_read(ADDR_STATUS, status_val);
                if (status_val[1]) break;
            end
            if (poll == timeout_polls)
                `uvm_fatal("TIMEOUT",
                    $sformatf("accel_compute_seq: STATUS.done not set after %0d polls (M=%0d N=%0d K=%0d)",
                              timeout_polls, m, n, k))

            // Clear done flag (W1C: write 1 to bit[1])
            do_write(ADDR_STATUS, 32'h2);

            `uvm_info("COMPUTE",
                $sformatf("Compute done (M=%0d N=%0d K=%0d, polled %0d times)", m, n, k, poll+1),
                UVM_MEDIUM)
        endtask

    endclass : accel_compute_seq

    // =========================================================================
    // accel_read_c_seq  –  drain M*N 32-bit result words from C FIFO
    // =========================================================================
    class accel_read_c_seq extends accel_base_seq;
        `uvm_object_utils(accel_read_c_seq)

        int unsigned m = 4;
        int unsigned n = 4;
        logic signed [31:0] c_data[];  // output array, filled after body()

        function new(string name = "accel_read_c_seq");
            super.new(name);
        endfunction

        virtual task body();
            logic [31:0] rd_val;
            c_data = new[m * n];
            for (int i = 0; i < m * n; i++) begin
                do_read(ADDR_C_DATA, rd_val);
                c_data[i] = $signed(rd_val);
            end
            `uvm_info("READ_C", $sformatf("Read %0d C elements", m * n), UVM_MEDIUM)
        endtask

    endclass : accel_read_c_seq

    // =========================================================================
    // accel_scoreboard
    //
    // Observes all APB transactions via the monitor analysis port.
    // Tracks shadow A/B matrices and C output, then compares against a
    // built-in SV GEMM reference model (DATA_W=16, ACC_W=32 wrap-around).
    //
    // Reactive: comparison is triggered automatically when the last of the
    // expected M*N C reads is observed.  Supports repeated GEMM runs within
    // one test (AB_CTRL write resets shadows for the next run).
    // =========================================================================
    class accel_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(accel_scoreboard)

        uvm_analysis_imp #(apb_seq_item, accel_scoreboard) mon_imp;

        // ---- Shadow state ---------------------------------------------------
        int unsigned        m_dim   = 0;
        int unsigned        n_dim   = 0;
        int unsigned        k_dim   = 0;
        int unsigned        data_w  = 16;  // set via config_db

        logic signed [15:0] a_shadow[$];
        logic signed [15:0] b_shadow[$];
        logic signed [31:0] c_observed[$];

        // ---- Statistics -----------------------------------------------------
        int unsigned check_count = 0;
        int unsigned error_count = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon_imp = new("mon_imp", this);
            void'(uvm_config_db #(int)::get(this, "", "data_w", data_w));
        endfunction

        // Called by UVM analysis infrastructure for every completed transaction
        virtual function void write(apb_seq_item item);
            if (!item.write) begin
                // ---- Read transaction ----------------------------------------
                // C data region: PADDR[9:8]=2'b10, PADDR[7]=0 → 0x200–0x27F
                if (item.addr[9:8] == 2'b10 && !item.addr[7]) begin
                    c_observed.push_back($signed(item.data));
                    if (m_dim > 0 && n_dim > 0 &&
                        c_observed.size() == m_dim * n_dim)
                        do_check();
                end
            end else begin
                // ---- Write transaction ---------------------------------------
                case (item.addr[9:8])
                    // AB region (0x000–0x0FF)
                    2'b00: begin
                        if (item.addr[7]) begin
                            // AB CTRL (0x080): reset shadow matrices
                            a_shadow.delete();
                            b_shadow.delete();
                        end else if (!item.addr[6]) begin
                            // A data (0x000–0x03F): unpack elements LSB-first
                            unpack_elements(item.data, a_shadow);
                        end else begin
                            // B data (0x040–0x07F)
                            unpack_elements(item.data, b_shadow);
                        end
                    end
                    // Control region (0x100–0x1FF): track dimension registers
                    2'b01: begin
                        case (item.addr[7:0])
                            8'h08: m_dim = item.data[7:0];
                            8'h0C: n_dim = item.data[7:0];
                            8'h18: k_dim = item.data[7:0];
                            default: ;
                        endcase
                    end
                    // C region (0x200–0x2FF)
                    2'b10: begin
                        if (item.addr[7]) begin
                            // C CTRL (0x280): reset observed
                            c_observed.delete();
                        end
                    end
                    default: ;
                endcase
            end
        endfunction

        // Unpack a 32-bit APB word into 16-bit signed elements (LSB-first)
        local function void unpack_elements(
            input  logic [31:0]      word,
            ref    logic signed [15:0] shadow[$]
        );
            case (data_w)
                16: begin
                    shadow.push_back($signed(word[15:0]));
                    shadow.push_back($signed(word[31:16]));
                end
                8: begin
                    shadow.push_back($signed({{8{word[ 7]}}, word[ 7: 0]}));
                    shadow.push_back($signed({{8{word[15]}}, word[15: 8]}));
                    shadow.push_back($signed({{8{word[23]}}, word[23:16]}));
                    shadow.push_back($signed({{8{word[31]}}, word[31:24]}));
                end
                32: shadow.push_back($signed(word[15:0]));  // truncate to 16-bit
                default: `uvm_error("SB", $sformatf("Unsupported DATA_W=%0d", data_w))
            endcase
        endfunction

        // Compute golden GEMM (signed 16-bit inputs, 32-bit truncated accumulation)
        local function void compute_golden(
            input int unsigned M, N, K,
            output logic signed [31:0] C_flat[]
        );
            logic signed [31:0] a_ext, b_ext, acc;
            C_flat = new[M * N];
            for (int i = 0; i < M; i++) begin
                for (int j = 0; j < N; j++) begin
                    acc = '0;
                    for (int k = 0; k < K; k++) begin
                        // Sign-extend 16-bit inputs to 32 bits, then multiply
                        // (32-bit truncated product + accumulation = matches RTL)
                        a_ext = 32'(a_shadow[i*K + k]);
                        b_ext = 32'(b_shadow[k*N + j]);
                        acc   = acc + a_ext * b_ext;
                    end
                    C_flat[i*N + j] = acc;
                end
            end
        endfunction

        local function void do_check();
            logic signed [31:0] c_golden[];
            bit local_ok = 1;

            // Sanity: enough shadow data for the declared dimensions
            if (a_shadow.size() < m_dim * k_dim) begin
                `uvm_error("SB_SIZE",
                    $sformatf("A shadow too small: have %0d, need %0d (M=%0d K=%0d)",
                              a_shadow.size(), m_dim * k_dim, m_dim, k_dim))
                c_observed.delete();
                return;
            end
            if (b_shadow.size() < k_dim * n_dim) begin
                `uvm_error("SB_SIZE",
                    $sformatf("B shadow too small: have %0d, need %0d (K=%0d N=%0d)",
                              b_shadow.size(), k_dim * n_dim, k_dim, n_dim))
                c_observed.delete();
                return;
            end

            compute_golden(m_dim, n_dim, k_dim, c_golden);

            for (int i = 0; i < m_dim * n_dim; i++) begin
                if (c_observed[i] !== c_golden[i]) begin
                    `uvm_error("SB_MISMATCH",
                        $sformatf("C[%0d]: got=0x%08x expected=0x%08x  (M=%0d N=%0d K=%0d)",
                                  i, c_observed[i], c_golden[i], m_dim, n_dim, k_dim))
                    local_ok = 0;
                    error_count++;
                end
            end

            if (local_ok)
                `uvm_info("SB_PASS",
                    $sformatf("GEMM check PASS (M=%0d N=%0d K=%0d)", m_dim, n_dim, k_dim),
                    UVM_LOW)

            check_count++;
            c_observed.delete();   // reset for the next run
        endfunction

        virtual function void check_phase(uvm_phase phase);
            if (check_count == 0)
                `uvm_warning("SB_NOCHECKS", "Scoreboard: no GEMM comparisons performed")
            else
                `uvm_info("SB_SUMMARY",
                    $sformatf("Scoreboard: %0d check(s), %0d error(s)",
                              check_count, error_count),
                    UVM_LOW)
            if (error_count > 0)
                `uvm_error("SB_FAIL",
                    $sformatf("%0d GEMM comparison(s) failed", error_count))
        endfunction

    endclass : accel_scoreboard

    // =========================================================================
    // accel_coverage  –  functional coverage subscriber
    //
    // Receives APB transactions from the monitor; updates three covergroups:
    //   apb_op_cg   – write/read × address region
    //   accel_dim_cg – M/N/K dimension bins (small/medium/large)
    //   accel_data_cg – input data value bins
    // =========================================================================
    class accel_coverage extends uvm_subscriber #(apb_seq_item);
        `uvm_component_utils(accel_coverage)

        // ---- Sampled values (set before each covergroup.sample()) -----------
        bit           cv_write;
        logic [9:0]   cv_addr;
        logic [31:0]  cv_data;
        int unsigned  cv_m = 4, cv_n = 4, cv_k = 4;

        // ---- Coverage groups ------------------------------------------------
        covergroup apb_op_cg;
            cp_write: coverpoint cv_write {
                bins write_txn = {1'b1};
                bins read_txn  = {1'b0};
            }
            cp_region: coverpoint cv_addr[9:8] {
                bins ab_region   = {2'b00};
                bins ctrl_region = {2'b01};
                bins c_region    = {2'b10};
            }
            cp_op_x_region: cross cp_write, cp_region;
        endgroup : apb_op_cg

        covergroup accel_dim_cg;
            cp_m: coverpoint cv_m {
                bins sz_1_4  = {[1 : 4]};
                bins sz_5_8  = {[5 : 8]};
                bins sz_9_16 = {[9 :16]};
            }
            cp_n: coverpoint cv_n {
                bins sz_1_4  = {[1 : 4]};
                bins sz_5_8  = {[5 : 8]};
                bins sz_9_16 = {[9 :16]};
            }
            cp_k: coverpoint cv_k {
                bins sz_1_4  = {[1 : 4]};
                bins sz_5_8  = {[5 : 8]};
                bins sz_9_16 = {[9 :16]};
            }
        endgroup : accel_dim_cg

        covergroup accel_data_cg;
            cp_data_lo: coverpoint cv_data[15:0] {
                bins zero     = {16'h0000};
                bins all_ones = {16'hFFFF};
                bins positive = {[16'h0001 : 16'h7FFF]};
                bins negative = {[16'h8001 : 16'hFFFE]};
                bins min_neg  = {16'h8000};
            }
        endgroup : accel_data_cg

        function new(string name, uvm_component parent);
            super.new(name, parent);
            apb_op_cg   = new();
            accel_dim_cg = new();
            accel_data_cg = new();
        endfunction

        virtual function void write(apb_seq_item t);
            cv_write = t.write;
            cv_addr  = t.addr;
            cv_data  = t.data;

            // Track dimension register writes for dim covergroup
            if (t.write) begin
                case (t.addr)
                    ADDR_M_DIM: cv_m = t.data[7:0];
                    ADDR_N_DIM: cv_n = t.data[7:0];
                    ADDR_K_DIM: cv_k = t.data[7:0];
                    default: ;
                endcase
            end

            apb_op_cg.sample();
            accel_dim_cg.sample();
            // Sample data coverage for A/B writes only
            if (t.write && t.addr[9:8] == 2'b00 && !t.addr[7])
                accel_data_cg.sample();
        endfunction

        virtual function void report_phase(uvm_phase phase);
            `uvm_info("COV", $sformatf("APB op coverage  : %5.1f%%", apb_op_cg.get_coverage()),   UVM_NONE)
            `uvm_info("COV", $sformatf("Dimension coverage: %5.1f%%", accel_dim_cg.get_coverage()), UVM_NONE)
            `uvm_info("COV", $sformatf("Data coverage    : %5.1f%%", accel_data_cg.get_coverage()), UVM_NONE)
        endfunction

    endclass : accel_coverage

    // =========================================================================
    // accel_env  –  top-level environment
    //
    // Instantiates:
    //   agent         – APB UVC (active)
    //   reg_model     – RAL register block
    //   reg_adapter   – APB ↔ RAL bridge
    //   reg_predictor – updates RAL mirror from observed APB bus traffic
    //   sb            – GEMM scoreboard
    //   cov           – functional coverage subscriber
    // =========================================================================
    class accel_env extends uvm_env;
        `uvm_component_utils(accel_env)

        apb_agent                             agent;
        accel_reg_block                       reg_model;
        accel_reg_adapter                     reg_adapter;
        uvm_reg_predictor #(apb_seq_item)     reg_predictor;
        accel_scoreboard                      sb;
        accel_coverage                        cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            agent         = apb_agent::type_id::create("agent", this);
            reg_model     = accel_reg_block::type_id::create("reg_model");
            reg_model.build();
            reg_adapter   = accel_reg_adapter::type_id::create("reg_adapter");
            reg_predictor = uvm_reg_predictor #(apb_seq_item)::type_id::create(
                                "reg_predictor", this);
            sb            = accel_scoreboard::type_id::create("sb",  this);
            cov           = accel_coverage::type_id::create("cov", this);
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);

            // Connect RAL to APB sequencer (enables reg_model.ctrl.write() etc.)
            reg_model.default_map.set_sequencer(agent.seqr, reg_adapter);
            reg_model.default_map.set_auto_predict(0); // use explicit predictor

            // Predictor keeps RAL mirror in sync with observed bus traffic
            reg_predictor.map     = reg_model.default_map;
            reg_predictor.adapter = reg_adapter;
            agent.ap.connect(reg_predictor.bus_in);

            // Scoreboard and coverage receive every completed transaction
            agent.ap.connect(sb.mon_imp);
            agent.ap.connect(cov.analysis_export);
        endfunction

    endclass : accel_env

endpackage : accel_env_pkg

`endif // ACCEL_ENV_PKG_SV
