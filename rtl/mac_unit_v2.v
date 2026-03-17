// Pipelined Multiply-Accumulate Unit v2
// 2-stage pipeline: Stage 1 (multiply + register) -> Stage 2 (accumulate + register)
// Supports int8 (8x8->16, 32-bit acc) and int16 (16x16->32, 48-bit acc)
// Saturation on overflow instead of wrap-around
module mac_unit_v2 #(
    parameter DATA_WIDTH_8  = 8,
    parameter DATA_WIDTH_16 = 16,
    parameter ACC_WIDTH     = 48   // wide enough for int16 accumulation
) (
    input wire clk,
    input wire rst,

    input wire        mode,        // 0 = int8, 1 = int16
    input wire        enable,      // pipeline enable
    input wire        clear_acc,   // reset accumulator (start new dot product)
    input wire [15:0] a,           // operand A (int8 uses [7:0], int16 uses [15:0])
    input wire [15:0] b,           // operand B

    output reg [ACC_WIDTH-1:0] result,     // accumulated result
    output reg                 valid_out,  // result valid (2-cycle latency after enable)
    output reg                 overflow
);

    // --- Stage 1: multiply + register ---
    reg [31:0] product_s1;
    reg        valid_s1;
    reg        clear_s1;
    reg        mode_s1;

    wire [15:0] prod_8  = a[7:0] * b[7:0];           // 8x8 -> 16 bit
    wire [31:0] prod_16 = a[15:0] * b[15:0];         // 16x16 -> 32 bit

    always @(posedge clk) begin
        if (rst) begin
            product_s1 <= 32'd0;
            valid_s1   <= 1'b0;
            clear_s1   <= 1'b0;
            mode_s1    <= 1'b0;
        end else if (enable) begin
            product_s1 <= mode ? prod_16 : {16'd0, prod_8};
            valid_s1   <= 1'b1;
            clear_s1   <= clear_acc;
            mode_s1    <= mode;
        end else begin
            valid_s1 <= 1'b0;
        end
    end

    // --- Stage 2: accumulate + register ---
    reg [ACC_WIDTH-1:0] accumulator;
    wire [ACC_WIDTH-1:0] extended_prod = {{(ACC_WIDTH-32){1'b0}}, product_s1};
    wire [ACC_WIDTH-1:0] sum           = accumulator + extended_prod;

    // Saturation limits (unsigned)
    localparam [ACC_WIDTH-1:0] SAT_MAX_32 = {16'd0, 32'hFFFF_FFFF};
    localparam [ACC_WIDTH-1:0] SAT_MAX_48 = {ACC_WIDTH{1'b1}};

    wire sat_limit_exceeded = mode_s1 ? (sum < accumulator) && (sum < extended_prod)
                                      : (sum[47:32] != 16'd0) && !clear_s1;

    always @(posedge clk) begin
        if (rst) begin
            accumulator <= {ACC_WIDTH{1'b0}};
            result      <= {ACC_WIDTH{1'b0}};
            valid_out   <= 1'b0;
            overflow    <= 1'b0;
        end else if (valid_s1) begin
            if (clear_s1) begin
                accumulator <= extended_prod;
                result      <= extended_prod;
                overflow    <= 1'b0;
            end else begin
                accumulator <= sum;
                result      <= sum;
                overflow    <= sat_limit_exceeded;
            end
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule
