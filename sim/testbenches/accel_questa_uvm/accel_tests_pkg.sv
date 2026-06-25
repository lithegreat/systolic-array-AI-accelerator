// =============================================================================
// accel_tests_pkg.sv  --  Accelerator UVM test classes
//
// Tests (all extend accel_base_test):
//   accel_zero_test         – A=0, B=random → C must be all-zeros
//   accel_identity_test     – A=I, B=I → C=I (tile-diagonal)
//   accel_checkerboard_test – alternating ±127 patterns, scoreboard comparison
//   accel_random_test       – constrained-random, 4 deterministic seeds
//   accel_coverage_test     – dimension-randomizing loop until ≥95% dim coverage
//
// All tests run through the helper task run_gemm() which:
//   1. Starts accel_load_ab_seq (stream A and B)
//   2. Starts accel_compute_seq (set dims, assert start, poll done)
//   The scoreboard checks the result reactively when C reads arrive.
// =============================================================================

`ifndef ACCEL_TESTS_PKG_SV
`define ACCEL_TESTS_PKG_SV

`include "uvm_macros.svh"

package accel_tests_pkg;

    import uvm_pkg::*;
    import apb_pkg::*;
    import accel_env_pkg::*;

    // =========================================================================
    // accel_base_test  –  shared setup: VIF, config_db, env creation
    // =========================================================================
    class accel_base_test extends uvm_test;
        `uvm_component_utils(accel_base_test)

        accel_env      env;
        virtual apb_if vif;

        // Default tile dimensions (override in subclass or via plusargs)
        int unsigned M      = 4;
        int unsigned N      = 4;
        int unsigned K      = 4;
        int unsigned DATA_W = 16;
        int unsigned ACC_W  = 32;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            // Grab virtual interface registered by tb_top
            if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "accel_base_test: no virtual interface in config_db")

            // Push it down to all agent sub-components
            uvm_config_db #(virtual apb_if)::set(this, "env.agent.*", "vif", vif);

            // Pass DATA_W to scoreboard
            uvm_config_db #(int)::set(this, "env.sb", "data_w", DATA_W);

            env = accel_env::type_id::create("env", this);
        endfunction

        virtual function void end_of_elaboration_phase(uvm_phase phase);
            uvm_top.print_topology();
        endfunction

        virtual task run_phase(uvm_phase phase);
            phase.raise_objection(this, "test started");
            do_test(phase);
            phase.drop_objection(this, "test done");
        endtask

        // Override in derived tests
        protected virtual task do_test(uvm_phase phase);
            `uvm_info(get_type_name(), "Base test: no scenario defined", UVM_MEDIUM)
        endtask

        virtual function void final_phase(uvm_phase phase);
            uvm_report_server svr = uvm_report_server::get_server();
            int unsigned n_err   = svr.get_severity_count(UVM_ERROR);
            int unsigned n_fatal = svr.get_severity_count(UVM_FATAL);
            if (n_fatal + n_err > 0)
                `uvm_error("TEST_FAIL",
                    $sformatf("FAILED: %0d fatal(s) + %0d error(s)", n_fatal, n_err))
            else
                `uvm_info("TEST_PASS", "PASSED", UVM_NONE)
        endfunction

        // =====================================================================
        // run_gemm()  –  shared helper used by all concrete tests
        //
        // Streams a_flat (M*K) and b_flat (K*N) to the DUT, programs dims,
        // asserts start, and polls until done.  The scoreboard fires
        // automatically when the expected M*N C reads are observed.
        // =====================================================================
        protected task run_gemm(
            input logic signed [15:0] a_flat[],
            input logic signed [15:0] b_flat[],
            input int unsigned        m,
            input int unsigned        n,
            input int unsigned        k
        );
            accel_load_ab_seq  load_seq;
            accel_compute_seq  comp_seq;

            load_seq        = accel_load_ab_seq::type_id::create("load_seq");
            load_seq.a_flat = a_flat;
            load_seq.b_flat = b_flat;
            load_seq.data_w = DATA_W;
            load_seq.start(env.agent.seqr);

            comp_seq   = accel_compute_seq::type_id::create("comp_seq");
            comp_seq.m = m;
            comp_seq.n = n;
            comp_seq.k = k;
            comp_seq.start(env.agent.seqr);
        endtask

    endclass : accel_base_test

    // =========================================================================
    // accel_zero_test  –  A=0, B=random → C must be all-zeros
    // =========================================================================
    class accel_zero_test extends accel_base_test;
        `uvm_component_utils(accel_zero_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        protected virtual task do_test(uvm_phase phase);
            logic signed [15:0] a_flat[];
            logic signed [15:0] b_flat[];

            a_flat = new[M * K];
            b_flat = new[K * N];

            // A = all zeros; B = random (result must be zero regardless of B)
            foreach (a_flat[i]) a_flat[i] = '0;
            foreach (b_flat[i]) b_flat[i] = $signed($urandom());

            `uvm_info(get_type_name(),
                $sformatf("Zero test: M=%0d N=%0d K=%0d", M, N, K), UVM_LOW)
            run_gemm(a_flat, b_flat, M, N, K);
        endtask

    endclass : accel_zero_test

    // =========================================================================
    // accel_identity_test  –  A=I, B=I → C=I
    //
    // Constructs the identity matrix for the configured tile size.
    // Off-diagonal elements are zero; diagonal elements are 1.
    // =========================================================================
    class accel_identity_test extends accel_base_test;
        `uvm_component_utils(accel_identity_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        protected virtual task do_test(uvm_phase phase);
            logic signed [15:0] a_flat[];
            logic signed [15:0] b_flat[];

            a_flat = new[M * K];
            b_flat = new[K * N];

            // Zero-fill, then set diagonal entries = 1
            foreach (a_flat[i]) a_flat[i] = '0;
            foreach (b_flat[i]) b_flat[i] = '0;

            for (int r = 0; r < M && r < K; r++)
                a_flat[r*K + r] = 16'sh0001;
            for (int r = 0; r < K && r < N; r++)
                b_flat[r*N + r] = 16'sh0001;

            `uvm_info(get_type_name(),
                $sformatf("Identity test: M=%0d N=%0d K=%0d", M, N, K), UVM_LOW)
            run_gemm(a_flat, b_flat, M, N, K);
        endtask

    endclass : accel_identity_test

    // =========================================================================
    // accel_checkerboard_test  –  alternating ±127 patterns
    //
    // A[i][j] = B[i][j] = (i+j)%2 ? +127 : -127
    // The expected result is computed by the scoreboard's golden model.
    // =========================================================================
    class accel_checkerboard_test extends accel_base_test;
        `uvm_component_utils(accel_checkerboard_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        protected virtual task do_test(uvm_phase phase);
            logic signed [15:0] a_flat[];
            logic signed [15:0] b_flat[];

            a_flat = new[M * K];
            b_flat = new[K * N];

            for (int i = 0; i < M; i++)
                for (int j = 0; j < K; j++)
                    a_flat[i*K + j] = ((i+j) % 2) ? 16'sh007F : 16'shFF81;

            for (int i = 0; i < K; i++)
                for (int j = 0; j < N; j++)
                    b_flat[i*N + j] = ((i+j) % 2) ? 16'sh007F : 16'shFF81;

            `uvm_info(get_type_name(),
                $sformatf("Checkerboard test: M=%0d N=%0d K=%0d", M, N, K), UVM_LOW)
            run_gemm(a_flat, b_flat, M, N, K);
        endtask

    endclass : accel_checkerboard_test

    // =========================================================================
    // accel_random_test  –  constrained-random A and B, 4 deterministic seeds
    //
    // Runs 4 independent iterations, each seeded deterministically so the test
    // is reproducible.  Full signed 16-bit range is used for both matrices.
    // =========================================================================
    class accel_random_test extends accel_base_test;
        `uvm_component_utils(accel_random_test)

        int unsigned rand_iters = 4;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        protected virtual task do_test(uvm_phase phase);
            logic signed [15:0] a_flat[];
            logic signed [15:0] b_flat[];

            // Deterministic seeds (same as pyuvm random_test.py)
            int seeds[4] = '{32'h00001234, 32'h0000ACCE,
                              32'h0000BEEF, 32'h0000C0DE};

            a_flat = new[M * K];
            b_flat = new[K * N];

            for (int iter = 0; iter < rand_iters; iter++) begin
                // Seed the SV random number generator
                void'($urandom(seeds[iter % 4]));

                foreach (a_flat[i])
                    a_flat[i] = $signed($urandom_range(16'hFFFF, 16'h0000));
                foreach (b_flat[i])
                    b_flat[i] = $signed($urandom_range(16'hFFFF, 16'h0000));

                `uvm_info(get_type_name(),
                    $sformatf("Random iter %0d/%0d (seed=0x%08x)",
                              iter+1, rand_iters, seeds[iter % 4]),
                    UVM_LOW)
                run_gemm(a_flat, b_flat, M, N, K);
            end
        endtask

    endclass : accel_random_test

    // =========================================================================
    // accel_coverage_test  –  coverage-driven random test
    //
    // Randomizes M, N, K independently within [1 .. configured maximum] and
    // runs until accel_dim_cg reaches the coverage target or max_iters is hit.
    // This exercises all dimension size bins (small/medium/large).
    //
    // Note: requires the DUT to be compiled with M=N=K=16 (or larger) so that
    // runtime dimensions up to 16 are accepted.  If compiled with smaller
    // parameters, set max_dim accordingly.
    // =========================================================================
    class accel_coverage_test extends accel_base_test;
        `uvm_component_utils(accel_coverage_test)

        real         cov_target = 95.0;   // percent
        int unsigned max_iters  = 100;
        int unsigned max_dim    = 4;      // capped at DUT compile-time size

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        protected virtual task do_test(uvm_phase phase);
            logic signed [15:0] a_flat[];
            logic signed [15:0] b_flat[];
            int unsigned tm, tn, tk;
            real cur_cov;

            for (int iter = 0; iter < max_iters; iter++) begin
                // Randomize dimensions within safe range
                tm = $urandom_range(1, max_dim);
                tn = $urandom_range(1, max_dim);
                tk = $urandom_range(1, max_dim);

                a_flat = new[tm * tk];
                b_flat = new[tk * tn];

                foreach (a_flat[i])
                    a_flat[i] = $signed($urandom_range(16'hFFFF, 16'h0000));
                foreach (b_flat[i])
                    b_flat[i] = $signed($urandom_range(16'hFFFF, 16'h0000));

                run_gemm(a_flat, b_flat, tm, tn, tk);

                cur_cov = env.cov.accel_dim_cg.get_coverage();
                `uvm_info(get_type_name(),
                    $sformatf("Coverage iter %0d: dim_cg=%.1f%% (M=%0d N=%0d K=%0d)",
                              iter+1, cur_cov, tm, tn, tk),
                    UVM_MEDIUM)

                if (cur_cov >= cov_target) begin
                    `uvm_info(get_type_name(),
                        $sformatf("Coverage target %.1f%% reached after %0d iterations",
                                  cov_target, iter+1),
                        UVM_LOW)
                    return;
                end
            end

            `uvm_warning(get_type_name(),
                $sformatf("Coverage %.1f%% after %0d iterations (target %.1f%%)",
                          cur_cov, max_iters, cov_target))
        endtask

    endclass : accel_coverage_test

endpackage : accel_tests_pkg

`endif // ACCEL_TESTS_PKG_SV
