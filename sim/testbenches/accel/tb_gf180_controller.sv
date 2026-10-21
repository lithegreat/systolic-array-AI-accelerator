`timescale 1ns/1ps
module tb_gf180_controller;
    logic clk = 0;
    always #10 clk = ~clk;
    logic rst_n = 0;
    logic req_valid = 0, req_ready, req_write = 0;
    logic [10:0] req_addr = 0;
    logic [7:0] req_wdata = 0, req_wmask = 0;
    logic rsp_valid, rsp_ready = 0;
    logic [7:0] rsp_rdata;
    wire sram_clk;
    supply1 VDD;
    supply0 VSS;
    time last_rise, last_fall;
    int operations = 0;

    gf180_sram_controller #(.NUM_MACROS(4)) dut (.*);

    always @(posedge sram_clk) begin
        if (last_rise != 0 && $time-last_rise < 80ns)
            $fatal(1, "Memory clock period is less than 80 ns");
        if (last_fall != 0 && $time-last_fall < 40ns)
            $fatal(1, "Memory low pulse was truncated");
        last_rise = $time;
    end
    always @(negedge sram_clk) begin
        if (last_rise != 0 && $time-last_rise < 40ns)
            $fatal(1, "Memory high pulse was truncated");
        last_fall = $time;
    end
    always @(posedge rsp_valid) begin
        if ($time-last_rise != 60ns)
            $fatal(1, "Response capture does not match the scoped three-cycle STA exception");
    end

    task automatic transaction(input bit wr, input int addr, input byte data,
                               input byte mask, input byte expected, input int stall = 0);
        int cycles;
        @(negedge clk);
        req_write = wr;
        req_addr = 11'(addr);
        req_wdata = data;
        req_wmask = mask;
        req_valid = 1;
        cycles = 0;
        do begin
            @(posedge clk);
            if (++cycles > 100) $fatal(1, "Request timeout");
        end while (!req_ready);
        @(negedge clk);
        req_valid = 0;
        cycles = 0;
        while (!rsp_valid) begin
            @(negedge clk);
            if (++cycles > 100) $fatal(1, "Response timeout");
        end
        repeat (stall) begin
            if (!rsp_valid || req_ready || (!wr && rsp_rdata !== expected))
                $fatal(1, "Response changed under backpressure");
            @(negedge clk);
        end
        if (!wr && rsp_rdata !== expected)
            $fatal(1, "Read %0d got %02x, expected %02x", addr, rsp_rdata, expected);
        rsp_ready = 1;
        @(negedge clk);
        rsp_ready = 0;
        operations++;
    endtask

    initial begin
        repeat (6) @(negedge clk);
        rst_n = 1;
        foreach_boundary: for (int bank = 0; bank < 4; bank++) begin
            transaction(1, bank*512, 8'(8'h30+bank), '1, 0);
            transaction(1, bank*512+511, 8'(8'ha0+bank), '1, 0);
            transaction(0, bank*512, 0, 0, 8'(8'h30+bank), bank);
            transaction(0, bank*512+511, 0, 0, 8'(8'ha0+bank), 2);
        end
        transaction(1, 19, 8'ha5, '1, 0);
        transaction(1, 19, 8'h3c, 8'h0f, 0);
        transaction(0, 19, 0, 0, 8'hac, 5);
        transaction(1, 19, 8'h00, 8'h00, 0);
        transaction(0, 19, 0, 0, 8'hac);
        for (int offset = 0; offset < 6; offset++) begin
            @(negedge clk);
            req_write = 0;
            req_addr = 19;
            req_valid = 1;
            do @(posedge clk); while (!req_ready);
            @(negedge clk);
            req_valid = 0;
            repeat (offset) @(negedge clk);
            rst_n = 0;
            repeat (6) @(negedge clk);
            if (rsp_valid || req_ready) $fatal(1, "Reset did not cancel protocol state");
            rst_n = 1;
            transaction(0, 19, 0, 0, 8'hac);
        end
        $display("GF180_CONTROLLER_PASS operations=%0d", operations);
        $finish;
    end
    initial begin
        #1ms;
        $fatal(1, "Controller test watchdog");
    end
endmodule
