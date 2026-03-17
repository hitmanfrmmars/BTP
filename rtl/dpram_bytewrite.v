// True Dual-Port Block RAM with Byte-Write Enables
// Vivado-compatible inference template (write-first mode)
//
// Port A: byte-write enables (for CPU)
// Port B: word-write (for DMA)
//
module dpram_bytewrite #(
    parameter ADDR_WIDTH = 15,
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 32768
) (
    input  wire                    clk,

    // Port A
    input  wire                    a_en,
    input  wire [DATA_WIDTH/8-1:0] a_we,
    input  wire [ADDR_WIDTH-1:0]   a_addr,
    input  wire [DATA_WIDTH-1:0]   a_din,
    output reg  [DATA_WIDTH-1:0]   a_dout,

    // Port B
    input  wire                    b_en,
    input  wire                    b_we,
    input  wire [ADDR_WIDTH-1:0]   b_addr,
    input  wire [DATA_WIDTH-1:0]   b_din,
    output reg  [DATA_WIDTH-1:0]   b_dout
);

    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Port A: byte-granularity writes
    always @(posedge clk) begin
        if (a_en) begin
            if (a_we[0]) mem[a_addr][ 7: 0] <= a_din[ 7: 0];
            if (a_we[1]) mem[a_addr][15: 8] <= a_din[15: 8];
            if (a_we[2]) mem[a_addr][23:16] <= a_din[23:16];
            if (a_we[3]) mem[a_addr][31:24] <= a_din[31:24];
            a_dout <= mem[a_addr];
        end
    end

    // Port B: word-granularity writes
    always @(posedge clk) begin
        if (b_en) begin
            if (b_we)
                mem[b_addr] <= b_din;
            b_dout <= mem[b_addr];
        end
    end

endmodule
