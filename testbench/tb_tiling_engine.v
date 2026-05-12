// Testbench for tiling_engine (8x8 tile size)
`timescale 1ns/1ps

module tb_tiling_engine;
    parameter ADDR_WIDTH = 32;
    parameter TILE_SIZE  = 8;

    reg clk, rst;
    reg start, mode;
    reg [15:0] dim_m, dim_k, dim_n;
    reg [ADDR_WIDTH-1:0] src_a, src_b, dst_c;
    reg [15:0] stride_a, stride_b, stride_c;
    wire done, busy;

    wire dma_start, dma_direction;
    wire [ADDR_WIDTH-1:0] dma_src_addr, dma_dst_addr;
    wire [15:0] dma_x_count, dma_y_count, dma_src_stride, dma_dst_stride;
    reg dma_done;

    wire matmul_start, matmul_mode;
    wire [9:0] matmul_a_base, matmul_b_base, matmul_c_base;
    wire matmul_accumulate;
    wire [3:0] matmul_eff_rows, matmul_eff_k;
    wire [9:0] matmul_spad_stride;
    reg matmul_done;

    wire swap_banks;

    integer errors = 0;
    integer dma_ops, matmul_ops, swap_count;
    integer dma_load_count, dma_store_count;

    reg [ADDR_WIDTH-1:0] last_dma_src, last_dma_dst;
    reg last_dma_dir;
    reg [9:0] last_matmul_a_base, last_matmul_b_base, last_matmul_c_base;

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

    always @(posedge clk) begin
        if (dma_start) begin
            dma_ops <= dma_ops + 1;
            last_dma_src <= dma_src_addr;
            last_dma_dst <= dma_dst_addr;
            last_dma_dir <= dma_direction;
            if (dma_direction == 0) dma_load_count <= dma_load_count + 1;
            else dma_store_count <= dma_store_count + 1;
            $display("  DMA #%0d: dir=%0b src=%h dst=%h x=%0d y=%0d",
                     dma_ops+1, dma_direction, dma_src_addr, dma_dst_addr,
                     dma_x_count, dma_y_count);
        end
    end

    always @(posedge clk)
        if (swap_banks) swap_count <= swap_count + 1;

    reg [3:0] dma_timer;
    always @(posedge clk) begin
        if (rst) begin dma_done <= 0; dma_timer <= 0; end
        else if (dma_start) begin dma_timer <= 4'd5; dma_done <= 0; end
        else if (dma_timer > 0) begin
            dma_timer <= dma_timer - 1;
            dma_done <= (dma_timer == 1);
        end else dma_done <= 0;
    end

    always @(posedge clk) begin
        if (matmul_start) begin
            matmul_ops <= matmul_ops + 1;
            last_matmul_a_base <= matmul_a_base;
            last_matmul_b_base <= matmul_b_base;
            last_matmul_c_base <= matmul_c_base;
            $display("  MATMUL #%0d: a=%h b=%h c=%h eff_rows=%0d eff_k=%0d accum=%b",
                     matmul_ops+1, matmul_a_base, matmul_b_base, matmul_c_base,
                     matmul_eff_rows, matmul_eff_k, matmul_accumulate);
        end
    end

    reg [3:0] matmul_timer;
    always @(posedge clk) begin
        if (rst) begin matmul_done <= 0; matmul_timer <= 0; end
        else if (matmul_start) begin matmul_timer <= 4'd3; matmul_done <= 0; end
        else if (matmul_timer > 0) begin
            matmul_timer <= matmul_timer - 1;
            matmul_done <= (matmul_timer == 1);
        end else matmul_done <= 0;
    end

    task reset_counters;
        begin
            dma_ops = 0; matmul_ops = 0; swap_count = 0;
            dma_load_count = 0; dma_store_count = 0;
        end
    endtask

    initial begin
        $dumpfile("tb_tiling_engine.vcd");
        $dumpvars(0, tb_tiling_engine);

        clk = 0; rst = 1; start = 0; mode = 0;
        dim_m = 0; dim_k = 0; dim_n = 0;
        src_a = 0; src_b = 0; dst_c = 0;
        stride_a = 0; stride_b = 0; stride_c = 0;

        repeat(3) @(posedge clk);
        @(negedge clk); rst = 0;

        // ============================================================
        // Test 1: Single 8x8 tile
        // 2 DMA loads (A, B), 1 matmul, 1 DMA store
        // ============================================================
        $display("\n=== Test 1: Single 8x8 tile ===");
        @(negedge clk);
        dim_m = 16'd8; dim_k = 16'd8; dim_n = 16'd8;
        src_a = 32'h1000; src_b = 32'h2000; dst_c = 32'h3000;
        stride_a = 16'd8; stride_b = 16'd8; stride_c = 16'd8;
        mode = 0;
        reset_counters;
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        wait(done); @(posedge clk);

        $display("  DMA: %0d (L=%0d S=%0d) Matmul: %0d Swaps: %0d",
                 dma_ops, dma_load_count, dma_store_count, matmul_ops, swap_count);

        if (matmul_ops != 1) begin
            $display("FAIL: Expected 1 matmul, got %0d", matmul_ops);
            errors = errors + 1;
        end else $display("PASS: 1 matmul op");

        if (dma_load_count != 2) begin
            $display("FAIL: Expected 2 DMA loads, got %0d", dma_load_count);
            errors = errors + 1;
        end else $display("PASS: 2 DMA loads");

        if (dma_store_count != 1) begin
            $display("FAIL: Expected 1 DMA store, got %0d", dma_store_count);
            errors = errors + 1;
        end else $display("PASS: 1 DMA store");

        // Verify spad base addresses (region_bytes = 8*8 = 64)
        if (last_matmul_a_base !== 10'h000) begin
            $display("FAIL: a_base=%h expected 000", last_matmul_a_base);
            errors = errors + 1;
        end else $display("PASS: a_base = 0x000");

        if (last_matmul_b_base !== 10'h040) begin
            $display("FAIL: b_base=%h expected 040", last_matmul_b_base);
            errors = errors + 1;
        end else $display("PASS: b_base = 0x040");

        if (last_matmul_c_base !== 10'h080) begin
            $display("FAIL: c_base=%h expected 080", last_matmul_c_base);
            errors = errors + 1;
        end else $display("PASS: c_base = 0x080");

        // ============================================================
        // Test 2: 16x16 matrix (2x2 output tiles, 2 K-tiles each)
        // 4 output tiles * 2 K-passes = 8 matmul ops, 4 C stores
        // ============================================================
        $display("\n=== Test 2: 16x16 matrix (4 output tiles, 2 K-passes) ===");
        @(negedge clk); @(negedge clk);
        dim_m = 16'd16; dim_k = 16'd16; dim_n = 16'd16;
        src_a = 32'h1000; src_b = 32'h2000; dst_c = 32'h3000;
        stride_a = 16'd16; stride_b = 16'd16; stride_c = 16'd16;
        reset_counters;
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        wait(done); @(posedge clk);

        $display("  DMA: %0d (L=%0d S=%0d) Matmul: %0d Swaps: %0d",
                 dma_ops, dma_load_count, dma_store_count, matmul_ops, swap_count);

        if (matmul_ops != 8) begin
            $display("FAIL: Expected 8 matmul ops, got %0d", matmul_ops);
            errors = errors + 1;
        end else $display("PASS: 8 matmul ops");

        if (dma_store_count != 4) begin
            $display("FAIL: Expected 4 DMA stores, got %0d", dma_store_count);
            errors = errors + 1;
        end else $display("PASS: 4 DMA stores");

        // ============================================================
        // Test 3: 5x5 non-aligned (fits in single 8x8 tile)
        // ============================================================
        $display("\n=== Test 3: 5x5 (single tile, non-aligned) ===");
        @(negedge clk); @(negedge clk);
        dim_m = 16'd5; dim_k = 16'd5; dim_n = 16'd5;
        src_a = 32'h1000; src_b = 32'h2000; dst_c = 32'h3000;
        stride_a = 16'd5; stride_b = 16'd5; stride_c = 16'd5;
        reset_counters;
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        wait(done); @(posedge clk);

        $display("  DMA: %0d (L=%0d S=%0d) Matmul: %0d",
                 dma_ops, dma_load_count, dma_store_count, matmul_ops);

        if (matmul_ops != 1) begin
            $display("FAIL: Expected 1 matmul for 5x5, got %0d", matmul_ops);
            errors = errors + 1;
        end else $display("PASS: 5x5 => 1 matmul op");

        // ============================================================
        // Test 4: 9x9 non-aligned (2x2 output tiles, 2 K-passes = 8 matmul)
        // ============================================================
        $display("\n=== Test 4: 9x9 non-aligned ===");
        @(negedge clk); @(negedge clk);
        dim_m = 16'd9; dim_k = 16'd9; dim_n = 16'd9;
        src_a = 32'h1000; src_b = 32'h2000; dst_c = 32'h3000;
        stride_a = 16'd9; stride_b = 16'd9; stride_c = 16'd9;
        reset_counters;
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        wait(done); @(posedge clk);

        $display("  DMA: %0d (L=%0d S=%0d) Matmul: %0d",
                 dma_ops, dma_load_count, dma_store_count, matmul_ops);

        if (matmul_ops != 8) begin
            $display("FAIL: Expected 8 matmul for 9x9, got %0d", matmul_ops);
            errors = errors + 1;
        end else $display("PASS: 9x9 => 8 matmul ops");

        @(posedge clk); @(posedge clk);
        if (errors == 0) $display("\n*** ALL TILING_ENGINE TESTS PASSED ***\n");
        else $display("\n*** %0d TESTS FAILED ***\n", errors);
        $finish;
    end

    initial begin
        #5000000;
        $display("TIMEOUT: Tiling engine test did not complete");
        $finish;
    end

endmodule
