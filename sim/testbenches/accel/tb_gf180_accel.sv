`timescale 1ns/1ps
module tb_gf180_accel;
    logic clk = 0;
    always #10 clk = ~clk;
    logic reset_n = 0;
    logic [15:0] PADDR = 0;
    logic PSEL = 0, PENABLE = 0, PWRITE = 0;
    logic [31:0] PWDATA = 0;
    wire [31:0] PRDATA;
    wire PREADY, PSLVERR, irq;
    wire [15:0] pmod_gpio_oe, pmod_gpo;
    supply1 VDD;
    supply0 VSS;
    int transfers = 0, wait_cycles = 0, checked_elements = 0, tiles = 0;
    int output_stalls = 0;
    bit was_stalled = 0;
    logic [511:0] stalled_row;
    logic [3:0] stalled_index;

    subsystem_12 #(.USE_GF180_SRAM(1)) dut (
        .clk(clk), .reset_n(reset_n), .PADDR(PADDR), .PSEL(PSEL), .PENABLE(PENABLE),
        .PWRITE(PWRITE), .PWDATA(PWDATA), .PRDATA(PRDATA), .PREADY(PREADY),
        .PSLVERR(PSLVERR), .irq(irq), .irq_en(1'b1), .pmod_gpi(16'b0),
        .pmod_gpio_oe(pmod_gpio_oe), .pmod_gpo(pmod_gpo), .VDD(VDD), .VSS(VSS)
    );

    always @(posedge clk) begin
        if (reset_n) begin
            if (was_stalled &&
                (!dut.i_accelerator_top.out_valid ||
                 dut.i_accelerator_top.c_row_data !== stalled_row ||
                 dut.i_accelerator_top.c_row !== stalled_index))
                $fatal(1, "Array output changed under SRAM backpressure");
            was_stalled = dut.i_accelerator_top.out_valid && !dut.i_accelerator_top.out_ready;
            if (was_stalled) begin
                stalled_row = dut.i_accelerator_top.c_row_data;
                stalled_index = dut.i_accelerator_top.c_row;
                output_stalls++;
            end
            if (dut.i_accelerator_top.array_done && dut.i_accelerator_top.g_sram_c.storage_busy)
                $fatal(1, "Completion preceded SRAM commit");
        end else was_stalled = 0;
    end

    task automatic transfer(input bit wr, input int addr, input logic [31:0] data,
                            output logic [31:0] result, input bit expected_error = 0);
        int timeout;
        @(negedge clk);
        PSEL = 1;
        PENABLE = 0;
        PWRITE = wr;
        PADDR = 16'(addr);
        PWDATA = data;
        @(negedge clk);
        PENABLE = 1;
        timeout = 0;
        do begin
            @(posedge clk);
            if (++timeout > 20000) $fatal(1, "APB timeout at %03x", addr);
            if (!PREADY) wait_cycles++;
        end while (!PREADY);
        if (PSLVERR !== expected_error)
            $fatal(1, "APB %03x PSLVERR=%b expected %b", addr, PSLVERR, expected_error);
        result = PRDATA;
        transfers++;
        @(negedge clk);
        PSEL = 0;
        PENABLE = 0;
        PWRITE = 0;
    endtask

    task automatic wr(input int addr, input logic [31:0] data, input bit error = 0);
        logic [31:0] ignored;
        transfer(1, addr, data, ignored, error);
    endtask
    task automatic rd(input int addr, output logic [31:0] data, input bit error = 0);
        transfer(0, addr, 0, data, error);
    endtask

    function automatic int value_a(input int i, input int k, input int seed);
        if (seed == 100) return ((i+k) % 2) ? 127 : -128;
        return (i*3 + k*5 + seed) % 11 - 5;
    endfunction
    function automatic int value_b(input int k, input int j, input int seed);
        if (seed == 100) return ((k+j) % 2) ? 127 : -128;
        return (k*7 + j*2 + seed) % 9 - 4;
    endfunction

    task automatic configure(input int m, input int n, input int k);
        wr('h108, m);
        wr('h10c, n);
        wr('h118, k);
    endtask
    task automatic load_a(input int bank, input int m, input int k, input int seed,
                          input bit reuse_previous_b = 0);
        logic [31:0] packed_word;
        int index;
        wr('h080, (bank << 3) | (bank << 4) | (reuse_previous_b << 5));
        wr('h080, (bank << 3) | (bank << 4) | (reuse_previous_b << 5) | 1);
        for (int base = 0; base < m*k; base += 4) begin
            packed_word = '1;
            for (int b = 0; b < 4; b++) begin
                index = base + b;
                if (index < m*k) packed_word[8*b +: 8] = 8'(value_a(index/k, index%k, seed));
            end
            wr('h000, packed_word);
        end
        wr('h000, '1, 1);
    endtask
    task automatic load_b(input int k, input int n, input int seed);
        logic [31:0] packed_word;
        int index;
        for (int base = 0; base < k*n; base += 4) begin
            packed_word = '1;
            for (int b = 0; b < 4; b++) begin
                index = base + b;
                if (index < k*n) packed_word[8*b +: 8] = 8'(value_b(index/n, index%n, seed));
            end
            wr('h040, packed_word);
        end
        wr('h040, '1, 1);
    endtask
    task automatic reset_c(input int capture_bank, input int read_bank);
        wr('h280, (capture_bank << 3) | (capture_bank << 4));
        wr('h280, (capture_bank << 3) | (capture_bank << 4) | 1);
        wr('h280, (read_bank << 3) | (capture_bank << 4));
    endtask
    task automatic await_done;
        logic [31:0] status;
        int timeout;
        timeout = 0;
        do begin
            rd('h104, status);
            if (++timeout > 20000) $fatal(1, "Compute timeout");
        end while (!status[1] || status[0]);
        if (dut.i_accelerator_top.g_sram_c.storage_busy)
            $fatal(1, "STATUS.done before last SRAM row committed");
        tiles++;
    endtask
    task automatic start_tile;
        wr('h104, 2);
        wr('h100, 1);
    endtask
    task automatic check_c(input int m, input int n, input int k, input int aseed, input int bseed);
        logic [31:0] result;
        int expected;
        for (int i = 0; i < m; i++)
            for (int j = 0; j < n; j++) begin
                expected = 0;
                for (int t = 0; t < k; t++) expected += value_a(i,t,aseed)*value_b(t,j,bseed);
                rd('h200, result);
                if (result !== 32'(expected))
                    $fatal(1, "C[%0d,%0d]=%08x expected %08x", i, j, result, expected);
                checked_elements++;
            end
        rd('h200, result, 1);
        if (result !== 0) $fatal(1, "Overread did not return zero");
    endtask

    initial begin
        logic [31:0] result;
        repeat (8) @(negedge clk);
        reset_n = 1;
        configure(3, 5, 7);
        load_a(0, 3, 7, 1);
        load_b(7, 5, 2);
        reset_c(0, 0);
        start_tile();

        // Preload the other software bank while the first bank streams.
        load_a(1, 3, 7, 3);
        load_b(7, 5, 2);
        await_done();
        reset_c(1, 0);
        start_tile();
        check_c(3, 5, 7, 1, 2);
        await_done();
        wr('h280, 24);
        check_c(3, 5, 7, 3, 2);

        load_a(1, 3, 7, 4, 1);
        reset_c(1, 1);
        start_tile();
        await_done();
        check_c(3, 5, 7, 4, 2);

        for (int bank = 0; bank < 2; bank++) begin
            configure(16, 16, 16);
            load_a(bank, 16, 16, bank ? 100 : 5);
            load_b(16, 16, bank ? 100 : 7);
            reset_c(bank, bank);
            start_tile();
            await_done();
            check_c(16, 16, 16, bank ? 100 : 5, bank ? 100 : 7);
        end
        // Abort a stalled APB write with reset; no memory clearing is assumed.
        wr('h080, 25);
        @(negedge clk);
        PSEL = 1;
        PENABLE = 0;
        PWRITE = 1;
        PADDR = 0;
        PWDATA = 32'h12345678;
        @(negedge clk);
        PENABLE = 1;
        repeat (3) @(negedge clk);
        if (PREADY) $fatal(1, "Reset-abort test did not reach a stalled write");
        reset_n = 0;
        PSEL = 0;
        PENABLE = 0;
        PWRITE = 0;
        repeat (8) @(negedge clk);
        reset_n = 1;
        rd('h080, result);
        if (result !== 0) $fatal(1, "A/B metadata did not reset");
        rd('h280, result);
        if (result !== 0) $fatal(1, "C metadata did not reset");
        configure(1, 1, 1);
        load_a(0, 1, 1, 9);
        load_b(1, 1, 8);
        reset_c(0, 0);
        start_tile();
        await_done();
        check_c(1, 1, 1, 9, 8);
        rd('h134, result);
        if (result == 0 || wait_cycles == 0 || output_stalls == 0)
            $fatal(1, "SRAM wait/backpressure paths were not exercised");
        wr('h300, 0, 1);
        $display("GF180_ACCEL_PASS tiles=%0d elements=%0d transfers=%0d wait_cycles=%0d output_stalls=%0d",
                 tiles, checked_elements, transfers, wait_cycles, output_stalls);
        $finish;
    end
    initial begin
        #10ms;
        $fatal(1, "Accelerator SRAM regression watchdog");
    end
endmodule
