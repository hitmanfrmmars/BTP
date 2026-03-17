// Testbench for mac_array_v2 (broadcast dataflow, output-stationary)
// Tests: single pass, multi-pass accumulation, full 4x4 GEMM, back-to-back
`timescale 1ns/1ps

module tb_mac_array_v2;
    parameter ARRAY_SIZE = 4;
    parameter ACC_WIDTH  = 48;

    reg clk, rst;
    reg mode, enable, clear_acc;
    reg [15:0] a_col [0:ARRAY_SIZE-1];
    reg [15:0] b_row [0:ARRAY_SIZE-1];
    wire [ACC_WIDTH-1:0] result_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire valid_out [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire overflow_flags [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    integer errors = 0;
    integer i, j;

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
        end else begin
            $display("PASS: C[%0d][%0d] %0s = %0d", r, c, msg, result_matrix[r][c]);
        end
    endtask

    initial begin
        $dumpfile("tb_mac_array_v2.vcd");
        $dumpvars(0, tb_mac_array_v2);

        clk = 0; rst = 1; mode = 0; enable = 0; clear_acc = 0;
        for (i = 0; i < 4; i = i + 1) begin
            a_col[i] = 16'd0;
            b_row[i] = 16'd0;
        end

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;

        // ============================================================
        // Test 1: Single-pass outer product
        // a_col = [1,2,3,4], b_row = [5,6,7,8]
        // C[i][j] = a_col[i] * b_row[j]
        // ============================================================
        $display("\n=== Test 1: Single-pass outer product ===");
        a_col[0] = 16'd1; a_col[1] = 16'd2; a_col[2] = 16'd3; a_col[3] = 16'd4;
        b_row[0] = 16'd5; b_row[1] = 16'd6; b_row[2] = 16'd7; b_row[3] = 16'd8;
        enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        enable = 0; clear_acc = 0;
        @(posedge clk); #1; // pipeline stage 1
        @(posedge clk); #1; // pipeline stage 2

        check_element(0, 0, 48'd5,  "1*5");
        check_element(0, 1, 48'd6,  "1*6");
        check_element(1, 0, 48'd10, "2*5");
        check_element(1, 1, 48'd12, "2*6");
        check_element(2, 2, 48'd21, "3*7");
        check_element(3, 3, 48'd32, "4*8");

        // ============================================================
        // Test 2: 4-pass GEMM -- identity matrix multiply
        // A = I, B = [[5,6,7,8],[9,10,11,12],[13,14,15,16],[17,18,19,20]]
        // C = I*B = B
        // ============================================================
        $display("\n=== Test 2: Identity x B = B (4-pass GEMM) ===");

        // Pass k=0: A col 0 = [1,0,0,0], B row 0 = [5,6,7,8]
        a_col[0] = 16'd1; a_col[1] = 16'd0; a_col[2] = 16'd0; a_col[3] = 16'd0;
        b_row[0] = 16'd5; b_row[1] = 16'd6; b_row[2] = 16'd7; b_row[3] = 16'd8;
        enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        clear_acc = 0;

        // Pass k=1
        a_col[0] = 16'd0; a_col[1] = 16'd1; a_col[2] = 16'd0; a_col[3] = 16'd0;
        b_row[0] = 16'd9; b_row[1] = 16'd10; b_row[2] = 16'd11; b_row[3] = 16'd12;
        @(posedge clk); #1;

        // Pass k=2
        a_col[0] = 16'd0; a_col[1] = 16'd0; a_col[2] = 16'd1; a_col[3] = 16'd0;
        b_row[0] = 16'd13; b_row[1] = 16'd14; b_row[2] = 16'd15; b_row[3] = 16'd16;
        @(posedge clk); #1;

        // Pass k=3
        a_col[0] = 16'd0; a_col[1] = 16'd0; a_col[2] = 16'd0; a_col[3] = 16'd1;
        b_row[0] = 16'd17; b_row[1] = 16'd18; b_row[2] = 16'd19; b_row[3] = 16'd20;
        @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;

        check_element(0, 0, 48'd5,  "I*B [0][0]");
        check_element(0, 1, 48'd6,  "I*B [0][1]");
        check_element(0, 2, 48'd7,  "I*B [0][2]");
        check_element(0, 3, 48'd8,  "I*B [0][3]");
        check_element(1, 0, 48'd9,  "I*B [1][0]");
        check_element(1, 1, 48'd10, "I*B [1][1]");
        check_element(2, 2, 48'd15, "I*B [2][2]");
        check_element(3, 3, 48'd20, "I*B [3][3]");

        // ============================================================
        // Test 3: General 2x2 sub-matrix
        // A = [[1,2],[3,4],..], B = [[5,6],[7,8],..]
        // C[0][0]=19, C[0][1]=22, C[1][0]=43, C[1][1]=50
        // ============================================================
        $display("\n=== Test 3: 2x2 [[1,2],[3,4]]*[[5,6],[7,8]] ===");

        // Pass k=0
        a_col[0] = 16'd1; a_col[1] = 16'd3; a_col[2] = 16'd0; a_col[3] = 16'd0;
        b_row[0] = 16'd5; b_row[1] = 16'd6; b_row[2] = 16'd0; b_row[3] = 16'd0;
        enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        clear_acc = 0;

        // Pass k=1
        a_col[0] = 16'd2; a_col[1] = 16'd4; a_col[2] = 16'd0; a_col[3] = 16'd0;
        b_row[0] = 16'd7; b_row[1] = 16'd8; b_row[2] = 16'd0; b_row[3] = 16'd0;
        @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;

        check_element(0, 0, 48'd19, "2x2 C[0][0]=19");
        check_element(0, 1, 48'd22, "2x2 C[0][1]=22");
        check_element(1, 0, 48'd43, "2x2 C[1][0]=43");
        check_element(1, 1, 48'd50, "2x2 C[1][1]=50");

        // ============================================================
        // Test 4: Full general 4x4 GEMM
        // A = [[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,16]]
        // B = [[17,18,19,20],[21,22,23,24],[25,26,27,28],[29,30,31,32]]
        // C[0] = [250, 260, 270, 280]
        // C[1] = [618, 644, 670, 696]
        // C[2] = [986, 1028, 1070, 1112]
        // C[3] = [1354, 1412, 1470, 1528]
        // ============================================================
        $display("\n=== Test 4: Full general 4x4 GEMM ===");

        // Pass k=0: A col 0 = [1,5,9,13], B row 0 = [17,18,19,20]
        a_col[0] = 16'd1;  a_col[1] = 16'd5;  a_col[2] = 16'd9;  a_col[3] = 16'd13;
        b_row[0] = 16'd17; b_row[1] = 16'd18; b_row[2] = 16'd19; b_row[3] = 16'd20;
        enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        clear_acc = 0;

        // Pass k=1
        a_col[0] = 16'd2;  a_col[1] = 16'd6;  a_col[2] = 16'd10; a_col[3] = 16'd14;
        b_row[0] = 16'd21; b_row[1] = 16'd22; b_row[2] = 16'd23; b_row[3] = 16'd24;
        @(posedge clk); #1;

        // Pass k=2
        a_col[0] = 16'd3;  a_col[1] = 16'd7;  a_col[2] = 16'd11; a_col[3] = 16'd15;
        b_row[0] = 16'd25; b_row[1] = 16'd26; b_row[2] = 16'd27; b_row[3] = 16'd28;
        @(posedge clk); #1;

        // Pass k=3
        a_col[0] = 16'd4;  a_col[1] = 16'd8;  a_col[2] = 16'd12; a_col[3] = 16'd16;
        b_row[0] = 16'd29; b_row[1] = 16'd30; b_row[2] = 16'd31; b_row[3] = 16'd32;
        @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;

        check_element(0, 0, 48'd250,  "4x4 C[0][0]=250");
        check_element(0, 1, 48'd260,  "4x4 C[0][1]=260");
        check_element(0, 2, 48'd270,  "4x4 C[0][2]=270");
        check_element(0, 3, 48'd280,  "4x4 C[0][3]=280");
        check_element(1, 0, 48'd618,  "4x4 C[1][0]=618");
        check_element(1, 1, 48'd644,  "4x4 C[1][1]=644");
        check_element(1, 2, 48'd670,  "4x4 C[1][2]=670");
        check_element(1, 3, 48'd696,  "4x4 C[1][3]=696");
        check_element(2, 0, 48'd986,  "4x4 C[2][0]=986");
        check_element(2, 1, 48'd1028, "4x4 C[2][1]=1028");
        check_element(2, 2, 48'd1070, "4x4 C[2][2]=1070");
        check_element(2, 3, 48'd1112, "4x4 C[2][3]=1112");
        check_element(3, 0, 48'd1354, "4x4 C[3][0]=1354");
        check_element(3, 1, 48'd1412, "4x4 C[3][1]=1412");
        check_element(3, 2, 48'd1470, "4x4 C[3][2]=1470");
        check_element(3, 3, 48'd1528, "4x4 C[3][3]=1528");

        // ============================================================
        // Test 5: Back-to-back GEMM (no reset)
        // A = all 1s, B = all 2s => C[i][j] = 1*2*4 = 8
        // ============================================================
        $display("\n=== Test 5: Back-to-back GEMM (no reset) ===");

        // Pass k=0
        for (i = 0; i < 4; i = i + 1) begin
            a_col[i] = 16'd1;
            b_row[i] = 16'd2;
        end
        enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        clear_acc = 0;
        // Passes k=1,2,3
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;

        check_element(0, 0, 48'd8, "b2b C[0][0]=8");
        check_element(1, 1, 48'd8, "b2b C[1][1]=8");
        check_element(2, 2, 48'd8, "b2b C[2][2]=8");
        check_element(3, 3, 48'd8, "b2b C[3][3]=8");
        check_element(0, 3, 48'd8, "b2b C[0][3]=8");
        check_element(3, 0, 48'd8, "b2b C[3][0]=8");

        @(posedge clk); @(posedge clk);
        if (errors == 0) $display("\n*** ALL MAC_ARRAY_V2 TESTS PASSED ***\n");
        else $display("\n*** %0d TESTS FAILED ***\n", errors);
        $finish;
    end

endmodule
