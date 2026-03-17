// Enhanced MAC Array v2 -- 4x4 Output-Stationary with Broadcast Dataflow
// A values broadcast across rows (a_col[i] feeds row i, all columns)
// B values broadcast across columns (b_row[j] feeds column j, all rows)
// C[i][j] += A[i][k] * B[k][j]  -- each MAC accumulates one output element
// Supports int8 and int16 modes via per-array mode select
module mac_array_v2 #(
    parameter ARRAY_SIZE = 4,
    parameter ACC_WIDTH  = 48
) (
    input wire clk,
    input wire rst,

    input wire        mode,          // 0 = int8, 1 = int16
    input wire        enable,        // pipeline enable
    input wire        clear_acc,     // clear all accumulators (new GEMM tile)

    // Broadcast inputs: one element per row (A) and one per column (B)
    input wire [15:0] a_col [0:ARRAY_SIZE-1],  // A[0..3][k] for current pass k
    input wire [15:0] b_row [0:ARRAY_SIZE-1],  // B[k][0..3] for current pass k

    // Results
    output wire [ACC_WIDTH-1:0] result_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],
    output wire                 valid_out      [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],
    output wire                 overflow_flags [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1]
);

    genvar i, j;
    generate
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : row
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin : col
                mac_unit_v2 #(
                    .ACC_WIDTH(ACC_WIDTH)
                ) mac_inst (
                    .clk(clk),
                    .rst(rst),
                    .mode(mode),
                    .enable(enable),
                    .clear_acc(clear_acc),
                    .a(a_col[i]),       // row i gets A[i][k]
                    .b(b_row[j]),       // col j gets B[k][j]
                    .result(result_matrix[i][j]),
                    .valid_out(valid_out[i][j]),
                    .overflow(overflow_flags[i][j])
                );
            end
        end
    endgenerate

endmodule
