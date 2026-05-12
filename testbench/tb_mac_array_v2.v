// Testbench for mac_array_v2 (8x8 broadcast dataflow, output-stationary)
`timescale 1ns/1ps

module tb_mac_array_v2;
    parameter ARRAY_SIZE = 8;
    parameter ACC_WIDTH  = 48;

    reg clk, rst;
    reg mode, enable, clear_acc;
    reg [15:0] a_col [0:ARRAY_SIZE-1];
    reg [15:0] b_row [0:ARRAY_SIZE-1];
    wire [ACC_WIDTH-1:0] result_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire valid_out [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire overflow_flags [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    integer errors = 0;
    integer i, j, k;

    mac_array_v2 #(
        .ARRAY_SIZE(ARRAY_SIZE), .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .mode(mode), .enable(enable), .clear_acc(clear_acc),
        .a_col(a_col), .b_row(b_row),
        .result_matrix(result_matrix),
        .valid_out(valid_out), .overflow_flags(overflow_flags)
    );

    always #5 clk = ~clk;

    task check_element(input integer r, c, input [ACC_WIDTH-1:0] expected, input [199:0] msg);
        if (result_matrix[r][c] !== expected) begin
            $display("FAIL: C[%0d][%0d] %0s - got %0d, expected %0d", r, c, msg, result_matrix[r][c], expected);
            errors = errors + 1;
        end
    endtask

    initial begin
        $dumpfile("tb_mac_array_v2.vcd");
        $dumpvars(0, tb_mac_array_v2);

        clk = 0; rst = 1; mode = 0; enable = 0; clear_acc = 0;
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            a_col[i] = 16'd0;
            b_row[i] = 16'd0;
        end

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;

        // ============================================================
        // Test 1: Single-pass outer product
        // a_col = [1..8], b_row = [1,1,...,1]
        // C[i][j] = (i+1)
        // ============================================================
        $display("\n=== Test 1: Single-pass outer product ===");
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            a_col[i] = i[15:0] + 16'd1;
            b_row[i] = 16'd1;
        end
        enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        enable = 0; clear_acc = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;

        for (i = 0; i < ARRAY_SIZE; i = i + 1)
            for (j = 0; j < ARRAY_SIZE; j = j + 1)
                check_element(i, j, i + 1, "outer product");

        // ============================================================
        // Test 2: 8-pass Identity x B = B
        // B row k = [(k+1)*10, ...] for all columns
        // C[i][j] = (i+1)*10
        // ============================================================
        $display("\n=== Test 2: Identity x B = B (8-pass GEMM) ===");

        for (k = 0; k < ARRAY_SIZE; k = k + 1) begin
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                a_col[i] = (i == k) ? 16'd1 : 16'd0;
                b_row[i] = (k + 1) * 10;
            end
            enable = 1;
            clear_acc = (k == 0) ? 1'b1 : 1'b0;
            @(posedge clk); #1;
        end
        enable = 0; clear_acc = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;

        for (i = 0; i < ARRAY_SIZE; i = i + 1)
            for (j = 0; j < ARRAY_SIZE; j = j + 1)
                check_element(i, j, (i + 1) * 10, "I*B");

        // ============================================================
        // Test 3: All-ones 8-pass accumulation => C[i][j] = 8
        // ============================================================
        $display("\n=== Test 3: All-ones 8-pass accumulation ===");

        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            a_col[i] = 16'd1;
            b_row[i] = 16'd1;
        end
        enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        clear_acc = 0;
        for (k = 1; k < ARRAY_SIZE; k = k + 1)
            @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;

        for (i = 0; i < ARRAY_SIZE; i = i + 1)
            for (j = 0; j < ARRAY_SIZE; j = j + 1)
                check_element(i, j, ARRAY_SIZE, "all-ones");

        // ============================================================
        // Test 4: Back-to-back GEMM (no reset)
        // A = [[1,0,...],[2,0,...],...], B = [[1,1,...]], 1 pass => C[i][j] = i+1
        // Then a = [1,...,1], b = [3,...,3], 8 passes => C[i][j] = 24
        // ============================================================
        $display("\n=== Test 4: Back-to-back GEMM ===");

        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            a_col[i] = i[15:0] + 16'd1;
            b_row[i] = 16'd1;
        end
        enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        enable = 0; clear_acc = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;

        check_element(0, 0, 48'd1, "b2b-first");
        check_element(7, 7, 48'd8, "b2b-first");

        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            a_col[i] = 16'd1;
            b_row[i] = 16'd3;
        end
        enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        clear_acc = 0;
        for (k = 1; k < ARRAY_SIZE; k = k + 1)
            @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;

        for (i = 0; i < ARRAY_SIZE; i = i + 1)
            for (j = 0; j < ARRAY_SIZE; j = j + 1)
                check_element(i, j, 48'd24, "b2b-second 1*3*8=24");

        @(posedge clk); @(posedge clk);
        if (errors == 0) $display("\n*** ALL MAC_ARRAY_V2 TESTS PASSED ***\n");
        else $display("\n*** %0d TESTS FAILED ***\n", errors);
        $finish;
    end

endmodule
