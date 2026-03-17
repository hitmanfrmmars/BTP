// Testbench for tiling_engine
// Enhanced: verifies DMA addresses, swap_banks timing, scratchpad base addresses,
// operation counts, and single-tile operation counts.
`timescale 1ns/1ps

module tb_tiling_engine;
    parameter ADDR_WIDTH = 32;
    parameter TILE_SIZE  = 4;

    reg clk, rst;
    reg start, mode;
    reg [15:0] dim_m, dim_k, dim_n;
    reg [ADDR_WIDTH-1:0] src_a, src_b, dst_c;
    reg [15:0] stride_a, stride_b, stride_c;
    wire done, busy;

    // DMA interface
    wire dma_start, dma_direction;
    wire [ADDR_WIDTH-1:0] dma_src_addr, dma_dst_addr;
    wire [15:0] dma_x_count, dma_y_count, dma_src_stride, dma_dst_stride;
    reg dma_done;

    // Matmul interface
    wire matmul_start, matmul_mode;
    wire [9:0] matmul_a_base, matmul_b_base, matmul_c_base;
    wire matmul_accumulate;
    wire [2:0] matmul_eff_rows, matmul_eff_k;
    reg matmul_done;

    wire swap_banks;

    integer errors = 0;
    integer dma_ops;
    integer matmul_ops;
    integer swap_count;
    integer dma_load_count;
    integer dma_store_count;

    // Capture DMA and matmul operation details
    reg [ADDR_WIDTH-1:0] last_dma_src, last_dma_dst;
    reg        last_dma_dir;
    reg [9:0]  last_matmul_a_base, last_matmul_b_base, last_matmul_c_base;

    wire [9:0] matmul_spad_stride;

    tiling_engine #(
        .TILE_SIZE(TILE_SIZE),
        .MACRO_TILE_SIZE(TILE_SIZE),
        .ARRAY_SIZE(TILE_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .start(start), .mode(mode),
        .dim_m(dim_m), .dim_k(dim_k), .dim_n(dim_n),
        .src_a(src_a), .src_b(src_b), .dst_c(dst_c),
        .stride_a(stride_a), .stride_b(stride_b), .stride_c(stride_c),
        .done(done), .busy(busy),
        .dma_start(dma_start), .dma_direction(dma_direction),
        .dma_src_addr(dma_src_addr), .dma_dst_addr(dma_dst_addr),
        .dma_x_count(dma_x_count), .dma_y_count(dma_y_count),
        .dma_src_stride(dma_src_stride), .dma_dst_stride(dma_dst_stride),
        .dma_burst_len(),
        .dma_done(dma_done),
        .matmul_start(matmul_start), .matmul_mode(matmul_mode),
        .matmul_a_base(matmul_a_base), .matmul_b_base(matmul_b_base),
        .matmul_c_base(matmul_c_base), .matmul_accumulate(matmul_accumulate),
        .matmul_eff_rows(matmul_eff_rows), .matmul_eff_k(matmul_eff_k),
        .matmul_spad_stride(matmul_spad_stride),
        .matmul_done(matmul_done),
        .swap_banks(swap_banks)
    );

    always #5 clk = ~clk;

    // Track DMA operations
    always @(posedge clk) begin
        if (dma_start) begin
            dma_ops <= dma_ops + 1;
            last_dma_src <= dma_src_addr;
            last_dma_dst <= dma_dst_addr;
            last_dma_dir <= dma_direction;
            if (dma_direction == 0) dma_load_count <= dma_load_count + 1;
            else dma_store_count <= dma_store_count + 1;
            $display("  DMA op #%0d: dir=%0b src=%h dst=%h x=%0d y=%0d sstride=%0d dstride=%0d",
                     dma_ops+1, dma_direction, dma_src_addr, dma_dst_addr,
                     dma_x_count, dma_y_count, dma_src_stride, dma_dst_stride);
        end
    end

    // Track swap_banks pulses
    always @(posedge clk) begin
        if (swap_banks)
            swap_count <= swap_count + 1;
    end

    // DMA auto-done after 5 cycles
    reg [3:0] dma_timer;
    always @(posedge clk) begin
        if (rst) begin
            dma_done <= 0; dma_timer <= 0;
        end else if (dma_start) begin
            dma_timer <= 4'd5;
            dma_done <= 0;
        end else if (dma_timer > 0) begin
            dma_timer <= dma_timer - 1;
            if (dma_timer == 1) dma_done <= 1;
            else dma_done <= 0;
        end else begin
            dma_done <= 0;
        end
    end

    // Track matmul operations
    always @(posedge clk) begin
        if (matmul_start) begin
            matmul_ops <= matmul_ops + 1;
            last_matmul_a_base <= matmul_a_base;
            last_matmul_b_base <= matmul_b_base;
            last_matmul_c_base <= matmul_c_base;
            $display("  MATMUL op #%0d: a_base=%h b_base=%h c_base=%h",
                     matmul_ops+1, matmul_a_base, matmul_b_base, matmul_c_base);
        end
    end

    // Matmul auto-done after 3 cycles
    reg [3:0] matmul_timer;
    always @(posedge clk) begin
        if (rst) begin
            matmul_done <= 0; matmul_timer <= 0;
        end else if (matmul_start) begin
            matmul_timer <= 4'd3;
            matmul_done <= 0;
        end else if (matmul_timer > 0) begin
            matmul_timer <= matmul_timer - 1;
            if (matmul_timer == 1) matmul_done <= 1;
            else matmul_done <= 0;
        end else begin
            matmul_done <= 0;
        end
    end

    initial begin
        $dumpfile("tb_tiling_engine.vcd");
        $dumpvars(0, tb_tiling_engine);

        clk = 0; rst = 1; start = 0; mode = 0;
        dim_m = 0; dim_k = 0; dim_n = 0;
        src_a = 0; src_b = 0; dst_c = 0;
        stride_a = 0; stride_b = 0; stride_c = 0;

        @(posedge clk); @(posedge clk); rst = 0;

        // ============================================================
        // Test 1: Single 4x4 tile
        // Expect: 2 DMA loads (A, B), 1 matmul, 1 DMA store = total 3 DMA, 1 matmul
        // ============================================================
        $display("\n=== Test 1: Single 4x4 tile ===");
        @(posedge clk);
        dim_m = 16'd4; dim_k = 16'd4; dim_n = 16'd4;
        src_a = 32'h0000_1000; src_b = 32'h0000_2000; dst_c = 32'h0000_3000;
        stride_a = 16'd16; stride_b = 16'd16; stride_c = 16'd16;
        mode = 0;
        dma_ops = 0; matmul_ops = 0; swap_count = 0;
        dma_load_count = 0; dma_store_count = 0;
        start = 1;
        @(posedge clk); start = 0;

        wait(done);
        @(posedge clk);
        $display("  DMA ops: %0d (loads=%0d, stores=%0d), Matmul ops: %0d, Swaps: %0d",
                 dma_ops, dma_load_count, dma_store_count, matmul_ops, swap_count);

        if (matmul_ops != 1) begin
            $display("FAIL: Expected 1 matmul op, got %0d", matmul_ops);
            errors = errors + 1;
        end else $display("PASS: Single tile: 1 matmul op");

        if (dma_load_count != 2) begin
            $display("FAIL: Expected 2 DMA loads (A+B), got %0d", dma_load_count);
            errors = errors + 1;
        end else $display("PASS: Single tile: 2 DMA loads");

        if (dma_store_count != 1) begin
            $display("FAIL: Expected 1 DMA store (C), got %0d", dma_store_count);
            errors = errors + 1;
        end else $display("PASS: Single tile: 1 DMA store");

        // Verify matmul base addresses
        if (last_matmul_a_base !== 10'h000) begin
            $display("FAIL: matmul_a_base = %h, expected 000", last_matmul_a_base);
            errors = errors + 1;
        end else $display("PASS: matmul_a_base = 0x000");

        if (last_matmul_b_base !== 10'h010) begin
            $display("FAIL: matmul_b_base = %h, expected 010", last_matmul_b_base);
            errors = errors + 1;
        end else $display("PASS: matmul_b_base = 0x010");

        if (last_matmul_c_base !== 10'h020) begin
            $display("FAIL: matmul_c_base = %h, expected 020", last_matmul_c_base);
            errors = errors + 1;
        end else $display("PASS: matmul_c_base = 0x020");

        // ============================================================
        // Test 2: 8x8 matrix (2x2 output tiles, 2 K-tiles each)
        // ============================================================
        $display("\n=== Test 2: 8x8 matrix (4 output tiles, 2 K-passes each) ===");
        @(posedge clk); @(posedge clk);
        dim_m = 16'd8; dim_k = 16'd8; dim_n = 16'd8;
        src_a = 32'h0000_1000; src_b = 32'h0000_2000; dst_c = 32'h0000_3000;
        stride_a = 16'd32; stride_b = 16'd32; stride_c = 16'd32;
        dma_ops = 0; matmul_ops = 0; swap_count = 0;
        dma_load_count = 0; dma_store_count = 0;
        start = 1;
        @(posedge clk); start = 0;

        wait(done);
        @(posedge clk);
        $display("  DMA ops: %0d (loads=%0d, stores=%0d), Matmul ops: %0d, Swaps: %0d",
                 dma_ops, dma_load_count, dma_store_count, matmul_ops, swap_count);

        // 2x2 output tiles * 2 K-tiles = 8 matmul ops
        if (matmul_ops != 8) begin
            $display("FAIL: Expected 8 matmul ops for 8x8, got %0d", matmul_ops);
            errors = errors + 1;
        end else $display("PASS: 8x8 tiling: 8 matmul ops");

        // 4 output tiles * 1 store each = 4 stores
        if (dma_store_count != 4) begin
            $display("FAIL: Expected 4 DMA stores for 8x8, got %0d", dma_store_count);
            errors = errors + 1;
        end else $display("PASS: 8x8 tiling: 4 DMA stores");

        // Swaps should occur between tiles
        if (swap_count < 1) begin
            $display("FAIL: Expected swap_banks pulses, got %0d", swap_count);
            errors = errors + 1;
        end else $display("PASS: 8x8 tiling: %0d swap_banks pulses", swap_count);

        // ============================================================
        // Test 3: Non-aligned 5x5 matrix (ceil(5/4)=2 in each dim)
        // ============================================================
        $display("\n=== Test 3: 5x5 matrix (non-aligned) ===");
        @(posedge clk); @(posedge clk);
        dim_m = 16'd5; dim_k = 16'd5; dim_n = 16'd5;
        src_a = 32'h0000_1000; src_b = 32'h0000_2000; dst_c = 32'h0000_3000;
        stride_a = 16'd20; stride_b = 16'd20; stride_c = 16'd20;
        dma_ops = 0; matmul_ops = 0; swap_count = 0;
        dma_load_count = 0; dma_store_count = 0;
        start = 1;
        @(posedge clk); start = 0;

        wait(done);
        @(posedge clk);
        $display("  DMA ops: %0d (loads=%0d, stores=%0d), Matmul ops: %0d, Swaps: %0d",
                 dma_ops, dma_load_count, dma_store_count, matmul_ops, swap_count);

        // ceil(5/4) = 2 tiles in each dim -> 2*2*2 = 8 matmul ops
        if (matmul_ops != 8) begin
            $display("FAIL: Expected 8 matmul ops for 5x5, got %0d", matmul_ops);
            errors = errors + 1;
        end else $display("PASS: 5x5 tiling: 8 matmul ops");

        if (dma_store_count != 4) begin
            $display("FAIL: Expected 4 DMA stores for 5x5, got %0d", dma_store_count);
            errors = errors + 1;
        end else $display("PASS: 5x5 tiling: 4 DMA stores");

        // ============================================================
        // Test 4: Verify DMA source addresses for first tile of 8x8
        // A tile(0,0): src = 0x1000 + 0*32*4 + 0*4 = 0x1000
        // B tile(0,0): src = 0x2000 + 0*32*4 + 0*4 = 0x2000
        // ============================================================
        $display("\n=== Test 4: DMA address verification (single tile 4x4) ===");
        @(posedge clk); @(posedge clk);
        dim_m = 16'd4; dim_k = 16'd4; dim_n = 16'd4;
        src_a = 32'h0000_4000; src_b = 32'h0000_5000; dst_c = 32'h0000_6000;
        stride_a = 16'd16; stride_b = 16'd16; stride_c = 16'd16;
        dma_ops = 0; matmul_ops = 0; swap_count = 0;
        dma_load_count = 0; dma_store_count = 0;
        start = 1;
        @(posedge clk); start = 0;

        wait(done);
        @(posedge clk);

        // The last DMA store should target dst_c = 0x6000
        if (last_dma_dst !== 32'h0000_6000) begin
            $display("FAIL: C tile DMA dst = %h, expected 0x6000", last_dma_dst);
            errors = errors + 1;
        end else $display("PASS: C tile DMA stores to 0x6000");

        @(posedge clk); @(posedge clk);
        if (errors == 0) $display("\n*** ALL TILING_ENGINE TESTS PASSED ***\n");
        else $display("\n*** %0d TESTS FAILED ***\n", errors);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #200000;
        $display("TIMEOUT: Tiling engine test did not complete");
        $finish;
    end

endmodule
