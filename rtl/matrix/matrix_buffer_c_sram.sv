`include "accel_pkg.sv"
module matrix_buffer_c_sram
    import accel_pkg::*;
#(
    parameter int unsigned ACC_W = 32,
    parameter int unsigned M = 16, N = 16,
    parameter int unsigned APB_AW = 10, APB_DW = 32
) (
    input logic clk, rst_n,
    input logic [APB_AW-1:0] PADDR,
    input logic PSEL, PENABLE, PWRITE,
    input logic [APB_DW-1:0] PWDATA,
    output logic [APB_DW-1:0] PRDATA,
    output logic PREADY, PSLVERR,
    input logic c_in_valid,
    output logic c_in_ready, busy,
    input logic [N*ACC_W-1:0] c_row_data_in,
    input logic [$clog2((M>1)?M:2)-1:0] c_row_in,
    input logic [APB_DW-1:0] cfg_m_dim, cfg_n_dim,
    inout wire VDD, VSS
);
    typedef enum logic [1:0] {R_IDLE, R_REQ, R_WAIT, R_ACK} read_state_t;
    typedef enum logic [1:0] {C_IDLE, C_REQ, C_WAIT} capture_state_t;
    read_state_t rs;
    capture_state_t cs;
    logic apb_bank, sys_bank;
    logic [8:0] read_ptr [2], read_base, limit;
    logic [4:0] rows_captured [2], capture_row, capture_n, capture_col;
    logic read_bank, capture_bank;
    logic [1:0] read_byte, capture_byte;
    logic [31:0] read_data;
    logic [N*ACC_W-1:0] row_data;
    logic access, sel_data, sel_ctrl, overread, row_available;
    logic mem_valid, mem_ready, mem_write, rsp_valid, owner_read;
    logic [10:0] mem_addr;
    logic [7:0] mem_data, rsp_data;
    wire sram_clk;

    initial begin
        if (ACC_W != 32 || APB_DW != 32 || APB_AW < 8 ||
            M < 1 || M > 16 || N < 1 || N > 16)
            $fatal(1, "GF180 C storage supports ACC32, APB32 and dimensions 1..16");
    end
    assign access = PSEL && PENABLE;
    assign sel_data = PADDR[7:0] == MAT_C_DATA_OFF;
    assign sel_ctrl = PADDR[7:0] == MAT_C_CTRL_OFF;
    assign limit = 9'(cfg_m_dim[4:0] * cfg_n_dim[4:0]);
    assign overread = read_ptr[apb_bank] >= limit;
    assign row_available = read_ptr[apb_bank] <
                           9'(rows_captured[apb_bank] * cfg_n_dim[4:0]);
    assign busy = cs != C_IDLE;
    assign c_in_ready = !busy && rows_captured[sys_bank] < cfg_m_dim[4:0] &&
                        !(access && PWRITE && sel_ctrl);
    assign PSLVERR = access && !PWRITE && sel_data && rs == R_IDLE && overread;
    always_comb begin
        PREADY = 1;
        if (access && !PWRITE && sel_data)
            PREADY = rs == R_ACK || (rs == R_IDLE && overread);
        if (access && PWRITE && sel_ctrl) PREADY = !busy && rs == R_IDLE;
        PRDATA = '0;
        if (access && !PWRITE && sel_data && rs == R_ACK) PRDATA = read_data;
        if (access && !PWRITE && sel_ctrl) begin
            PRDATA[1] = rows_captured[sys_bank] >= cfg_m_dim[4:0];
            PRDATA[3] = apb_bank;
            PRDATA[4] = sys_bank;
        end
        mem_valid = rs == R_REQ || cs == C_REQ;
        mem_write = rs != R_REQ;
        if (rs == R_REQ)
            mem_addr = (11'(read_bank) << 10) + (11'(read_base) << 2) + 11'(read_byte);
        else
            mem_addr = (11'(capture_bank) << 10) +
                       (11'(capture_row * capture_n + capture_col) << 2) + 11'(capture_byte);
        mem_data = row_data[32*capture_col + 8*capture_byte +: 8];
    end

    gf180_sram_controller #(.NUM_MACROS(4)) u_storage (
        .clk(clk), .rst_n(rst_n), .req_valid(mem_valid), .req_ready(mem_ready),
        .req_write(mem_write), .req_addr(mem_addr), .req_wdata(mem_data), .req_wmask(8'hff),
        .rsp_valid(rsp_valid), .rsp_ready(1'b1), .rsp_rdata(rsp_data),
        .sram_clk(sram_clk), .VDD(VDD), .VSS(VSS)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rs <= R_IDLE;
            cs <= C_IDLE;
            apb_bank <= 0;
            sys_bank <= 0;
            read_bank <= 0;
            capture_bank <= 0;
            read_base <= 0;
            read_byte <= 0;
            read_data <= 0;
            capture_row <= 0;
            capture_n <= 0;
            capture_col <= 0;
            capture_byte <= 0;
            row_data <= '0;
            owner_read <= 0;
            for (int b = 0; b < 2; b++) begin
                read_ptr[b] <= 0;
                rows_captured[b] <= 0;
            end
        end else begin
            if (mem_valid && mem_ready) owner_read <= !mem_write;
            if (access && PWRITE && sel_ctrl && PREADY) begin
                apb_bank <= PWDATA[3];
                sys_bank <= PWDATA[4];
                if (PWDATA[0]) begin
                    read_ptr[apb_bank] <= 0;
                    rows_captured[apb_bank] <= 0;
                end
            end
            case (rs)
                R_IDLE: if (access && !PWRITE && sel_data && !overread && row_available) begin
                    read_bank <= apb_bank;
                    read_base <= read_ptr[apb_bank];
                    read_byte <= 0;
                    read_data <= 0;
                    rs <= R_REQ;
                end
                R_REQ: if (mem_valid && mem_ready) rs <= R_WAIT;
                R_WAIT: if (rsp_valid && owner_read) begin
                    read_data[8*read_byte +: 8] <= rsp_data;
                    if (read_byte == 3) rs <= R_ACK;
                    else begin
                        read_byte <= read_byte + 1'b1;
                        rs <= R_REQ;
                    end
                end
                R_ACK: if (access && PREADY) begin
                    read_ptr[read_bank] <= read_base + 1'b1;
                    rs <= R_IDLE;
                end
                default: rs <= R_IDLE;
            endcase
            case (cs)
                C_IDLE: if (c_in_valid && c_in_ready) begin
                    row_data <= c_row_data_in;
                    capture_bank <= sys_bank;
                    capture_row <= 5'(c_row_in);
                    capture_n <= cfg_n_dim[4:0];
                    capture_col <= 0;
                    capture_byte <= 0;
                    cs <= C_REQ;
                end
                C_REQ: if (mem_valid && mem_ready && mem_write) cs <= C_WAIT;
                C_WAIT: if (rsp_valid && !owner_read) begin
                    if (capture_byte == 3) begin
                        capture_byte <= 0;
                        if (capture_col + 1'b1 == capture_n) begin
                            rows_captured[capture_bank] <= rows_captured[capture_bank] + 1'b1;
                            cs <= C_IDLE;
                        end else begin
                            capture_col <= capture_col + 1'b1;
                            cs <= C_REQ;
                        end
                    end else begin
                        capture_byte <= capture_byte + 1'b1;
                        cs <= C_REQ;
                    end
                end
                default: cs <= C_IDLE;
            endcase
        end
    end
endmodule
