// Double-Buffered Scratchpad Memory (Ping-Pong)
// Two SRAM banks; DMA fills one while compute reads the other.
// bank_sel toggles on swap_banks pulse to implement ping-pong.
// Each bank is 2KB (512 x 32-bit words) dual-port.
module scratchpad_double_buf #(
    parameter ADDR_WIDTH  = 10,
    parameter DATA_WIDTH  = 32,
    parameter BANK_DEPTH  = 256
) (
    input wire clk,
    input wire rst,

    // Bank control
    input wire swap_banks,          // Pulse to toggle active bank

    // Port A: DMA side (writes to fill bank, reads for store-back)
    input  wire [ADDR_WIDTH-1:0] dma_addr,
    input  wire [DATA_WIDTH-1:0] dma_wdata,
    input  wire                  dma_we,
    input  wire                  dma_re,
    output wire [DATA_WIDTH-1:0] dma_rdata,

    // Port B: Compute side (reads operands, writes results)
    input  wire [ADDR_WIDTH-1:0] comp_addr,
    input  wire [DATA_WIDTH-1:0] comp_wdata,
    input  wire                  comp_we,
    input  wire                  comp_re,
    output wire [DATA_WIDTH-1:0] comp_rdata
);

    reg bank_sel; // 0: DMA->Bank0, Compute->Bank1;  1: DMA->Bank1, Compute->Bank0

    always @(posedge clk) begin
        if (rst)
            bank_sel <= 1'b0;
        else if (swap_banks)
            bank_sel <= ~bank_sel;
    end

    // Bank 0 signals
    wire [ADDR_WIDTH-1:0] b0_addr_a, b0_addr_b;
    wire [DATA_WIDTH-1:0] b0_wdata_a, b0_wdata_b;
    wire                  b0_we_a, b0_we_b, b0_re_a, b0_re_b;
    wire [DATA_WIDTH-1:0] b0_rdata_a, b0_rdata_b;

    // Bank 1 signals
    wire [ADDR_WIDTH-1:0] b1_addr_a, b1_addr_b;
    wire [DATA_WIDTH-1:0] b1_wdata_a, b1_wdata_b;
    wire                  b1_we_a, b1_we_b, b1_re_a, b1_re_b;
    wire [DATA_WIDTH-1:0] b1_rdata_a, b1_rdata_b;

    // Mux: when bank_sel==0, DMA writes Bank0 (port A), Compute reads Bank1 (port B)
    //       when bank_sel==1, DMA writes Bank1 (port A), Compute reads Bank0 (port B)

    // Bank 0 port A (DMA when bank_sel==0, Compute when bank_sel==1)
    assign b0_addr_a  = bank_sel ? comp_addr  : dma_addr;
    assign b0_wdata_a = bank_sel ? comp_wdata : dma_wdata;
    assign b0_we_a    = bank_sel ? comp_we    : dma_we;
    assign b0_re_a    = bank_sel ? comp_re    : dma_re;

    // Bank 0 port B (unused — single-port-per-user is sufficient)
    assign b0_addr_b  = {ADDR_WIDTH{1'b0}};
    assign b0_wdata_b = {DATA_WIDTH{1'b0}};
    assign b0_we_b    = 1'b0;
    assign b0_re_b    = 1'b0;

    // Bank 1 port A (DMA when bank_sel==1, Compute when bank_sel==0)
    assign b1_addr_a  = bank_sel ? dma_addr   : comp_addr;
    assign b1_wdata_a = bank_sel ? dma_wdata  : comp_wdata;
    assign b1_we_a    = bank_sel ? dma_we     : comp_we;
    assign b1_re_a    = bank_sel ? dma_re     : comp_re;

    // Bank 1 port B (unused)
    assign b1_addr_b  = {ADDR_WIDTH{1'b0}};
    assign b1_wdata_b = {DATA_WIDTH{1'b0}};
    assign b1_we_b    = 1'b0;
    assign b1_re_b    = 1'b0;

    // Read data mux
    assign dma_rdata  = bank_sel ? b1_rdata_a : b0_rdata_a;
    assign comp_rdata = bank_sel ? b0_rdata_a : b1_rdata_a;

    // Bank 0
    scratchpad_mem #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(BANK_DEPTH)
    ) bank0 (
        .clk(clk), .rst(rst),
        .addr_a(b0_addr_a), .wdata_a(b0_wdata_a), .we_a(b0_we_a), .re_a(b0_re_a), .rdata_a(b0_rdata_a),
        .addr_b(b0_addr_b), .wdata_b(b0_wdata_b), .we_b(b0_we_b), .re_b(b0_re_b), .rdata_b(b0_rdata_b)
    );

    // Bank 1
    scratchpad_mem #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(BANK_DEPTH)
    ) bank1 (
        .clk(clk), .rst(rst),
        .addr_a(b1_addr_a), .wdata_a(b1_wdata_a), .we_a(b1_we_a), .re_a(b1_re_a), .rdata_a(b1_rdata_a),
        .addr_b(b1_addr_b), .wdata_b(b1_wdata_b), .we_b(b1_we_b), .re_b(b1_re_b), .rdata_b(b1_rdata_b)
    );

endmodule
