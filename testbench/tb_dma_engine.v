// Testbench for dma_engine (burst, 2D strided, bidirectional)
// Enhanced: data verification for LOAD/STORE, 2D stride, zero-count edge case
`timescale 1ns/1ps

module tb_dma_engine;
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    reg clk, rst;
    reg start, direction;
    reg [ADDR_WIDTH-1:0] src_addr, dst_addr;
    reg [15:0] x_count, y_count, src_stride, dst_stride;
    reg [3:0] burst_len;
    wire done, busy, irq;

    wire [ADDR_WIDTH-1:0] mem_addr;
    wire mem_read, mem_write;
    wire [DATA_WIDTH-1:0] mem_wdata;
    wire [3:0] mem_burst_len;
    reg  [DATA_WIDTH-1:0] mem_rdata;
    reg  mem_ready;

    wire [9:0] spad_addr;
    wire [DATA_WIDTH-1:0] spad_wdata;
    wire spad_we, spad_re;
    wire [DATA_WIDTH-1:0] spad_rdata;

    integer errors = 0;
    integer i, j;
    reg [31:0] expected;
    integer done_seen;

    // Simulated main memory (16KB)
    reg [31:0] main_mem [0:4095];

    // Scratchpad instance
    scratchpad_mem #(.ADDR_WIDTH(10), .DATA_WIDTH(32), .DEPTH(256)) spad_inst (
        .clk(clk), .rst(rst),
        .addr_a(spad_addr), .wdata_a(spad_wdata), .we_a(spad_we), .re_a(spad_re), .rdata_a(spad_rdata),
        .addr_b(10'd0), .wdata_b(32'd0), .we_b(1'b0), .re_b(1'b0), .rdata_b()
    );

    dma_engine #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .start(start), .direction(direction),
        .src_addr(src_addr), .dst_addr(dst_addr),
        .x_count(x_count), .y_count(y_count),
        .src_stride(src_stride), .dst_stride(dst_stride),
        .burst_len(burst_len),
        .done(done), .busy(busy), .irq(irq),
        .mem_addr(mem_addr), .mem_read(mem_read), .mem_write(mem_write),
        .mem_wdata(mem_wdata), .mem_burst_len(mem_burst_len),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .spad_addr(spad_addr), .spad_wdata(spad_wdata),
        .spad_we(spad_we), .spad_re(spad_re), .spad_rdata(spad_rdata)
    );

    always #5 clk = ~clk;

    // Burst-aware memory response model
    reg [3:0]  mem_bcnt;
    reg [31:0] mem_baddr;
    reg        mem_in_rburst;

    always @(posedge clk) begin
        if (rst) begin
            mem_ready     <= 1'b0;
            mem_rdata     <= 32'd0;
            mem_bcnt      <= 4'd0;
            mem_baddr     <= 32'd0;
            mem_in_rburst <= 1'b0;
        end else if (mem_in_rburst) begin
            if (mem_bcnt == 4'd0) begin
                mem_in_rburst <= 1'b0;
                mem_ready     <= 1'b0;
            end else begin
                mem_rdata <= main_mem[mem_baddr[13:2]];
                mem_ready <= 1'b1;
                mem_bcnt  <= mem_bcnt - 4'd1;
                mem_baddr <= mem_baddr + 32'd4;
            end
        end else if (mem_read) begin
            mem_rdata     <= main_mem[mem_addr[13:2]];
            mem_ready     <= 1'b1;
            mem_baddr     <= mem_addr + 32'd4;
            mem_bcnt      <= mem_burst_len;
            mem_in_rburst <= (mem_burst_len > 4'd0);
        end else if (mem_write) begin
            main_mem[mem_addr[13:2]] <= mem_wdata;
            mem_ready <= 1'b1;
        end else begin
            mem_ready <= 1'b0;
        end
    end

    // Helper task: start a DMA transfer with proper timing
    task dma_start_transfer(
        input        dir,
        input [31:0] src, dst,
        input [15:0] xc, yc, ss, ds
    );
        begin
            direction  = dir;
            src_addr   = src;
            dst_addr   = dst;
            x_count    = xc;
            y_count    = yc;
            src_stride = ss;
            dst_stride = ds;
            burst_len  = (xc > 16'd0) ? xc[3:0] - 4'd1 : 4'd0;
            start = 1;
            @(posedge clk); #1;
            start = 0;
        end
    endtask

    // Helper task: wait for DMA done
    task wait_dma_done;
        integer timeout;
        begin
            timeout = 0;
            while (!done && timeout < 2000) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
            end
            if (timeout >= 2000) begin
                $display("FAIL: DMA transfer timed out");
                errors = errors + 1;
            end
            @(posedge clk); #1; // extra cycle for signals to settle
        end
    endtask

    initial begin
        $dumpfile("tb_dma_engine.vcd");
        $dumpvars(0, tb_dma_engine);

        clk = 0; rst = 1; start = 0; direction = 0;
        src_addr = 0; dst_addr = 0;
        x_count = 0; y_count = 0;
        src_stride = 0; dst_stride = 0;
        burst_len = 4'd0;
        mem_rdata = 0; mem_ready = 0;

        // Initialize main memory with known pattern
        for (i = 0; i < 4096; i = i + 1)
            main_mem[i] = 32'hA000_0000 + i;

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;
        @(posedge clk); #1;

        // ============================================================
        // Test 1: 1D LOAD 4 words + data verification
        // ============================================================
        $display("\n=== Test 1: 1D LOAD 4 words with data verify ===");
        dma_start_transfer(0, 32'h0000_0000, 32'h0000_0000, 16'd4, 16'd1, 16'd16, 16'd16);
        wait_dma_done;

        for (i = 0; i < 4; i = i + 1) begin
            expected = 32'hA000_0000 + i;
            if (spad_inst.mem[i] !== expected) begin
                $display("FAIL: spad[%0d] = %h, expected %h", i, spad_inst.mem[i], expected);
                errors = errors + 1;
            end else begin
                $display("PASS: spad[%0d] = %h", i, spad_inst.mem[i]);
            end
        end

        // ============================================================
        // Test 2: 2D LOAD 4x2 strided + data verify
        // src_stride=32 (8 words between source rows), dst_stride=16 (contiguous)
        // Source row 0: words 0..3, row 1: words 8..11
        // Dest: spad word 16..23
        // ============================================================
        $display("\n=== Test 2: 2D LOAD 4x2 strided with data verify ===");
        @(posedge clk); #1;
        dma_start_transfer(0, 32'h0000_0000, 32'h0000_0040, 16'd4, 16'd2, 16'd32, 16'd16);
        wait_dma_done;

        // Row 0: spad words 16..19 from main_mem[0..3]
        for (i = 0; i < 4; i = i + 1) begin
            expected = 32'hA000_0000 + i;
            if (spad_inst.mem[16 + i] !== expected) begin
                $display("FAIL: 2D spad[%0d] = %h, expected %h", 16+i, spad_inst.mem[16+i], expected);
                errors = errors + 1;
            end else begin
                $display("PASS: 2D spad[%0d] = %h (row 0)", 16+i, spad_inst.mem[16+i]);
            end
        end
        // Row 1: spad words 20..23 from main_mem[8..11]
        for (i = 0; i < 4; i = i + 1) begin
            expected = 32'hA000_0000 + 8 + i;
            if (spad_inst.mem[20 + i] !== expected) begin
                $display("FAIL: 2D spad[%0d] = %h, expected %h", 20+i, spad_inst.mem[20+i], expected);
                errors = errors + 1;
            end else begin
                $display("PASS: 2D spad[%0d] = %h (row 1)", 20+i, spad_inst.mem[20+i]);
            end
        end

        // ============================================================
        // Test 3: 1D STORE 4 words + data verify
        // spad words 0..3 already loaded from Test 1
        // ============================================================
        $display("\n=== Test 3: 1D STORE 4 words with data verify ===");
        @(posedge clk); #1;
        dma_start_transfer(1, 32'h0000_0000, 32'h0000_2000, 16'd4, 16'd1, 16'd16, 16'd16);
        wait_dma_done;

        for (i = 0; i < 4; i = i + 1) begin
            expected = 32'hA000_0000 + i;
            if (main_mem[2048 + i] !== expected) begin
                $display("FAIL: main_mem[%0d] = %h, expected %h", 2048+i, main_mem[2048+i], expected);
                errors = errors + 1;
            end else begin
                $display("PASS: main_mem[%0d] = %h (STORE verified)", 2048+i, main_mem[2048+i]);
            end
        end

        // ============================================================
        // Test 4: Zero x_count edge case
        // ============================================================
        $display("\n=== Test 4: Zero x_count edge case ===");
        @(posedge clk); #1;
        dma_start_transfer(0, 32'h0000_0000, 32'h0000_0000, 16'd0, 16'd4, 16'd16, 16'd16);

        done_seen = 0;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            if (done) begin
                done_seen = 1;
                i = 20; // break
            end
        end
        if (done_seen) begin
            $display("PASS: Zero x_count completed without hanging");
        end else begin
            $display("FAIL: Zero x_count did not complete (hung)");
            errors = errors + 1;
        end

        // ============================================================
        // Test 5: Zero y_count edge case
        // ============================================================
        $display("\n=== Test 5: Zero y_count edge case ===");
        @(posedge clk); #1;
        @(posedge clk); #1;
        dma_start_transfer(0, 32'h0000_0000, 32'h0000_0000, 16'd4, 16'd0, 16'd16, 16'd16);

        done_seen = 0;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #1;
            if (done) begin
                done_seen = 1;
                i = 20; // break
            end
        end
        if (done_seen) begin
            $display("PASS: Zero y_count completed without hanging");
        end else begin
            $display("FAIL: Zero y_count did not complete (hung)");
            errors = errors + 1;
        end

        // ============================================================
        // Test 6: Back-to-back LOAD then STORE (direction change)
        // ============================================================
        $display("\n=== Test 6: Back-to-back LOAD then STORE ===");
        @(posedge clk); #1;
        @(posedge clk); #1;

        // LOAD 2 words into spad word 32
        dma_start_transfer(0, 32'h0000_0100, 32'h0000_0080, 16'd2, 16'd1, 16'd8, 16'd8);
        wait_dma_done;

        if (spad_inst.mem[32] !== (32'hA000_0000 + 64)) begin
            $display("FAIL: b2b LOAD spad[32] = %h, expected %h", spad_inst.mem[32], 32'hA000_0000 + 64);
            errors = errors + 1;
        end else $display("PASS: b2b LOAD spad[32] verified");

        // Immediately STORE back (direction change - tests Bug 2 fix)
        @(posedge clk); #1;
        dma_start_transfer(1, 32'h0000_0080, 32'h0000_3000, 16'd2, 16'd1, 16'd8, 16'd8);
        wait_dma_done;

        expected = 32'hA000_0000 + 64;
        if (main_mem[3072] !== expected) begin
            $display("FAIL: b2b STORE main_mem[3072] = %h, expected %h", main_mem[3072], expected);
            errors = errors + 1;
        end else $display("PASS: b2b STORE main_mem[3072] verified (direction change OK)");

        @(posedge clk); @(posedge clk);
        if (errors == 0) $display("\n*** ALL DMA_ENGINE TESTS PASSED ***\n");
        else $display("\n*** %0d TESTS FAILED ***\n", errors);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500000;
        $display("TIMEOUT: DMA test did not complete in time");
        $finish;
    end

endmodule
