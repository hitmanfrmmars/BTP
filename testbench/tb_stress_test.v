// SoC-level testbench for GEMM stress test firmware
// Boots PicoRV32, runs 21 stress test patterns, checks debug port for PASS/FAIL
`timescale 1ns/1ps

module tb_stress_test;

    reg clk, resetn;
    wire trap, accel_busy, accel_done, irq;
    wire debug_wr;
    wire [31:0] debug_data;

    gemm_soc_top #(
        .MEM_WORDS     (32768),
        .FIRMWARE_FILE ("stress_test.hex"),
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

    always @(posedge clk) begin
        if (debug_wr) begin
            if ((debug_data & 32'hFFFF0000) == 32'hAAAA0000) begin
                cur_test = debug_data & 32'h0000FFFF;
                $display("[STRESS] Test %0d started  (t=%0t)", cur_test, $time);
            end
            else if (debug_data == 32'h0000600D) begin
                $display("[STRESS] Test %0d PASSED", cur_test);
                total_pass = total_pass + 1;
            end
            else if (debug_data == 32'h0000FA11) begin
                $display("[STRESS] Test %0d FAILED <<<", cur_test);
                total_fail = total_fail + 1;
            end
            else if (debug_data == 32'h0000DEAD) begin
                test_done = 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (trap) begin
            $display("[FATAL] PicoRV32 trapped at t=%0t, PC=%08X", $time,
                     dut.u_cpu.mem_addr);
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

        repeat (20) @(posedge clk);
        resetn = 1;

        $display("=== GEMM Stress Test (21 patterns, 8x8 array) ===");
        $display("");

        fork
            begin wait (test_done); end
            begin
                repeat (50_000_000) @(posedge clk);
                $display("[TIMEOUT] Stress test did not complete in 50M cycles.");
                $finish;
            end
        join_any
        disable fork;

        repeat (10) @(posedge clk);

        $display("");
        $display("=== STRESS TEST SUMMARY ===");
        $display("  Passed: %0d", total_pass);
        $display("  Failed: %0d", total_fail);
        if (total_fail == 0 && total_pass > 0)
            $display("  RESULT: ALL PASSED");
        else
            $display("  RESULT: FAILURES DETECTED");
        $display("===========================");
        $finish;
    end

endmodule
