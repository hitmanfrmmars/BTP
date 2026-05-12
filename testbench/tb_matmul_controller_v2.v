// Testbench for matmul_controller_v2 (8x8 streaming, broadcast dataflow)
// Integrates with scratchpad_mem and mac_array_v2
`timescale 1ns/1ps

module tb_matmul_controller_v2;
    parameter ARRAY_SIZE = 8;
    parameter ACC_WIDTH  = 48;

    reg clk, rst;
    reg start, mode, accumulate;
    reg [3:0] eff_rows, eff_k;
    reg [9:0] spad_row_stride;
    reg [9:0] a_base, b_base, c_base;
    wire done, busy;

    wire [9:0]  spad_addr;
    wire        spad_re, spad_we;
    wire [31:0] spad_rdata, spad_wdata;

    wire [15:0] a_col [0:ARRAY_SIZE-1];
    wire [15:0] b_row [0:ARRAY_SIZE-1];
    wire        mac_enable, mac_clear_acc;
    wire [ACC_WIDTH-1:0] result_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire valid_out [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire overflow_flags [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    integer errors = 0;
    integer i, j;
    integer cycle_count;

    scratchpad_mem #(.ADDR_WIDTH(10), .DATA_WIDTH(32), .DEPTH(512)) spad (
        .clk(clk), .rst(rst),
        .addr_a(10'd0), .wdata_a(32'd0), .we_a(1'b0), .re_a(1'b0), .rdata_a(),
        .addr_b(spad_addr), .wdata_b(spad_wdata), .we_b(spad_we), .re_b(spad_re), .rdata_b(spad_rdata)
    );

    mac_array_v2 #(.ARRAY_SIZE(ARRAY_SIZE), .ACC_WIDTH(ACC_WIDTH)) mac (
        .clk(clk), .rst(rst),
        .mode(mode), .enable(mac_enable), .clear_acc(mac_clear_acc),
        .a_col(a_col), .b_row(b_row),
        .result_matrix(result_matrix),
        .valid_out(valid_out), .overflow_flags(overflow_flags)
    );

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

    task check_spad_word(input [9:0] byte_addr, input [31:0] expected, input [199:0] msg);
        reg [31:0] actual;
        begin
            actual = spad.mem[byte_addr >> 2];
            if (actual !== expected) begin
                $display("FAIL: %0s @ 0x%03h - got %h, expected %h", msg, byte_addr, actual, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s @ 0x%03h = %h", msg, byte_addr, actual);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_matmul_controller_v2.vcd");
        $dumpvars(0, tb_matmul_controller_v2);

        clk = 0; rst = 1; start = 0; mode = 0; accumulate = 0;
        eff_rows = 4'd0; eff_k = 4'd0;
        spad_row_stride = 10'd8;
        a_base = 10'h000; b_base = 10'h040; c_base = 10'h080;

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;
        @(posedge clk); #1;

        // ============================================================
        // Test 1: Identity * B = B (int8, 8x8)
        // A = I_8, B[k][j] = k+1 for all j
        // C = I*B so C[i][j] = i+1
        // ============================================================
        $display("\n=== Test 1: Identity x B = B (8x8 int8) ===");

        // Load 8x8 identity into A region (base 0x000, stride 8 bytes)
        // Row i: byte i is 1, rest are 0. 2 words per row.
        for (i = 0; i < 8; i = i + 1) begin
            spad.mem[i * 2]     = (i < 4) ? (32'd1 << (i * 8))     : 32'd0;
            spad.mem[i * 2 + 1] = (i >= 4) ? (32'd1 << ((i-4)*8)) : 32'd0;
        end

        // Load B at base 0x040 (word 16). B[k] = [k+1, k+1, ...] for all 8 cols
        for (i = 0; i < 8; i = i + 1) begin
            spad.mem[16 + i * 2]     = {4{i[7:0] + 8'd1}};
            spad.mem[16 + i * 2 + 1] = {4{i[7:0] + 8'd1}};
        end

        run_matmul;

        // Verify C at base 0x080 (word 32). C[r] = [r+1, r+1, ...]
        for (i = 0; i < 8; i = i + 1) begin
            check_spad_word(10'h080 + i * 8,     {4{i[7:0] + 8'd1}}, "C row word0");
            check_spad_word(10'h080 + i * 8 + 4, {4{i[7:0] + 8'd1}}, "C row word1");
        end

        // ============================================================
        // Test 2: All-ones * all-ones = 8 (int8, 8x8)
        // ============================================================
        $display("\n=== Test 2: All-ones 8x8 int8 ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;

        for (i = 0; i < 8; i = i + 1) begin
            spad.mem[i * 2]     = 32'h01010101;
            spad.mem[i * 2 + 1] = 32'h01010101;
        end
        for (i = 0; i < 8; i = i + 1) begin
            spad.mem[16 + i * 2]     = 32'h01010101;
            spad.mem[16 + i * 2 + 1] = 32'h01010101;
        end

        run_matmul;

        for (i = 0; i < 8; i = i + 1) begin
            check_spad_word(10'h080 + i * 8,     32'h08080808, "allones row word0");
            check_spad_word(10'h080 + i * 8 + 4, 32'h08080808, "allones row word1");
        end

        // ============================================================
        // Test 3: Zero matrix A => C = 0
        // ============================================================
        $display("\n=== Test 3: Zero matrix A ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;

        for (i = 0; i < 16; i = i + 1) spad.mem[i] = 32'd0;
        for (i = 0; i < 8; i = i + 1) begin
            spad.mem[16 + i * 2]     = 32'hFFFFFFFF;
            spad.mem[16 + i * 2 + 1] = 32'hFFFFFFFF;
        end

        run_matmul;

        for (i = 0; i < 8; i = i + 1) begin
            check_spad_word(10'h080 + i * 8,     32'h00000000, "zero A row word0");
            check_spad_word(10'h080 + i * 8 + 4, 32'h00000000, "zero A row word1");
        end

        // ============================================================
        // Test 4: Cycle count measurement
        // ============================================================
        $display("\n=== Test 4: Cycle count ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;

        for (i = 0; i < 8; i = i + 1) begin
            spad.mem[i * 2]     = (i < 4) ? (32'd1 << (i * 8))     : 32'd0;
            spad.mem[i * 2 + 1] = (i >= 4) ? (32'd1 << ((i-4)*8)) : 32'd0;
        end
        for (i = 0; i < 8; i = i + 1) begin
            spad.mem[16 + i * 2]     = 32'h01010101;
            spad.mem[16 + i * 2 + 1] = 32'h01010101;
        end

        cycle_count = 0;
        start = 1;
        @(posedge clk); #1;
        start = 0;
        while (!done) begin
            @(posedge clk); #1;
            cycle_count = cycle_count + 1;
        end
        $display("  GEMM 8x8 completed in %0d cycles", cycle_count);
        if (cycle_count > 150) begin
            $display("FAIL: Cycle count %0d exceeds 150", cycle_count);
            errors = errors + 1;
        end else begin
            $display("PASS: Cycle count %0d within range", cycle_count);
        end

        // ============================================================
        // Test 5: int16 mode - Identity * B = B
        // ============================================================
        $display("\n=== Test 5: int16 Identity x B = B ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;

        mode = 1;
        spad_row_stride = 10'd16;
        a_base = 10'h000;
        b_base = 10'h080;
        c_base = 10'h100;

        // Identity 8x8 int16: 4 words per row. Row i has halfword i = 1.
        for (i = 0; i < 8; i = i + 1) begin
            spad.mem[i * 4 + 0] = 32'd0;
            spad.mem[i * 4 + 1] = 32'd0;
            spad.mem[i * 4 + 2] = 32'd0;
            spad.mem[i * 4 + 3] = 32'd0;
            // Element i of row i = 1. Word = i/2, halfword sel = i%2.
            spad.mem[i * 4 + (i / 2)] = (i % 2 == 0) ? 32'h00000001 : 32'h00010000;
        end

        // B at word 32 (byte 0x080). B[k][j] = 10*(k+1) for all j.
        for (i = 0; i < 8; i = i + 1) begin
            spad.mem[32 + i * 4 + 0] = {(i[15:0]+16'd1)*16'd10, (i[15:0]+16'd1)*16'd10};
            spad.mem[32 + i * 4 + 1] = {(i[15:0]+16'd1)*16'd10, (i[15:0]+16'd1)*16'd10};
            spad.mem[32 + i * 4 + 2] = {(i[15:0]+16'd1)*16'd10, (i[15:0]+16'd1)*16'd10};
            spad.mem[32 + i * 4 + 3] = {(i[15:0]+16'd1)*16'd10, (i[15:0]+16'd1)*16'd10};
        end

        run_matmul;

        // C at word 64 (byte 0x100). C[r][j] = 10*(r+1).
        for (i = 0; i < 8; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                check_spad_word(10'h100 + i * 16 + j * 4,
                    {(i[15:0]+16'd1)*16'd10, (i[15:0]+16'd1)*16'd10},
                    "int16 C row");
            end
        end

        // Restore int8 settings
        mode = 0;
        spad_row_stride = 10'd8;
        a_base = 10'h000; b_base = 10'h040; c_base = 10'h080;

        @(posedge clk); @(posedge clk);
        if (errors == 0) $display("\n*** ALL MATMUL_CONTROLLER_V2 TESTS PASSED ***\n");
        else $display("\n*** %0d TESTS FAILED ***\n", errors);
        $finish;
    end

    initial begin
        #500000;
        $display("TIMEOUT: Matmul test did not complete");
        $finish;
    end

endmodule
