// SoC-level testbench for GEMM FAST stress test (golden model verification)
// No SW GEMM -- uses precomputed checksums, runs 10-100x faster than original
`timescale 1ns/1ps

module tb_stress_fast;

    reg clk, resetn;
    wire trap, accel_busy, accel_done, irq;
    wire debug_wr;
    wire [31:0] debug_data;

    gemm_soc_top #(
        .MEM_WORDS     (32768),
        .FIRMWARE_FILE ("stress_test_fast.hex"),
        .ARRAY_SIZE    (8),
        .ACC_WIDTH     (48),
        .STACKADDR     (32'h0002_0000),
        .PROGADDR_RESET(32'h0000_0000)
    ) dut (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (trap),
        .accel_busy(accel_busy),
        .accel_done(accel_done),
        .irq       (irq),
        .debug_wr  (debug_wr),
        .debug_data(debug_data)
    );

    always #5 clk = ~clk;

    integer total_pass, total_fail, cur_test;
    reg     test_done;
    integer t_start;

    always @(posedge clk) begin
        if (debug_wr) begin
            if ((debug_data & 32'hFFFF0000) == 32'hAAAA0000) begin
                cur_test = debug_data & 32'h0000FFFF;
                t_start = $time;
                $display("[GOLDEN] Test %0d started  (t=%0t)", cur_test, $time);
            end
            else if (debug_data == 32'h0000600D) begin
                $display("[GOLDEN] Test %0d PASSED  (%0d ns)", cur_test, $time - t_start);
                total_pass = total_pass + 1;
            end
            else if (debug_data == 32'h0000FA11) begin
                $display("[GOLDEN] Test %0d FAILED <<<", cur_test);
                total_fail = total_fail + 1;
            end
            else if (debug_data == 32'h0000DEAD) begin
                test_done = 1'b1;
            end
            else begin
                $display("[GOLDEN]   debug: 0x%08X", debug_data);
            end
        end
    end

    always @(posedge clk) begin
        if (trap) begin
            $display("[FATAL] PicoRV32 trapped at t=%0t", $time);
            $finish;
        end
    end

    initial begin
        clk        = 0;
        resetn     = 0;
        test_done  = 0;
        total_pass = 0;
        total_fail = 0;
        cur_test   = 0;
        t_start    = 0;

        repeat (20) @(posedge clk);
        resetn = 1;

        $display("=== GEMM Fast Stress Test (31 patterns: 21 int8 + 10 acc32) ===");
        $display("    21 int8 tests + 10 acc32 (32-bit accumulator) tests");
        $display("");

        fork
            begin wait (test_done); end
            begin
                repeat (80_000_000) @(posedge clk);
                $display("[TIMEOUT] Fast stress test did not complete in 80M cycles.");
                $finish;
            end
        join_any
        disable fork;

        repeat (10) @(posedge clk);

        $display("");
        $display("=== FAST STRESS TEST SUMMARY ===");
        $display("  Passed: %0d / 31", total_pass);
        $display("  Failed: %0d", total_fail);
        if (total_fail == 0 && total_pass == 31)
            $display("  RESULT: ALL 31 TESTS PASSED");
        else
            $display("  RESULT: FAILURES DETECTED");
        $display("================================");
        $finish;
    end

endmodule
