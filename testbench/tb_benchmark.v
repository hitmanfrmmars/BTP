// Benchmark testbench: captures SW vs HW GEMM cycle counts from debug port.
//
// Debug protocol:
//   0xBEEF0000 | size  -- test header
//   SW cycles           -- software GEMM cycle count
//   HW cycles           -- hardware GEMM cycle count
//   0x600D / 0xFA11     -- pass/fail
//   ... repeat per size ...
//   0x0000DEAD          -- done
`timescale 1ns/1ps

module tb_benchmark;

    reg clk, resetn;

    wire trap;
    wire accel_busy, accel_done, irq;
    wire debug_wr;
    wire [31:0] debug_data;

    gemm_soc_top #(
        .MEM_WORDS     (32768),
        .FIRMWARE_FILE ("firmware.hex"),
        .ARRAY_SIZE    (4),
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

    reg        test_done;
    integer    total_errors;

    // State machine to parse debug output
    localparam S_HEADER  = 0;
    localparam S_SW_CYC  = 1;
    localparam S_HW_CYC  = 2;
    localparam S_RESULT  = 3;

    integer parse_state;
    integer cur_size;
    integer sw_cycles, hw_cycles;
    real    speedup;

    integer test_num;

    always @(posedge clk) begin
        if (debug_wr) begin
            if (debug_data == 32'h0000DEAD) begin
                test_done = 1'b1;
            end else begin
                case (parse_state)
                    S_HEADER: begin
                        if (debug_data[31:16] == 16'hBEEF) begin
                            cur_size = debug_data[15:0];
                            test_num = test_num + 1;
                            $display("");
                            $display("--- Test %0d: %0dx%0d GEMM (int8) ---", test_num, cur_size, cur_size);
                            parse_state = S_SW_CYC;
                        end
                    end
                    S_SW_CYC: begin
                        sw_cycles = debug_data;
                        $display("  Software cycles: %0d", sw_cycles);
                        parse_state = S_HW_CYC;
                    end
                    S_HW_CYC: begin
                        hw_cycles = debug_data;
                        speedup = $itor(sw_cycles) / $itor(hw_cycles);
                        $display("  Hardware cycles: %0d", hw_cycles);
                        $display("  Speedup:         %.1fx", speedup);
                        parse_state = S_RESULT;
                    end
                    S_RESULT: begin
                        if (debug_data == 32'h0000600D) begin
                            $display("  Verify:          PASS");
                        end else begin
                            $display("  Verify:          FAIL");
                            total_errors = total_errors + 1;
                        end
                        parse_state = S_HEADER;
                    end
                endcase
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
        clk          = 0;
        resetn       = 0;
        test_done    = 0;
        total_errors = 0;
        parse_state  = S_HEADER;
        test_num     = 0;

        repeat (20) @(posedge clk);
        resetn = 1;

        $display("===========================================");
        $display("  GEMM Benchmark: Software vs. Hardware");
        $display("  PicoRV32 @ 100 MHz, 4x4 MAC array");
        $display("===========================================");

        fork
            begin
                wait (test_done);
            end
            begin
                repeat (20000000) @(posedge clk);
                $display("[TIMEOUT] Benchmark did not complete.");
                $finish;
            end
        join_any
        disable fork;

        repeat (10) @(posedge clk);

        $display("");
        $display("===========================================");
        if (total_errors == 0)
            $display("  ALL BENCHMARKS PASSED");
        else
            $display("  %0d BENCHMARKS FAILED", total_errors);
        $display("===========================================");

        $finish;
    end

endmodule
