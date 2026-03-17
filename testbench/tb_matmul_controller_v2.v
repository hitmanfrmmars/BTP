// Testbench for matmul_controller_v2 (streaming, broadcast dataflow)
// Enhanced: cycle counting, zero matrix, max-value, back-to-back tests
// Integrates with scratchpad_mem and mac_array_v2
`timescale 1ns/1ps

module tb_matmul_controller_v2;
    parameter ARRAY_SIZE = 4;
    parameter ACC_WIDTH  = 48;

    reg clk, rst;
    reg start, mode, accumulate;
    reg [2:0] eff_rows, eff_k;
    reg [9:0] spad_row_stride;
    reg [9:0] a_base, b_base, c_base;
    wire done, busy;

    // Scratchpad wires
    wire [9:0]  spad_addr;
    wire        spad_re, spad_we;
    wire [31:0] spad_rdata, spad_wdata;

    // MAC wires
    wire [15:0] a_col [0:ARRAY_SIZE-1];
    wire [15:0] b_row [0:ARRAY_SIZE-1];
    wire        mac_enable, mac_clear_acc;
    wire [ACC_WIDTH-1:0] result_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire valid_out [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire overflow_flags [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    integer errors = 0;
    integer i, j;
    integer cycle_count;
    reg [31:0] readback;

    // Scratchpad
    scratchpad_mem #(.ADDR_WIDTH(10), .DATA_WIDTH(32), .DEPTH(256)) spad (
        .clk(clk), .rst(rst),
        .addr_a(10'd0), .wdata_a(32'd0), .we_a(1'b0), .re_a(1'b0), .rdata_a(),
        .addr_b(spad_addr), .wdata_b(spad_wdata), .we_b(spad_we), .re_b(spad_re), .rdata_b(spad_rdata)
    );

    // MAC Array v2
    mac_array_v2 #(.ARRAY_SIZE(ARRAY_SIZE), .ACC_WIDTH(ACC_WIDTH)) mac (
        .clk(clk), .rst(rst),
        .mode(mode), .enable(mac_enable), .clear_acc(mac_clear_acc),
        .a_col(a_col), .b_row(b_row),
        .result_matrix(result_matrix),
        .valid_out(valid_out), .overflow_flags(overflow_flags)
    );

    // DUT
    matmul_controller_v2 #(.ARRAY_SIZE(ARRAY_SIZE), .ACC_WIDTH(ACC_WIDTH)) dut (
        .clk(clk), .rst(rst),
        .start(start), .mode(mode), .accumulate(accumulate),
        .eff_rows(eff_rows), .eff_k(eff_k),
        .spad_row_stride(spad_row_stride),
        .a_base_addr(a_base), .b_base_addr(b_base), .c_base_addr(c_base),
        .done(done), .busy(busy),
        .spad_addr(spad_addr), .spad_re(spad_re), .spad_rdata(spad_rdata),
        .spad_we(spad_we), .spad_wdata(spad_wdata),
        .a_col(a_col), .b_row(b_row),
        .mac_enable(mac_enable), .mac_clear_acc(mac_clear_acc),
        .result_matrix(result_matrix)
    );

    always #5 clk = ~clk;

    // Helper: load a 4x4 matrix into scratchpad (row-major, 1 word per row)
    task load_matrix_4x4;
        input [9:0] base;
        input [7:0] m00, m01, m02, m03;
        input [7:0] m10, m11, m12, m13;
        input [7:0] m20, m21, m22, m23;
        input [7:0] m30, m31, m32, m33;
        begin
            spad.mem[(base >> 2) + 0] = {m03, m02, m01, m00};
            spad.mem[(base >> 2) + 1] = {m13, m12, m11, m10};
            spad.mem[(base >> 2) + 2] = {m23, m22, m21, m20};
            spad.mem[(base >> 2) + 3] = {m33, m32, m31, m30};
        end
    endtask

    task check_result_byte;
        input [9:0] addr;
        input [1:0] byte_sel;
        input [7:0] expected;
        input [199:0] msg;
        reg [31:0] word;
        reg [7:0] actual;
        begin
            word = spad.mem[addr >> 2];
            case (byte_sel)
                2'd0: actual = word[7:0];
                2'd1: actual = word[15:8];
                2'd2: actual = word[23:16];
                2'd3: actual = word[31:24];
            endcase
            if (actual !== expected) begin
                $display("FAIL: %0s - got %0d, expected %0d (word=%h)", msg, actual, expected, word);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d", msg, actual);
            end
        end
    endtask

    // Load 4x4 int16 matrix (2 words per row, row stride = 8 bytes)
    task load_matrix_4x4_int16;
        input [9:0] base;
        input [15:0] m00, m01, m02, m03;
        input [15:0] m10, m11, m12, m13;
        input [15:0] m20, m21, m22, m23;
        input [15:0] m30, m31, m32, m33;
        begin
            spad.mem[(base >> 2) + 0] = {m01, m00};
            spad.mem[(base >> 2) + 1] = {m03, m02};
            spad.mem[(base >> 2) + 2] = {m11, m10};
            spad.mem[(base >> 2) + 3] = {m13, m12};
            spad.mem[(base >> 2) + 4] = {m21, m20};
            spad.mem[(base >> 2) + 5] = {m23, m22};
            spad.mem[(base >> 2) + 6] = {m31, m30};
            spad.mem[(base >> 2) + 7] = {m33, m32};
        end
    endtask

    task check_result_halfword;
        input [9:0] addr;
        input        sel;    // 0=low halfword, 1=high halfword
        input [15:0] expected;
        input [199:0] msg;
        reg [31:0] word;
        reg [15:0] actual;
        begin
            word = spad.mem[addr >> 2];
            actual = sel ? word[31:16] : word[15:0];
            if (actual !== expected) begin
                $display("FAIL: %0s - got %0d, expected %0d (word=%h)", msg, actual, expected, word);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = %0d", msg, actual);
            end
        end
    endtask

    // Helper: start matmul and wait for done
    task run_matmul;
        begin
            start = 1;
            @(posedge clk); #1;
            start = 0;
            while (!done) begin
                @(posedge clk); #1;
            end
            @(posedge clk); #1;
        end
    endtask

    initial begin
        $dumpfile("tb_matmul_controller_v2.vcd");
        $dumpvars(0, tb_matmul_controller_v2);

        clk = 0; rst = 1; start = 0; mode = 0; accumulate = 0;
        eff_rows = 3'd4; eff_k = 3'd4;
        spad_row_stride = 10'd4;
        a_base = 10'h000; b_base = 10'h010; c_base = 10'h020;

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;
        @(posedge clk); #1;

        // ============================================================
        // Test 1: Identity * B = B
        // ============================================================
        $display("\n=== Test 1: Identity x B = B ===");
        load_matrix_4x4(10'h000,
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        );
        load_matrix_4x4(10'h010,
            1, 2,  3,  4,
            5, 6,  7,  8,
            9, 10, 11, 12,
            13, 14, 15, 16
        );

        run_matmul;

        check_result_byte(10'h020, 2'd0, 8'd1,  "C[0][0]");
        check_result_byte(10'h020, 2'd1, 8'd2,  "C[0][1]");
        check_result_byte(10'h020, 2'd2, 8'd3,  "C[0][2]");
        check_result_byte(10'h020, 2'd3, 8'd4,  "C[0][3]");
        check_result_byte(10'h024, 2'd0, 8'd5,  "C[1][0]");
        check_result_byte(10'h024, 2'd1, 8'd6,  "C[1][1]");
        check_result_byte(10'h028, 2'd0, 8'd9,  "C[2][0]");
        check_result_byte(10'h02C, 2'd3, 8'd16, "C[3][3]");

        // ============================================================
        // Test 2: 2x2 sub-matrix [[1,2],[3,4]] * [[5,6],[7,8]]
        // C = [[19,22],[43,50]]
        // ============================================================
        $display("\n=== Test 2: 2x2 multiply ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;

        load_matrix_4x4(10'h000,
            1, 2, 0, 0,
            3, 4, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0
        );
        load_matrix_4x4(10'h010,
            5, 6, 0, 0,
            7, 8, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0
        );

        run_matmul;

        check_result_byte(10'h020, 2'd0, 8'd19, "C[0][0]=19");
        check_result_byte(10'h020, 2'd1, 8'd22, "C[0][1]=22");
        check_result_byte(10'h024, 2'd0, 8'd43, "C[1][0]=43");
        check_result_byte(10'h024, 2'd1, 8'd50, "C[1][1]=50");

        // ============================================================
        // Test 3: Cycle count measurement
        // ============================================================
        $display("\n=== Test 3: Cycle count measurement ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;

        load_matrix_4x4(10'h000,
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        );
        load_matrix_4x4(10'h010,
            2, 3, 4, 5,
            6, 7, 8, 9,
            10, 11, 12, 13,
            14, 15, 16, 17
        );

        cycle_count = 0;
        start = 1;
        @(posedge clk); #1;
        start = 0;
        while (!done) begin
            @(posedge clk); #1;
            cycle_count = cycle_count + 1;
        end
        $display("  GEMM completed in %0d cycles", cycle_count);
        if (cycle_count > 50) begin
            $display("FAIL: Cycle count %0d exceeds expected ~25 cycles", cycle_count);
            errors = errors + 1;
        end else begin
            $display("PASS: Cycle count %0d is within acceptable range", cycle_count);
        end

        // ============================================================
        // Test 4: Zero matrix test (A=0 => C=0)
        // ============================================================
        $display("\n=== Test 4: Zero matrix A ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;

        load_matrix_4x4(10'h000,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0,
            0, 0, 0, 0
        );
        load_matrix_4x4(10'h010,
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12,
            13, 14, 15, 16
        );

        run_matmul;

        check_result_byte(10'h020, 2'd0, 8'd0, "Zero A: C[0][0]=0");
        check_result_byte(10'h020, 2'd1, 8'd0, "Zero A: C[0][1]=0");
        check_result_byte(10'h024, 2'd0, 8'd0, "Zero A: C[1][0]=0");
        check_result_byte(10'h02C, 2'd3, 8'd0, "Zero A: C[3][3]=0");

        // ============================================================
        // Test 5: Max-value accumulation (255*255*4 = 260100 = 0x3F804)
        // Low byte of result = 0x04
        // ============================================================
        $display("\n=== Test 5: Max-value accumulation ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;

        load_matrix_4x4(10'h000,
            255, 255, 255, 255,
            255, 255, 255, 255,
            255, 255, 255, 255,
            255, 255, 255, 255
        );
        load_matrix_4x4(10'h010,
            255, 255, 255, 255,
            255, 255, 255, 255,
            255, 255, 255, 255,
            255, 255, 255, 255
        );

        run_matmul;

        check_result_byte(10'h020, 2'd0, 8'h04, "Max val: C[0][0] low byte=0x04");
        check_result_byte(10'h024, 2'd1, 8'h04, "Max val: C[1][1] low byte=0x04");

        // ============================================================
        // Test 6: Back-to-back matmul without reset
        // ============================================================
        $display("\n=== Test 6: Back-to-back matmul without reset ===");
        // First: I * B = B
        load_matrix_4x4(10'h000,
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        );
        load_matrix_4x4(10'h010,
            10, 20, 30, 40,
            50, 60, 70, 80,
            90, 100, 110, 120,
            130, 140, 150, 160
        );

        run_matmul;

        check_result_byte(10'h020, 2'd0, 8'd10,  "B2B first: C[0][0]=10");
        check_result_byte(10'h024, 2'd1, 8'd60,  "B2B first: C[1][1]=60");

        // Second: 2I * B = 2B (no reset)
        load_matrix_4x4(10'h000,
            2, 0, 0, 0,
            0, 2, 0, 0,
            0, 0, 2, 0,
            0, 0, 0, 2
        );

        run_matmul;

        check_result_byte(10'h020, 2'd0, 8'd20,  "B2B second: C[0][0]=20");
        check_result_byte(10'h024, 2'd1, 8'd120, "B2B second: C[1][1]=120");

        // ============================================================
        // Test 7: Accumulate mode (simulate multi-K-tile)
        // First matmul: I * [1,2,3,4; 5,6,7,8; ...] = B (accum=0, clears)
        // Second matmul: I * [10,10,10,10; ...] with accum=1 -> should ADD
        // Result: C[0][0] = 1+10 = 11, C[1][1] = 6+10 = 16
        // ============================================================
        $display("\n=== Test 7: Accumulate mode (multi-K simulation) ===");

        accumulate = 0;
        load_matrix_4x4(10'h000,
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        );
        load_matrix_4x4(10'h010,
            1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12,
            13, 14, 15, 16
        );
        run_matmul;
        check_result_byte(10'h020, 2'd0, 8'd1, "Accum pass1: C[0][0]=1");
        check_result_byte(10'h024, 2'd1, 8'd6, "Accum pass1: C[1][1]=6");

        // Second pass with accumulate=1 (MAC should NOT be cleared)
        accumulate = 1;
        load_matrix_4x4(10'h000,
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        );
        load_matrix_4x4(10'h010,
            10, 10, 10, 10,
            10, 10, 10, 10,
            10, 10, 10, 10,
            10, 10, 10, 10
        );
        run_matmul;
        check_result_byte(10'h020, 2'd0, 8'd11, "Accum pass2: C[0][0]=1+10=11");
        check_result_byte(10'h020, 2'd1, 8'd12, "Accum pass2: C[0][1]=2+10=12");
        check_result_byte(10'h024, 2'd1, 8'd16, "Accum pass2: C[1][1]=6+10=16");
        check_result_byte(10'h02C, 2'd3, 8'd26, "Accum pass2: C[3][3]=16+10=26");

        accumulate = 0;

        // ============================================================
        // Test 8: int16 mode - Identity * B = B
        // ============================================================
        $display("\n=== Test 8: int16 mode - Identity x B = B ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;

        mode = 1;
        spad_row_stride = 10'd8;
        a_base = 10'h000;
        b_base = 10'h020;
        c_base = 10'h040;

        load_matrix_4x4_int16(10'h000,
            16'd1, 16'd2, 16'd3, 16'd4,
            16'd5, 16'd6, 16'd7, 16'd8,
            16'd9, 16'd10, 16'd11, 16'd12,
            16'd13, 16'd14, 16'd15, 16'd16
        );
        load_matrix_4x4_int16(10'h020,
            16'd1, 16'd0, 16'd0, 16'd0,
            16'd0, 16'd1, 16'd0, 16'd0,
            16'd0, 16'd0, 16'd1, 16'd0,
            16'd0, 16'd0, 16'd0, 16'd1
        );

        run_matmul;

        check_result_halfword(10'h040, 0, 16'd1,  "int16 C[0][0]=1");
        check_result_halfword(10'h040, 1, 16'd2,  "int16 C[0][1]=2");
        check_result_halfword(10'h044, 0, 16'd3,  "int16 C[0][2]=3");
        check_result_halfword(10'h044, 1, 16'd4,  "int16 C[0][3]=4");
        check_result_halfword(10'h048, 0, 16'd5,  "int16 C[1][0]=5");
        check_result_halfword(10'h048, 1, 16'd6,  "int16 C[1][1]=6");
        check_result_halfword(10'h04C, 0, 16'd7,  "int16 C[1][2]=7");
        check_result_halfword(10'h04C, 1, 16'd8,  "int16 C[1][3]=8");
        check_result_halfword(10'h050, 0, 16'd9,  "int16 C[2][0]=9");
        check_result_halfword(10'h058, 0, 16'd13, "int16 C[3][0]=13");
        check_result_halfword(10'h05C, 1, 16'd16, "int16 C[3][3]=16");

        // ============================================================
        // Test 9: int16 mode - Values exceeding uint8 range
        // A = all 1s, B rows = [100,200,300,400]
        // C[i][j] = 400, 800, 1200, 1600
        // ============================================================
        $display("\n=== Test 9: int16 values > 255 ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;

        mode = 1;
        spad_row_stride = 10'd8;
        a_base = 10'h000;
        b_base = 10'h020;
        c_base = 10'h040;

        load_matrix_4x4_int16(10'h000,
            16'd1, 16'd1, 16'd1, 16'd1,
            16'd1, 16'd1, 16'd1, 16'd1,
            16'd1, 16'd1, 16'd1, 16'd1,
            16'd1, 16'd1, 16'd1, 16'd1
        );
        load_matrix_4x4_int16(10'h020,
            16'd100, 16'd200, 16'd300, 16'd400,
            16'd100, 16'd200, 16'd300, 16'd400,
            16'd100, 16'd200, 16'd300, 16'd400,
            16'd100, 16'd200, 16'd300, 16'd400
        );

        run_matmul;

        check_result_halfword(10'h040, 0, 16'd400,  "int16 big: C[0][0]=400");
        check_result_halfword(10'h040, 1, 16'd800,  "int16 big: C[0][1]=800");
        check_result_halfword(10'h044, 0, 16'd1200, "int16 big: C[0][2]=1200");
        check_result_halfword(10'h044, 1, 16'd1600, "int16 big: C[0][3]=1600");
        check_result_halfword(10'h058, 0, 16'd400,  "int16 big: C[3][0]=400");
        check_result_halfword(10'h05C, 1, 16'd1600, "int16 big: C[3][3]=1600");

        // Restore int8 settings
        mode = 0;
        a_base = 10'h000;
        b_base = 10'h010;
        c_base = 10'h020;

        @(posedge clk); @(posedge clk);
        if (errors == 0) $display("\n*** ALL MATMUL_CONTROLLER_V2 TESTS PASSED ***\n");
        else $display("\n*** %0d TESTS FAILED ***\n", errors);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #200000;
        $display("TIMEOUT: Matmul test did not complete");
        $finish;
    end

endmodule
