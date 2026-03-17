// MAC Array (4x4)
// Performs parallel multiply-accumulate operations
// Can process 4x4 matrix operations in parallel
module mac_array #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire accumulate,
    
    // Input matrices (flattened)
    // a_matrix: 4x4 elements (16 total)
    input wire [DATA_WIDTH-1:0] a_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],
    input wire [DATA_WIDTH-1:0] b_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],
    
    // Output results (flattened)
    output wire [ACC_WIDTH-1:0] result_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],
    output wire [ARRAY_SIZE-1:0] overflow_flags [0:ARRAY_SIZE-1]
);

    // Generate 4x4 MAC units
    genvar i, j;
    generate
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : row
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin : col
                mac_unit mac_inst (
                    .clk(clk),
                    .rst(rst),
                    .enable(enable),
                    .accumulate(accumulate),
                    .a(a_matrix[i][j]),
                    .b(b_matrix[i][j]),
                    .result(result_matrix[i][j]),
                    .overflow(overflow_flags[i][j])
                );
            end
        end
    endgenerate

endmodule


