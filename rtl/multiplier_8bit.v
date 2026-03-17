// 8-bit x 8-bit Multiplier
// Produces a 16-bit product
module multiplier_8bit (
    input wire clk,
    input wire rst,
    input wire [7:0] a,
    input wire [7:0] b,
    input wire valid_in,
    output reg [15:0] product,
    output reg valid_out
);

    // Combinational multiplication with registered output
    always @(posedge clk) begin
        if (rst) begin
            product <= 16'd0;
            valid_out <= 1'b0;
        end else begin
            product <= a * b;
            valid_out <= valid_in;
        end
    end

endmodule


