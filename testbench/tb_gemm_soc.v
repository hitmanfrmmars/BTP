// End-to-end SoC testbench
// PicoRV32 boots from ROM, configures GEMM via PCPI custom instructions,
// runs a 4x4 int8 GEMM, and writes a completion marker to the debug port.
// Testbench reads result matrix from memory and verifies against golden model.
`timescale 1ns/1ps

module tb_gemm_soc;

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

    // Clock: 10ns period (100 MHz)
    always #5 clk = ~clk;

    // Track debug writes
    reg        test_done;
    reg        fw_pass;      // firmware reported PASS
    reg        fw_fail;      // firmware reported FAIL
    reg [31:0] fw_cycles;
    reg [31:0] debug_log [0:15];
    integer    debug_idx;

    always @(posedge clk) begin
        if (debug_wr) begin
            $display("[DEBUG] t=%0t  data=0x%08X", $time, debug_data);
            if (debug_idx < 16) begin
                debug_log[debug_idx] = debug_data;
                debug_idx = debug_idx + 1;
            end
            if (debug_data == 32'h0000DEAD)
                test_done = 1'b1;
            if (debug_data == 32'h0000600D)
                fw_pass = 1'b1;
            if (debug_data == 32'h0000FA11)
                fw_fail = 1'b1;
            if (!fw_pass && !fw_fail && debug_data != 32'h0000DEAD)
                fw_cycles = debug_data;
        end
    end

    // Monitor trap
    always @(posedge clk) begin
        if (trap) begin
            $display("[FATAL] PicoRV32 trapped at t=%0t", $time);
            $display("  CPU PC was accessing address 0x%08X", dut.u_cpu.mem_addr);
            $finish;
        end
    end

    // Expected result matrix (C = A * B, int8 output packed 4 per word)
    // A = [[1,2,0,0],[0,1,2,0],[0,0,1,2],[1,0,0,1]]
    // B = [[1,1,0,0],[0,1,1,0],[0,0,1,1],[1,0,0,1]]
    // C = [[1,3,2,0],[0,1,3,2],[2,0,1,3],[2,1,0,1]]
    // STRIDE_C = 4 bytes, so rows are at consecutive word addresses.
    // Each word: {C[r][3], C[r][2], C[r][1], C[r][0]} packed as bytes.

    integer errors;
    integer r, c;
    reg [7:0] expected [0:3][0:3]; // [row][col]
    reg [31:0] row_word;
    reg [7:0]  actual_byte;

    initial begin
        expected[0][0] = 1; expected[0][1] = 3; expected[0][2] = 2; expected[0][3] = 0;
        expected[1][0] = 0; expected[1][1] = 1; expected[1][2] = 3; expected[1][3] = 2;
        expected[2][0] = 2; expected[2][1] = 0; expected[2][2] = 1; expected[2][3] = 3;
        expected[3][0] = 2; expected[3][1] = 1; expected[3][2] = 0; expected[3][3] = 1;
    end

    initial begin
        $dumpfile("tb_gemm_soc.vcd");
        $dumpvars(0, tb_gemm_soc);

        clk       = 0;
        resetn    = 0;
        test_done = 0;
        fw_pass   = 0;
        fw_fail   = 0;
        fw_cycles = 0;
        debug_idx = 0;
        errors    = 0;

        // Reset for 20 cycles
        repeat (20) @(posedge clk);
        resetn = 1;

        $display("=== GEMM SoC Integration Test ===");
        $display("PicoRV32 booting from 0x00000000...");
        $display("Firmware configures GEMM 4x4 int8, starts, waits, signals done.");
        $display("");

        // Wait for test_done or timeout
        fork
            begin
                wait (test_done);
            end
            begin
                repeat (100000) @(posedge clk);
                $display("[TIMEOUT] Test did not complete in 100000 cycles.");
                $display("  accel_busy=%b accel_done=%b", accel_busy, accel_done);
                $display("  debug_idx=%0d", debug_idx);
                $finish;
            end
        join_any
        disable fork;

        // Allow a few cycles for final writes to settle
        repeat (10) @(posedge clk);

        // Check firmware self-test result
        $display("");
        $display("--- Firmware Self-Test ---");
        if (fw_pass)
            $display("  Firmware reported: PASS (cycle count = %0d)", fw_cycles);
        else if (fw_fail) begin
            $display("  Firmware reported: FAIL");
            errors = errors + 1;
        end else begin
            $display("  Firmware did not report PASS or FAIL");
            errors = errors + 1;
        end

        $display("");
        $display("--- Verifying Result Matrix C (at 0x00010200, packed int8) ---");

        // C at byte address 0x00010200 = word 0x4080.
        // STRIDE_C = 4 bytes, so rows at consecutive words: 0x4080, 0x4081, 0x4082, 0x4083.
        for (r = 0; r < 4; r = r + 1) begin
            row_word = dut.memory[32'h4080 + r];
            $display("  Row %0d word = 0x%08X", r, row_word);
            for (c = 0; c < 4; c = c + 1) begin
                actual_byte = row_word[c*8 +: 8];
                if (actual_byte !== expected[r][c]) begin
                    $display("    FAIL C[%0d][%0d]: expected=%0d  got=%0d",
                             r, c, expected[r][c], actual_byte);
                    errors = errors + 1;
                end else begin
                    $display("    OK   C[%0d][%0d] = %0d", r, c, actual_byte);
                end
            end
        end

        $display("");
        if (errors == 0)
            $display("=== ALL CHECKS PASSED ===");
        else
            $display("=== %0d ERRORS ===", errors);

        $finish;
    end

endmodule
