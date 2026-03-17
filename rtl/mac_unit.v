// Multiply-Accumulate (MAC) Unit
// Performs: result = a * b + acc
module mac_unit (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire accumulate,      // 1: accumulate, 0: just multiply
    input wire [7:0] a,
    input wire [7:0] b,
    output reg [31:0] result,
    output reg overflow
);

    reg [31:0] accumulator;
    wire [15:0] product;
    wire [31:0] extended_product;
    wire [31:0] next_result;

    // Multiply
    assign product = a * b;
    assign extended_product = {16'd0, product};
    
    // Add to accumulator if accumulate is enabled
    assign next_result = accumulate ? (accumulator + extended_product) : extended_product;

    always @(posedge clk) begin
        if (rst) begin
            accumulator <= 32'd0;
            result <= 32'd0;
            overflow <= 1'b0;
        end else if (enable) begin
            accumulator <= next_result;
            result <= next_result;
            
            // Simple overflow detection
            if (accumulate && (accumulator[31] == 0 && extended_product[31] == 0 && next_result[31] == 1))
                overflow <= 1'b1;
            else
                overflow <= 1'b0;
        end
    end

endmodule


