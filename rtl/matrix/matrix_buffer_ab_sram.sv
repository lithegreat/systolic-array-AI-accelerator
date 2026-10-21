`include "accel_pkg.sv"
module matrix_buffer_ab_sram
    import accel_pkg::*;
#(
    parameter int unsigned DATA_W = 8,
    parameter int unsigned M = 16, N = 16, K = 16,
    parameter int unsigned APB_AW = 10, APB_DW = 32
) (
    input logic clk, rst_n,
    input logic [APB_AW-1:0] PADDR,
    input logic PSEL, PENABLE, PWRITE,
    input logic [APB_DW-1:0] PWDATA,
    output logic [APB_DW-1:0] PRDATA,
    output logic PREADY, PSLVERR,
    input logic mat_start,
    output logic mat_valid,
    input logic sys_ready,
    input logic [APB_DW-1:0] cfg_m_dim, cfg_n_dim, cfg_k_dim,
    output logic [M*DATA_W-1:0] a_col,
    output logic [N*DATA_W-1:0] b_row,
    inout wire VDD, VSS
);
    typedef enum logic [1:0] {W_IDLE, W_REQ, W_WAIT, W_ACK} write_state_t;
    typedef enum logic [2:0] {S_IDLE, A_REQ, A_WAIT, B_REQ, B_WAIT, S_VALID} stream_state_t;
    write_state_t ws;
    stream_state_t ss;
    logic apb_bank, sys_bank, reuse_b [2];
    logic [8:0] a_ptr [2], b_ptr [2];
    logic [8:0] a_limit, b_limit, write_ptr, write_limit;
    logic access, sel_a, sel_b, sel_ctrl, overflow;
    logic write_bank, write_b;
    logic [8:0] write_base;
    logic [31:0] write_data;
    logic [2:0] write_count, write_byte;
    logic stream_bank;
    logic [4:0] stream_m, stream_n, stream_k, lane, k_index;
    logic mem_valid, mem_ready, mem_write, rsp_valid, owner_write;
    logic [9:0] mem_addr;
    logic [7:0] mem_data, rsp_data;
    wire sram_clk;

    initial begin
        if (DATA_W != 8 || APB_DW != 32 || APB_AW < 8 ||
            M < 1 || M > 16 || N < 1 || N > 16 || K < 1 || K > 16)
            $fatal(1, "GF180 A/B storage supports INT8, APB32 and dimensions 1..16");
    end

    assign access = PSEL && PENABLE;
    assign sel_a = PADDR[7:0] == MAT_A_DATA_OFF;
    assign sel_b = PADDR[7:0] == MAT_B_DATA_OFF;
    assign sel_ctrl = PADDR[7:0] == MAT_AB_CTRL_OFF;
    assign a_limit = 9'(cfg_m_dim[4:0] * cfg_k_dim[4:0]);
    assign b_limit = 9'(cfg_k_dim[4:0] * cfg_n_dim[4:0]);
    assign write_ptr = sel_b ? b_ptr[apb_bank] : a_ptr[apb_bank];
    assign write_limit = sel_b ? b_limit : a_limit;
    assign overflow = write_ptr >= write_limit;
    assign PREADY = !(access && PWRITE && (sel_a || sel_b)) ||
                    ws == W_ACK || (ws == W_IDLE && overflow);
    assign PSLVERR = access && PWRITE && (sel_a || sel_b) && ws == W_IDLE && overflow;
    assign mat_valid = ss == S_VALID;

    always_comb begin
        PRDATA = '0;
        if (access && !PWRITE && sel_ctrl) begin
            PRDATA[1] = a_ptr[apb_bank] >= a_limit;
            PRDATA[2] = b_ptr[apb_bank] >= b_limit;
            PRDATA[3] = apb_bank;
            PRDATA[4] = sys_bank;
            PRDATA[5] = reuse_b[apb_bank];
        end
        mem_valid = ws == W_REQ || ss == A_REQ || ss == B_REQ;
        mem_write = ws == W_REQ;
        mem_data = write_data[8*write_byte +: 8];
        if (mem_write)
            mem_addr = (10'(write_bank) << 9) + (write_b ? 10'd256 : 10'd0) +
                       10'(write_base) + 10'(write_byte);
        else if (ss == A_REQ)
            mem_addr = (10'(stream_bank) << 9) + 10'(lane * stream_k + k_index);
        else
            mem_addr = (10'(stream_bank) << 9) + 10'd256 + 10'(k_index * stream_n + lane);
    end

    gf180_sram_controller #(.NUM_MACROS(2)) u_storage (
        .clk(clk), .rst_n(rst_n), .req_valid(mem_valid), .req_ready(mem_ready),
        .req_write(mem_write), .req_addr(mem_addr), .req_wdata(mem_data), .req_wmask(8'hff),
        .rsp_valid(rsp_valid), .rsp_ready(1'b1), .rsp_rdata(rsp_data),
        .sram_clk(sram_clk), .VDD(VDD), .VSS(VSS)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ws <= W_IDLE;
            apb_bank <= 0;
            sys_bank <= 0;
            write_bank <= 0;
            write_b <= 0;
            write_base <= 0;
            write_data <= 0;
            write_count <= 0;
            write_byte <= 0;
            owner_write <= 0;
            for (int b = 0; b < 2; b++) begin
                a_ptr[b] <= 0;
                b_ptr[b] <= 0;
                reuse_b[b] <= 0;
            end
        end else begin
            if (mem_valid && mem_ready) owner_write <= mem_write;
            if (access && PWRITE && sel_ctrl) begin
                apb_bank <= PWDATA[3];
                sys_bank <= PWDATA[4];
                reuse_b[PWDATA[3]] <= PWDATA[5];
                if (PWDATA[0]) begin
                    a_ptr[apb_bank] <= 0;
                    if (!reuse_b[apb_bank]) b_ptr[apb_bank] <= 0;
                end
            end
            case (ws)
                W_IDLE: if (access && PWRITE && (sel_a || sel_b) && !overflow) begin
                    write_bank <= apb_bank;
                    write_b <= sel_b;
                    write_base <= write_ptr;
                    write_data <= PWDATA;
                    write_count <= (write_limit-write_ptr < 4) ? 3'(write_limit-write_ptr) : 3'd4;
                    write_byte <= 0;
                    ws <= W_REQ;
                end
                W_REQ: if (mem_ready) ws <= W_WAIT;
                W_WAIT: if (rsp_valid && owner_write) begin
                    if (write_byte + 1'b1 == write_count) ws <= W_ACK;
                    else begin
                        write_byte <= write_byte + 1'b1;
                        ws <= W_REQ;
                    end
                end
                W_ACK: if (access && PREADY) begin
                    if (write_b) b_ptr[write_bank] <= write_base + 9'(write_count);
                    else a_ptr[write_bank] <= write_base + 9'(write_count);
                    ws <= W_IDLE;
                end
                default: ws <= W_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ss <= S_IDLE;
            stream_bank <= 0;
            stream_m <= 0;
            stream_n <= 0;
            stream_k <= 0;
            lane <= 0;
            k_index <= 0;
            a_col <= '0;
            b_row <= '0;
        end else begin
            case (ss)
                S_IDLE: if (mat_start) begin
                    stream_bank <= sys_bank;
                    stream_m <= cfg_m_dim[4:0];
                    stream_n <= cfg_n_dim[4:0];
                    stream_k <= cfg_k_dim[4:0];
                    k_index <= 0;
                    lane <= 0;
                    a_col <= '0;
                    b_row <= '0;
                    ss <= A_REQ;
                end
                A_REQ: if (mem_valid && mem_ready && !mem_write) ss <= A_WAIT;
                A_WAIT: if (rsp_valid && !owner_write) begin
                    a_col[8*lane +: 8] <= rsp_data;
                    if (lane + 1'b1 == stream_m) begin
                        lane <= 0;
                        ss <= B_REQ;
                    end else begin
                        lane <= lane + 1'b1;
                        ss <= A_REQ;
                    end
                end
                B_REQ: if (mem_valid && mem_ready && !mem_write) ss <= B_WAIT;
                B_WAIT: if (rsp_valid && !owner_write) begin
                    b_row[8*lane +: 8] <= rsp_data;
                    if (lane + 1'b1 == stream_n) ss <= S_VALID;
                    else begin
                        lane <= lane + 1'b1;
                        ss <= B_REQ;
                    end
                end
                S_VALID: if (sys_ready) begin
                    if (k_index + 1'b1 == stream_k) ss <= S_IDLE;
                    else begin
                        k_index <= k_index + 1'b1;
                        lane <= 0;
                        a_col <= '0;
                        b_row <= '0;
                        ss <= A_REQ;
                    end
                end
                default: ss <= S_IDLE;
            endcase
        end
    end
endmodule
