// Dual-Port Scratchpad SRAM
// 1KB (256 x 32-bit words), synchronous read/write, 1-cycle read latency
// Port A: DMA controller access
// Port B: Matmul controller access
module scratchpad_mem #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 256
) (
    input wire clk,
    input wire rst,

    // Port A (DMA side)
    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [DATA_WIDTH-1:0] wdata_a,
    input  wire                  we_a,
    input  wire                  re_a,
    output reg  [DATA_WIDTH-1:0] rdata_a,

    // Port B (Controller side)
    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [DATA_WIDTH-1:0] wdata_b,
    input  wire                  we_b,
    input  wire                  re_b,
    output reg  [DATA_WIDTH-1:0] rdata_b
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Word-aligned address: drop lower 2 bits to convert byte address to word index
    wire [$clog2(DEPTH)-1:0] word_addr_a = addr_a[ADDR_WIDTH-1:2];
    wire [$clog2(DEPTH)-1:0] word_addr_b = addr_b[ADDR_WIDTH-1:2];

    integer k;

    // Port A: synchronous read and write
    always @(posedge clk) begin
        if (rst) begin
            rdata_a <= {DATA_WIDTH{1'b0}};
        end else begin
            if (we_a)
                mem[word_addr_a] <= wdata_a;
            if (re_a)
                rdata_a <= mem[word_addr_a];
        end
    end

    // Port B: synchronous read and write
    always @(posedge clk) begin
        if (rst) begin
            rdata_b <= {DATA_WIDTH{1'b0}};
        end else begin
            if (we_b)
                mem[word_addr_b] <= wdata_b;
            if (re_b)
                rdata_b <= mem[word_addr_b];
        end
    end

endmodule
