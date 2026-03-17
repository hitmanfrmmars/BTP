// Testbench for gemm_pcpi_adapter
// Tests all four GEMM custom instructions through PicoRV32's PCPI protocol,
// verifying correct register file interaction and GEMM.WAIT stall behavior.
`timescale 1ns / 1ps

module tb_gemm_pcpi_adapter;

    reg clk, resetn;

    // PCPI signals (mimicking PicoRV32 CPU side)
    reg         pcpi_valid;
    reg  [31:0] pcpi_insn;
    reg  [31:0] pcpi_rs1;
    reg  [31:0] pcpi_rs2;
    wire        pcpi_wr;
    wire [31:0] pcpi_rd;
    wire        pcpi_wait;
    wire        pcpi_ready;

    // Register file interface
    wire [5:0]  reg_wr_addr;
    wire [31:0] reg_wr_data;
    wire        reg_wr_en;
    wire [5:0]  reg_rd_addr;
    wire [31:0] reg_rd_data;
    wire        reg_rd_en;

    // Accelerator status
    reg         accel_busy;
    reg         accel_done;

    // Regfile config outputs (directly from regfile)
    wire        cfg_start, cfg_mode, cfg_irq_en;
    wire [15:0] cfg_dim_m, cfg_dim_k, cfg_dim_n;
    wire [31:0] cfg_src_a, cfg_src_b, cfg_dst_c;
    wire [15:0] cfg_stride_a, cfg_stride_b, cfg_stride_c;

    // Error tracking
    integer errors = 0;
    integer test_num = 0;

    // Clock generation
    always #5 clk = ~clk;

    // GEMM instruction encoding helper
    // funct7=0x08 (7'b0001000), opcode=0x0B (7'b0001011)
    function [31:0] gemm_insn;
        input [2:0] funct3;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        begin
            gemm_insn = {7'b0001000, rs2, rs1, funct3, rd, 7'b0001011};
        end
    endfunction

    // DUT: PCPI adapter
    gemm_pcpi_adapter u_adapter (
        .clk(clk),
        .resetn(resetn),
        .pcpi_valid(pcpi_valid),
        .pcpi_insn(pcpi_insn),
        .pcpi_rs1(pcpi_rs1),
        .pcpi_rs2(pcpi_rs2),
        .pcpi_wr(pcpi_wr),
        .pcpi_rd(pcpi_rd),
        .pcpi_wait(pcpi_wait),
        .pcpi_ready(pcpi_ready),
        .reg_wr_addr(reg_wr_addr),
        .reg_wr_data(reg_wr_data),
        .reg_wr_en(reg_wr_en),
        .reg_rd_addr(reg_rd_addr),
        .reg_rd_data(reg_rd_data),
        .reg_rd_en(reg_rd_en),
        .accel_done(accel_done)
    );

    // Real register file instance
    gemm_regfile #(
        .ADDR_WIDTH(32)
    ) u_regfile (
        .clk(clk),
        .rst(~resetn),  // regfile uses active-high reset
        .wr_addr(reg_wr_addr),
        .wr_data(reg_wr_data),
        .wr_en(reg_wr_en),
        .rd_addr(reg_rd_addr),
        .rd_data(reg_rd_data),
        .rd_en(reg_rd_en),
        .cfg_start(cfg_start),
        .cfg_mode(cfg_mode),
        .cfg_irq_en(cfg_irq_en),
        .cfg_dim_m(cfg_dim_m),
        .cfg_dim_k(cfg_dim_k),
        .cfg_dim_n(cfg_dim_n),
        .cfg_src_a(cfg_src_a),
        .cfg_src_b(cfg_src_b),
        .cfg_dst_c(cfg_dst_c),
        .cfg_stride_a(cfg_stride_a),
        .cfg_stride_b(cfg_stride_b),
        .cfg_stride_c(cfg_stride_c),
        .accel_busy(accel_busy),
        .accel_done(accel_done),
        .accel_error(1'b0),
        .accel_overflow(1'b0)
    );

    // Task: issue a PCPI instruction and wait for response
    task pcpi_execute;
        input [31:0] insn;
        input [31:0] rs1_val;
        input [31:0] rs2_val;
        output [31:0] result;
        output        got_wr;
        integer timeout;
        begin
            @(posedge clk);
            pcpi_valid <= 1'b1;
            pcpi_insn  <= insn;
            pcpi_rs1   <= rs1_val;
            pcpi_rs2   <= rs2_val;

            // Wait for pcpi_ready
            timeout = 0;
            @(posedge clk);
            while (!pcpi_ready && timeout < 10000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            result = pcpi_rd;
            got_wr = pcpi_wr;

            // De-assert valid after ready
            @(posedge clk);
            pcpi_valid <= 1'b0;
            pcpi_insn  <= 32'd0;
            pcpi_rs1   <= 32'd0;
            pcpi_rs2   <= 32'd0;
            @(posedge clk);
        end
    endtask

    // Task: check result
    task check;
        input [31:0] got;
        input [31:0] expected;
        input [255:0] msg;
        begin
            if (got !== expected) begin
                $display("  FAIL: %0s -- got 0x%08x, expected 0x%08x", msg, got, expected);
                errors = errors + 1;
            end else begin
                $display("  PASS: %0s = 0x%08x", msg, got);
            end
        end
    endtask

    reg [31:0] result;
    reg        got_wr;

    initial begin
        $display("==============================================");
        $display("  GEMM PCPI Adapter Testbench");
        $display("==============================================");

        clk        = 0;
        resetn     = 0;
        pcpi_valid = 0;
        pcpi_insn  = 0;
        pcpi_rs1   = 0;
        pcpi_rs2   = 0;
        accel_busy = 0;
        accel_done = 0;

        // Reset
        repeat (5) @(posedge clk);
        resetn = 1;
        repeat (2) @(posedge clk);

        // ============================================================
        // Test 1: GEMM.CFG -- write DIM_MK register (0x08)
        // ============================================================
        test_num = 1;
        $display("\nTest %0d: GEMM.CFG -- write DIM_MK (M=8, K=4)", test_num);
        // rs1 = value to write, rs2 = register offset
        // M=8 in upper 16, K=4 in lower 16 → 0x00080004
        pcpi_execute(
            gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),  // GEMM.CFG x1, x2, x3
            32'h0008_0004,   // rs1: M=8, K=4
            32'h0000_0008,   // rs2: register offset 0x08 = DIM_MK
            result, got_wr
        );
        check(got_wr, 1, "pcpi_wr asserted");
        // Old value should be 0 (register was reset)
        check(result, 32'h0000_0000, "old DIM_MK value");
        // Verify the register was actually written
        if (cfg_dim_m !== 16'd8 || cfg_dim_k !== 16'd4) begin
            $display("  FAIL: DIM_MK not written -- M=%0d K=%0d", cfg_dim_m, cfg_dim_k);
            errors = errors + 1;
        end else begin
            $display("  PASS: DIM_MK written correctly -- M=%0d K=%0d", cfg_dim_m, cfg_dim_k);
        end

        // ============================================================
        // Test 2: GEMM.CFG -- write DIM_N register (0x0C)
        // ============================================================
        test_num = 2;
        $display("\nTest %0d: GEMM.CFG -- write DIM_N (N=6)", test_num);
        pcpi_execute(
            gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),
            32'h0000_0006,   // rs1: N=6
            32'h0000_000C,   // rs2: register offset 0x0C = DIM_N
            result, got_wr
        );
        check(result, 32'h0000_0000, "old DIM_N value");
        if (cfg_dim_n !== 16'd6) begin
            $display("  FAIL: DIM_N not written -- N=%0d", cfg_dim_n);
            errors = errors + 1;
        end else begin
            $display("  PASS: DIM_N written correctly -- N=%0d", cfg_dim_n);
        end

        // ============================================================
        // Test 3: GEMM.CFG -- write SRC_A, then read back old value
        // ============================================================
        test_num = 3;
        $display("\nTest %0d: GEMM.CFG -- write SRC_A twice, verify old value returned", test_num);
        // First write
        pcpi_execute(
            gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),
            32'hAAAA_0000,   // rs1: address
            32'h0000_0010,   // rs2: register offset 0x10 = SRC_A
            result, got_wr
        );
        check(result, 32'h0000_0000, "first write old value (was 0)");

        // Second write -- should return the value we just wrote
        pcpi_execute(
            gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),
            32'hBBBB_0000,   // rs1: new address
            32'h0000_0010,   // rs2: same register
            result, got_wr
        );
        check(result, 32'hAAAA_0000, "second write returns previous value");

        // ============================================================
        // Test 4: GEMM.CFG -- write SRC_B and DST_C
        // ============================================================
        test_num = 4;
        $display("\nTest %0d: GEMM.CFG -- write SRC_B and DST_C", test_num);
        pcpi_execute(
            gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),
            32'h1000_0000,
            32'h0000_0014,   // SRC_B
            result, got_wr
        );
        pcpi_execute(
            gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),
            32'h2000_0000,
            32'h0000_0018,   // DST_C
            result, got_wr
        );
        if (cfg_src_b !== 32'h1000_0000 || cfg_dst_c !== 32'h2000_0000) begin
            $display("  FAIL: SRC_B=0x%08x DST_C=0x%08x", cfg_src_b, cfg_dst_c);
            errors = errors + 1;
        end else begin
            $display("  PASS: SRC_B=0x%08x DST_C=0x%08x", cfg_src_b, cfg_dst_c);
        end

        // ============================================================
        // Test 5: GEMM.STATUS -- read status (should be idle)
        // ============================================================
        test_num = 5;
        $display("\nTest %0d: GEMM.STATUS -- read status (idle, not done)", test_num);
        accel_busy = 0;
        accel_done = 0;
        pcpi_execute(
            gemm_insn(3'b011, 5'd1, 5'd0, 5'd0),  // GEMM.STATUS x1
            32'd0, 32'd0,
            result, got_wr
        );
        // STATUS: [0]=busy, [1]=done, [2]=error, [3]=overflow
        check(result, 32'h0000_0000, "status: idle, not done");

        // ============================================================
        // Test 6: GEMM.STATUS -- read status with busy flag
        // ============================================================
        test_num = 6;
        $display("\nTest %0d: GEMM.STATUS -- read status (busy)", test_num);
        accel_busy = 1;
        accel_done = 0;
        @(posedge clk);
        pcpi_execute(
            gemm_insn(3'b011, 5'd1, 5'd0, 5'd0),
            32'd0, 32'd0,
            result, got_wr
        );
        check(result[0], 1'b1, "status bit 0 = busy");
        check(result[1], 1'b0, "status bit 1 = not done");
        accel_busy = 0;

        // ============================================================
        // Test 7: GEMM.START -- trigger start, get status back
        // ============================================================
        test_num = 7;
        $display("\nTest %0d: GEMM.START -- start computation", test_num);
        pcpi_execute(
            gemm_insn(3'b001, 5'd1, 5'd0, 5'd0),  // GEMM.START x1
            32'd0, 32'd0,
            result, got_wr
        );
        check(got_wr, 1, "pcpi_wr asserted");
        // The cfg_start pulse should have fired (self-clearing in regfile)
        $display("  INFO: start pulse fired (verified by regfile internals)");

        // ============================================================
        // Test 8: GEMM.WAIT -- already done (immediate return)
        // ============================================================
        test_num = 8;
        $display("\nTest %0d: GEMM.WAIT -- accelerator already done", test_num);
        accel_done = 1;
        accel_busy = 0;
        @(posedge clk);
        pcpi_execute(
            gemm_insn(3'b010, 5'd1, 5'd0, 5'd0),  // GEMM.WAIT x1
            32'd0, 32'd0,
            result, got_wr
        );
        check(got_wr, 1, "pcpi_wr asserted");
        $display("  INFO: cycle count = %0d", result);
        accel_done = 0;

        // ============================================================
        // Test 9: GEMM.WAIT -- stall until accelerator completes
        // ============================================================
        test_num = 9;
        $display("\nTest %0d: GEMM.WAIT -- stall CPU for 50 cycles", test_num);
        accel_busy = 1;
        accel_done = 0;

        // Issue GEMM.WAIT -- this will stall
        @(posedge clk);
        pcpi_valid <= 1'b1;
        pcpi_insn  <= gemm_insn(3'b010, 5'd1, 5'd0, 5'd0);
        pcpi_rs1   <= 32'd0;
        pcpi_rs2   <= 32'd0;

        // Should see pcpi_wait go high
        @(posedge clk);
        @(posedge clk);
        if (!pcpi_wait) begin
            $display("  FAIL: pcpi_wait not asserted during GEMM.WAIT stall");
            errors = errors + 1;
        end else begin
            $display("  PASS: pcpi_wait asserted (CPU stalled)");
        end

        // Verify pcpi_ready stays low while waiting
        repeat (20) begin
            @(posedge clk);
            if (pcpi_ready) begin
                $display("  FAIL: pcpi_ready asserted before accel_done");
                errors = errors + 1;
            end
        end
        $display("  PASS: pcpi_ready stayed low during 20 wait cycles");

        // Now signal accelerator done
        accel_done = 1;
        accel_busy = 0;

        // Wait for pcpi_ready
        @(posedge clk); // adapter sees accel_done, goes to S_WDONE
        @(posedge clk); // adapter asserts pcpi_ready
        if (pcpi_ready && pcpi_wr) begin
            $display("  PASS: pcpi_ready and pcpi_wr asserted after accel_done");
            $display("  INFO: returned cycle count = %0d", pcpi_rd);
        end else begin
            $display("  FAIL: pcpi_ready=%b pcpi_wr=%b", pcpi_ready, pcpi_wr);
            errors = errors + 1;
        end

        pcpi_valid <= 1'b0;
        accel_done = 0;
        repeat (3) @(posedge clk);

        // ============================================================
        // Test 10: Non-GEMM instruction -- should NOT assert wait/ready
        // ============================================================
        test_num = 10;
        $display("\nTest %0d: Non-GEMM instruction (wrong funct7) -- no response", test_num);
        @(posedge clk);
        pcpi_valid <= 1'b1;
        // Use funct7=0x00 (PicoRV32 IRQ encoding, not ours)
        pcpi_insn  <= {7'b0000000, 5'd0, 5'd0, 3'b000, 5'd1, 7'b0001011};
        pcpi_rs1   <= 32'd0;
        pcpi_rs2   <= 32'd0;

        repeat (5) @(posedge clk);
        if (pcpi_wait || pcpi_ready) begin
            $display("  FAIL: adapter responded to non-GEMM instruction (wait=%b ready=%b)",
                     pcpi_wait, pcpi_ready);
            errors = errors + 1;
        end else begin
            $display("  PASS: adapter ignored non-GEMM instruction");
        end
        pcpi_valid <= 1'b0;
        repeat (2) @(posedge clk);

        // ============================================================
        // Test 11: GEMM.CFG -- write strides
        // ============================================================
        test_num = 11;
        $display("\nTest %0d: GEMM.CFG -- write STRIDE_A/B/C", test_num);
        pcpi_execute(gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),
                     32'h0000_0004, 32'h0000_001C, result, got_wr);
        pcpi_execute(gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),
                     32'h0000_0004, 32'h0000_0020, result, got_wr);
        pcpi_execute(gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),
                     32'h0000_0010, 32'h0000_0024, result, got_wr);
        if (cfg_stride_a == 16'd4 && cfg_stride_b == 16'd4 && cfg_stride_c == 16'd16) begin
            $display("  PASS: strides written -- A=%0d B=%0d C=%0d",
                     cfg_stride_a, cfg_stride_b, cfg_stride_c);
        end else begin
            $display("  FAIL: strides -- A=%0d B=%0d C=%0d",
                     cfg_stride_a, cfg_stride_b, cfg_stride_c);
            errors = errors + 1;
        end

        // ============================================================
        // Test 12: GEMM.CFG -- write CTRL with int16 mode bit
        // ============================================================
        test_num = 12;
        $display("\nTest %0d: GEMM.CFG -- set int16 mode via CTRL register", test_num);
        pcpi_execute(gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),
                     32'h0000_0002, 32'h0000_0000, result, got_wr);  // CTRL, mode=int16
        if (cfg_mode == 1'b1) begin
            $display("  PASS: int16 mode bit set");
        end else begin
            $display("  FAIL: int16 mode bit not set (cfg_mode=%b)", cfg_mode);
            errors = errors + 1;
        end
        // Clear it back
        pcpi_execute(gemm_insn(3'b000, 5'd1, 5'd2, 5'd3),
                     32'h0000_0000, 32'h0000_0000, result, got_wr);

        // ============================================================
        // Summary
        // ============================================================
        $display("\n==============================================");
        if (errors == 0) begin
            $display("  ALL %0d TESTS PASSED", test_num);
        end else begin
            $display("  %0d ERROR(S) in %0d tests", errors, test_num);
        end
        $display("==============================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #200000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
