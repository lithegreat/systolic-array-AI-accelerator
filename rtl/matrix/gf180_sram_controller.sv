module gf180_sram_controller #(
    parameter int unsigned NUM_MACROS = 2,
    parameter int unsigned ADDR_W = 9 + $clog2(NUM_MACROS)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic req_valid,
    output logic req_ready,
    input  logic req_write,
    input  logic [ADDR_W-1:0] req_addr,
    input  logic [7:0] req_wdata,
    input  logic [7:0] req_wmask,
    output logic rsp_valid,
    input  logic rsp_ready,
    output logic [7:0] rsp_rdata,
    output logic sram_clk,
    inout  wire VDD,
    inout  wire VSS
);
    localparam int unsigned SELECT_W = (NUM_MACROS > 1) ? $clog2(NUM_MACROS) : 1;
    typedef enum logic [2:0] {BOOT, IDLE, ISSUE, WAIT_DATA, RESPONSE} state_t;
    state_t state;
    logic [1:0] phase;
    logic write_q;
    logic [ADDR_W-1:0] address_q;
    logic [7:0] data_q, mask_q;
    logic [NUM_MACROS-1:0] cen;
    logic gwen;
    logic [8:0] address;
    logic [7:0] data, wen;
    wire [7:0] q [NUM_MACROS];
    logic [SELECT_W-1:0] selected;

    initial begin
        if (NUM_MACROS == 0 || (NUM_MACROS & (NUM_MACROS-1)) != 0 ||
            ADDR_W != 9 + $clog2(NUM_MACROS))
            $fatal(1, "GF180 controller requires a power-of-two macro count and exact address width");
    end

    // Reset never truncates a high memory-clock pulse.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            case (phase)
                2, 3: phase <= phase + 1'b1;
                default: phase <= '0;
            endcase
        end else begin
            phase <= phase + 1'b1;
        end
    end
    assign sram_clk = phase[1];
    assign req_ready = rst_n && state == IDLE;
    assign rsp_valid = rst_n && state == RESPONSE;

    always_ff @(posedge clk) begin
        if (phase == 0) begin
            cen <= '1;
            gwen <= 1'b1;
            wen <= '1;
            if (rst_n && state == ISSUE) begin
                for (int i = 0; i < NUM_MACROS; i++)
                    cen[i] <= (ADDR_W'(i) != (address_q >> 9));
                gwen <= !write_q;
                wen <= ~mask_q;
                address <= address_q[8:0];
                data <= data_q;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= BOOT;
            write_q <= 1'b0;
            address_q <= '0;
            data_q <= '0;
            mask_q <= '0;
            selected <= '0;
            rsp_rdata <= '0;
        end else begin
            case (state)
                BOOT: if (phase == 0) state <= IDLE;
                IDLE: if (req_valid) begin
                    write_q <= req_write;
                    address_q <= req_addr;
                    data_q <= req_wdata;
                    mask_q <= req_wmask;
                    state <= ISSUE;
                end
                ISSUE: if (phase == 0) begin
                    selected <= SELECT_W'(address_q >> 9);
                    state <= WAIT_DATA;
                end
                WAIT_DATA: if (phase == 0) begin
                    rsp_rdata <= write_q ? 8'b0 : q[selected];
                    state <= RESPONSE;
                end
                RESPONSE: if (rsp_ready) state <= IDLE;
                default: state <= BOOT;
            endcase
        end
    end

    for (genvar i = 0; i < NUM_MACROS; i++) begin : g_macro
        gf180mcu_fd_ip_sram__sram512x8m8wm1 u_sram (
            .CLK(sram_clk), .CEN(cen[i]), .GWEN(gwen), .WEN(wen),
            .A(address), .D(data), .Q(q[i]), .VDD(VDD), .VSS(VSS)
        );
    end
endmodule
