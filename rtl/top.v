// Top-level integration module
// Complete matrix multiplication accelerator with DMA, Scratchpad, Controller, and MAC Array
module top #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    
    // DMA Control signals
    input wire dma_start,
    input wire [ADDR_WIDTH-1:0] dma_src_addr,
    input wire [ADDR_WIDTH-1:0] dma_dst_addr,
    input wire [15:0] dma_transfer_size,
    output wire dma_done,
    output wire dma_busy,
    
    // Matrix multiplication control
    input wire matmul_start,           // Start matrix multiplication
    input wire [9:0] a_base_addr,      // Scratchpad address for A matrix
    input wire [9:0] b_base_addr,      // Scratchpad address for B matrix
    input wire [9:0] c_base_addr,      // Scratchpad address for C matrix (results)
    output wire matmul_done,           // Matrix multiplication complete
    output wire matmul_busy,           // Matrix multiplication in progress
    
    // Main memory interface
    output wire [ADDR_WIDTH-1:0] mem_addr,
    output wire mem_read,
    input wire [31:0] mem_rdata,
    input wire mem_ready,
    
    // Status outputs for debugging
    output wire [ACC_WIDTH-1:0] mac_result_0_0,
    output wire mac_overflow_0_0
);

    // Scratchpad memory signals
    // Port A: DMA controller
    wire [9:0] spad_addr_a;
    wire [31:0] spad_wdata_a;
    wire spad_we_a;
    wire spad_re_a;
    wire [31:0] spad_rdata_a;
    
    // Port B: Matrix multiplication controller
    wire [9:0] spad_addr_b;
    wire [31:0] spad_wdata_b;
    wire spad_we_b;
    wire spad_re_b;
    wire [31:0] spad_rdata_b;
    
    // MAC array signals
    wire [DATA_WIDTH-1:0] a_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire [DATA_WIDTH-1:0] b_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire [ACC_WIDTH-1:0] result_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire [ARRAY_SIZE-1:0] overflow_flags [0:ARRAY_SIZE-1];
    
    // Controller-MAC interface
    wire mac_enable;
    wire mac_accumulate;
    
    // ========================================
    // DMA Controller (Port A of Scratchpad)
    // ========================================
    dma_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(32)
    ) dma_inst (
        .clk(clk),
        .rst(rst),
        .start(dma_start),
        .src_addr(dma_src_addr),
        .dst_addr(dma_dst_addr),
        .transfer_size(dma_transfer_size),
        .done(dma_done),
        .busy(dma_busy),
        // Main memory interface
        .mem_addr(mem_addr),
        .mem_read(mem_read),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        // Scratchpad Port A
        .spad_addr(spad_addr_a),
        .spad_wdata(spad_wdata_a),
        .spad_we(spad_we_a),
        .spad_re(spad_re_a),
        .spad_rdata(spad_rdata_a)
    );
    
    // ========================================
    // Scratchpad Memory (Dual-Port)
    // ========================================
    scratchpad_mem #(
        .ADDR_WIDTH(10),
        .DATA_WIDTH(32)
    ) spad_inst (
        .clk(clk),
        .rst(rst),
        // Port A: DMA
        .addr_a(spad_addr_a),
        .wdata_a(spad_wdata_a),
        .we_a(spad_we_a),
        .re_a(spad_re_a),
        .rdata_a(spad_rdata_a),
        // Port B: Controller
        .addr_b(spad_addr_b),
        .wdata_b(spad_wdata_b),
        .we_b(spad_we_b),
        .re_b(spad_re_b),
        .rdata_b(spad_rdata_b)
    );
    
    // ========================================
    // Matrix Multiplication Controller (Port B of Scratchpad)
    // ========================================
    matmul_controller ctrl_inst (
        .clk(clk),
        .rst(rst),
        // Control interface
        .start(matmul_start),
        .a_base_addr(a_base_addr),
        .b_base_addr(b_base_addr),
        .c_base_addr(c_base_addr),
        .done(matmul_done),
        .busy(matmul_busy),
        // Scratchpad Port B
        .spad_addr(spad_addr_b),
        .spad_re(spad_re_b),
        .spad_rdata(spad_rdata_b),
        .spad_we(spad_we_b),
        .spad_wdata(spad_wdata_b),
        // MAC Array interface
        .a_matrix(a_matrix),
        .b_matrix(b_matrix),
        .mac_enable(mac_enable),
        .mac_accumulate(mac_accumulate),
        .result_matrix(result_matrix)
    );
    
    // ========================================
    // MAC Array
    // ========================================
    mac_array #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) mac_inst (
        .clk(clk),
        .rst(rst),
        .enable(mac_enable),
        .accumulate(mac_accumulate),
        .a_matrix(a_matrix),
        .b_matrix(b_matrix),
        .result_matrix(result_matrix),
        .overflow_flags(overflow_flags)
    );
    
    // ========================================
    // Debug outputs
    // ========================================
    assign mac_result_0_0 = result_matrix[0][0];
    assign mac_overflow_0_0 = overflow_flags[0][0];

endmodule
