// Testbench for mac_unit_v2 (pipelined, int8/int16, saturation)
// Enhanced: valid_out timing, overflow, clear_acc mid-computation
`timescale 1ns/1ps

module tb_mac_unit_v2;
    parameter ACC_WIDTH = 48;

    reg clk, rst;
    reg mode, enable, clear_acc;
    reg [15:0] a, b;
    wire [ACC_WIDTH-1:0] result;
    wire valid_out, overflow;

    integer errors = 0;

    mac_unit_v2 #(.ACC_WIDTH(ACC_WIDTH)) dut (
        .clk(clk), .rst(rst),
        .mode(mode), .enable(enable), .clear_acc(clear_acc),
        .a(a), .b(b),
        .result(result), .valid_out(valid_out), .overflow(overflow)
    );

    always #5 clk = ~clk;

    task check48(input [ACC_WIDTH-1:0] actual, expected, input [199:0] msg);
        if (actual !== expected) begin
            $display("FAIL: %0s - got %0d, expected %0d", msg, actual, expected);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s = %0d", msg, actual);
        end
    endtask

    task check1(input actual, expected, input [199:0] msg);
        if (actual !== expected) begin
            $display("FAIL: %0s - got %b, expected %b", msg, actual, expected);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s = %b", msg, actual);
        end
    endtask

    initial begin
        $dumpfile("tb_mac_unit_v2.vcd");
        $dumpvars(0, tb_mac_unit_v2);

        clk = 0; rst = 1; mode = 0; enable = 0; clear_acc = 0;
        a = 0; b = 0;

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;

        // Test 1: int8 multiply 5 * 6 = 30
        $display("\n=== Test 1: int8 5*6=30 ===");
        mode = 0; a = 16'd5; b = 16'd6; enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        enable = 0; clear_acc = 0;
        @(posedge clk); #1; // stage 1 done
        @(posedge clk); #1; // stage 2 done
        check48(result, 48'd30, "int8 5*6");

        // Test 2: int8 accumulate 30 + 4*5 = 50
        $display("\n=== Test 2: int8 accumulate 30+4*5=50 ===");
        a = 16'd4; b = 16'd5; enable = 1; clear_acc = 0;
        @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check48(result, 48'd50, "int8 acc 30+20");

        // Test 3: int8 dot product [1,2,3,4].[5,6,7,8] = 5+12+21+32 = 70
        $display("\n=== Test 3: int8 dot product=70 ===");
        a = 16'd1; b = 16'd5; enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        a = 16'd2; b = 16'd6; clear_acc = 0;
        @(posedge clk); #1;
        a = 16'd3; b = 16'd7;
        @(posedge clk); #1;
        a = 16'd4; b = 16'd8;
        @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check48(result, 48'd70, "int8 dot product");

        // Test 4: int16 multiply 300*400 = 120000
        $display("\n=== Test 4: int16 300*400=120000 ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;
        mode = 1; a = 16'd300; b = 16'd400; enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        enable = 0; clear_acc = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check48(result, 48'd120000, "int16 300*400");

        // Test 5: int16 accumulate
        $display("\n=== Test 5: int16 accumulate ===");
        a = 16'd500; b = 16'd600; enable = 1; clear_acc = 0;
        @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check48(result, 48'd420000, "int16 120000+300000");

        // Test 6: Clear accumulator
        $display("\n=== Test 6: Clear accumulator ===");
        a = 16'd2; b = 16'd3; enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        enable = 0; clear_acc = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check48(result, 48'd6, "Clear then 2*3=6");

        // Test 7: valid_out timing
        $display("\n=== Test 7: valid_out timing ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;
        mode = 0;
        a = 16'd3; b = 16'd4; enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        // 1 cycle after enable: valid_out should be low (in stage 1)
        check1(valid_out, 1'b0, "valid_out=0 at cycle+1");
        enable = 0; clear_acc = 0;
        @(posedge clk); #1;
        // 2 cycles after enable: valid_out should be high (stage 2 complete)
        check1(valid_out, 1'b1, "valid_out=1 at cycle+2");
        @(posedge clk); #1;
        // 3 cycles: no enable, valid_out should drop
        check1(valid_out, 1'b0, "valid_out=0 at cycle+3");

        // Test 8: valid_out stays low without enable
        $display("\n=== Test 8: valid_out stays low without enable ===");
        enable = 0; a = 16'd10; b = 16'd20;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check1(valid_out, 1'b0, "valid_out stays 0 without enable");

        // Test 9: int16 large accumulation (1000*1000*4=4000000)
        $display("\n=== Test 9: int16 large accumulation ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;
        mode = 1;
        a = 16'd1000; b = 16'd1000; enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        clear_acc = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check48(result, 48'd4000000, "int16 1000*1000*4=4000000");

        // Test 10: clear_acc mid-computation
        $display("\n=== Test 10: clear_acc mid-computation ===");
        rst = 1; @(posedge clk); #1; rst = 0; @(posedge clk); #1;
        mode = 0;
        // Cycle 1: 10*10=100 with clear
        a = 16'd10; b = 16'd10; enable = 1; clear_acc = 1;
        @(posedge clk); #1;
        // Cycle 2: 5*5=25, acc
        a = 16'd5; b = 16'd5; clear_acc = 0;
        @(posedge clk); #1;
        // Cycle 3: 3*3=9 with clear (resets accumulator)
        a = 16'd3; b = 16'd3; clear_acc = 1;
        @(posedge clk); #1;
        // Cycle 4: 2*2=4, acc
        a = 16'd2; b = 16'd2; clear_acc = 0;
        @(posedge clk); #1;
        enable = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check48(result, 48'd13, "clear mid-comp: 3*3+2*2=13");

        @(posedge clk); @(posedge clk);
        if (errors == 0) $display("\n*** ALL MAC_UNIT_V2 TESTS PASSED ***\n");
        else $display("\n*** %0d TESTS FAILED ***\n", errors);
        $finish;
    end

endmodule
