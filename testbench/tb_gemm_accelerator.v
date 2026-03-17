// Comprehensive end-to-end testbench for gemm_accelerator_top
// Tests: dense GEMM, multi-tile 8x8, back-to-back, zero matrix,
//        overflow/truncation, IRQ, non-square matrices
`timescale 1ns/1ps

module tb_gemm_accelerator;
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter ARRAY_SIZE = 4;
    parameter ACC_WIDTH  = 48;

    reg clk, rst;

    // AXI-Lite
    reg [5:0]  axi_wr_addr;
    reg [31:0] axi_wr_data;
    reg        axi_wr_en;
    reg [5:0]  axi_rd_addr;
    wire [31:0] axi_rd_data;
    reg        axi_rd_en;

    // PCPI interface (unused in this testbench -- AXI-Lite path tested here)
    reg         pcpi_valid;
    reg  [31:0] pcpi_insn, pcpi_rs1, pcpi_rs2;
    wire        pcpi_wr, pcpi_wait, pcpi_ready;
    wire [31:0] pcpi_rd;

    // Memory interface
    wire [ADDR_WIDTH-1:0] mem_addr;
    wire mem_read, mem_write;
    wire [DATA_WIDTH-1:0] mem_wdata;
    wire [3:0] mem_burst_len;
    reg [DATA_WIDTH-1:0] mem_rdata;
    reg mem_ready;

    wire irq, accel_busy, accel_done;

    integer errors = 0;
    integer total_errors = 0;
    integer i, r, c;
    integer test_num;

    // Simulated main memory (64KB = 16384 words)
    reg [31:0] main_mem [0:16383];

    gemm_accelerator_top #(
        .ARRAY_SIZE(ARRAY_SIZE), .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .axi_wr_addr(axi_wr_addr), .axi_wr_data(axi_wr_data), .axi_wr_en(axi_wr_en),
        .axi_rd_addr(axi_rd_addr), .axi_rd_data(axi_rd_data), .axi_rd_en(axi_rd_en),
        .pcpi_valid(pcpi_valid), .pcpi_insn(pcpi_insn),
        .pcpi_rs1(pcpi_rs1), .pcpi_rs2(pcpi_rs2),
        .pcpi_wr(pcpi_wr), .pcpi_rd(pcpi_rd),
        .pcpi_wait(pcpi_wait), .pcpi_ready(pcpi_ready),
        .mem_addr(mem_addr), .mem_read(mem_read), .mem_write(mem_write),
        .mem_wdata(mem_wdata), .mem_burst_len(mem_burst_len),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .irq(irq), .accel_busy(accel_busy), .accel_done(accel_done)
    );

    always #5 clk = ~clk;

    // Burst-aware memory model: responds with burst_len+1 consecutive ready pulses
    reg [3:0]  mem_burst_cnt;
    reg [31:0] mem_burst_addr;
    reg        mem_in_read_burst;
    reg        mem_in_write_burst;

    always @(posedge clk) begin
        if (rst) begin
            mem_ready         <= 1'b0;
            mem_rdata         <= 32'd0;
            mem_burst_cnt     <= 4'd0;
            mem_burst_addr    <= 32'd0;
            mem_in_read_burst <= 1'b0;
            mem_in_write_burst<= 1'b0;
        end else if (mem_in_read_burst) begin
            if (mem_burst_cnt == 4'd0) begin
                mem_in_read_burst <= 1'b0;
                mem_ready         <= 1'b0;
            end else begin
                mem_rdata      <= main_mem[mem_burst_addr[15:2]];
                mem_ready      <= 1'b1;
                mem_burst_cnt  <= mem_burst_cnt - 4'd1;
                mem_burst_addr <= mem_burst_addr + 32'd4;
            end
        end else if (mem_read) begin
            mem_rdata      <= main_mem[mem_addr[15:2]];
            mem_ready      <= 1'b1;
            mem_burst_addr <= mem_addr + 32'd4;
            mem_burst_cnt  <= mem_burst_len;
            mem_in_read_burst <= (mem_burst_len > 4'd0);
        end else if (mem_write) begin
            main_mem[mem_addr[15:2]] <= mem_wdata;
            mem_ready <= 1'b1;
        end else begin
            mem_ready <= 1'b0;
        end
    end

    // Track IRQ pulses
    integer irq_count;
    always @(posedge clk) begin
        if (rst) irq_count <= 0;
        else if (irq) irq_count <= irq_count + 1;
    end

    // ========== Helper tasks ==========

    task reg_write(input [5:0] addr, input [31:0] data);
        begin
            @(posedge clk); #1;
            axi_wr_addr = addr;
            axi_wr_data = data;
            axi_wr_en   = 1;
            @(posedge clk); #1;
            axi_wr_en = 0;
        end
    endtask

    task reg_read(input [5:0] addr, output [31:0] data);
        begin
            @(posedge clk); #1;
            axi_rd_addr = addr;
            axi_rd_en   = 1;
            @(posedge clk); #1;
            axi_rd_en = 0;
            data = axi_rd_data;
        end
    endtask

    task configure_gemm(
        input [15:0] m, input [15:0] k, input [15:0] n,
        input [31:0] sa, input [31:0] sb, input [31:0] sc,
        input [15:0] stra, input [15:0] strb, input [15:0] strc,
        input        irq_en
    );
        begin
            reg_write(6'h08, {m, k});
            reg_write(6'h0C, {16'd0, n});
            reg_write(6'h10, sa);
            reg_write(6'h14, sb);
            reg_write(6'h18, sc);
            reg_write(6'h1C, {16'd0, stra});
            reg_write(6'h20, {16'd0, strb});
            reg_write(6'h24, {16'd0, strc});
        end
    endtask

    task start_gemm(input irq_en, input mode_bit);
        begin
            reg_write(6'h00, {29'd0, irq_en, mode_bit, 1'b1});
        end
    endtask

    task wait_done(input integer max_cycles, output integer ok);
        begin : wait_blk
            integer cyc;
            ok = 0;
            for (cyc = 0; cyc < max_cycles; cyc = cyc + 1) begin
                @(posedge clk);
                if (accel_done) begin
                    ok = 1;
                    disable wait_blk;
                end
            end
        end
    endtask

    task clear_mem;
        begin
            for (i = 0; i < 16384; i = i + 1)
                main_mem[i] = 32'd0;
        end
    endtask

    task check_byte(
        input [13:0] word_addr, input [1:0] byte_sel,
        input [7:0] expected, input [79:0] label
    );
        reg [31:0] w;
        reg [7:0] actual;
        begin
            w = main_mem[word_addr];
            case (byte_sel)
                2'd0: actual = w[7:0];
                2'd1: actual = w[15:8];
                2'd2: actual = w[23:16];
                2'd3: actual = w[31:24];
            endcase
            if (actual !== expected) begin
                $display("  FAIL %0s: got %0d, expected %0d (word=%h)", label, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    // Verify full NxN C matrix at base_addr with given stride (bytes)
    task verify_c_matrix(
        input [31:0] base_addr, input [15:0] stride, input [15:0] rows, input [15:0] cols,
        input [7:0] golden_flat_0,  input [7:0] golden_flat_1,  input [7:0] golden_flat_2,  input [7:0] golden_flat_3,
        input [7:0] golden_flat_4,  input [7:0] golden_flat_5,  input [7:0] golden_flat_6,  input [7:0] golden_flat_7,
        input [7:0] golden_flat_8,  input [7:0] golden_flat_9,  input [7:0] golden_flat_10, input [7:0] golden_flat_11,
        input [7:0] golden_flat_12, input [7:0] golden_flat_13, input [7:0] golden_flat_14, input [7:0] golden_flat_15
    );
        reg [7:0] golden [0:15];
        reg [31:0] row_addr;
        reg [31:0] c_word;
        reg [7:0] actual;
        integer ri, ci;
        begin
            golden[0]=golden_flat_0; golden[1]=golden_flat_1; golden[2]=golden_flat_2; golden[3]=golden_flat_3;
            golden[4]=golden_flat_4; golden[5]=golden_flat_5; golden[6]=golden_flat_6; golden[7]=golden_flat_7;
            golden[8]=golden_flat_8; golden[9]=golden_flat_9; golden[10]=golden_flat_10; golden[11]=golden_flat_11;
            golden[12]=golden_flat_12; golden[13]=golden_flat_13; golden[14]=golden_flat_14; golden[15]=golden_flat_15;
            for (ri = 0; ri < rows && ri < 4; ri = ri + 1) begin
                row_addr = base_addr + ri * stride;
                c_word = main_mem[row_addr[15:2]];
                for (ci = 0; ci < cols && ci < 4; ci = ci + 1) begin
                    case (ci)
                        0: actual = c_word[7:0];
                        1: actual = c_word[15:8];
                        2: actual = c_word[23:16];
                        3: actual = c_word[31:24];
                    endcase
                    if (actual !== golden[ri*4 + ci]) begin
                        $display("  FAIL: C[%0d][%0d] = %0d, expected %0d", ri, ci, actual, golden[ri*4+ci]);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    reg [31:0] status;
    integer ok;

    initial begin
        $dumpfile("tb_gemm_accelerator.vcd");
        $dumpvars(0, tb_gemm_accelerator);

        clk = 0; rst = 1;
        axi_wr_addr = 0; axi_wr_data = 0; axi_wr_en = 0;
        axi_rd_addr = 0; axi_rd_en = 0;
        pcpi_valid = 0; pcpi_insn = 0; pcpi_rs1 = 0; pcpi_rs2 = 0;
        mem_rdata = 0; mem_ready = 0;

        clear_mem;
        @(posedge clk); @(posedge clk); #1; rst = 0;
        @(posedge clk); @(posedge clk); #1;

        // ============================================================
        // TEST 1: Dense general 4x4 GEMM
        // A = [[2,1,3,1],[1,3,2,1],[3,2,1,3],[2,1,1,2]]
        // B = [[1,2,1,3],[3,1,2,1],[2,3,1,2],[1,1,3,1]]
        // C = [[12,15,10,14],[15,12,12,11],[14,14,17,16],[9,10,11,11]]
        // ============================================================
        test_num = 1;
        errors = 0;
        $display("\n=== TEST %0d: Dense 4x4 GEMM (general A*B) ===", test_num);
        clear_mem;

        // A at 0x1000 (word 0x400), stride=16
        main_mem[14'h0400] = 32'h01_03_01_02; // Row 0: [2,1,3,1]
        main_mem[14'h0404] = 32'h01_02_03_01; // Row 1: [1,3,2,1]
        main_mem[14'h0408] = 32'h03_01_02_03; // Row 2: [3,2,1,3]
        main_mem[14'h040C] = 32'h02_01_01_02; // Row 3: [2,1,1,2]

        // B at 0x2000 (word 0x800), stride=16
        main_mem[14'h0800] = 32'h03_01_02_01; // Row 0: [1,2,1,3]
        main_mem[14'h0804] = 32'h01_02_01_03; // Row 1: [3,1,2,1]
        main_mem[14'h0808] = 32'h02_01_03_02; // Row 2: [2,3,1,2]
        main_mem[14'h080C] = 32'h01_03_01_01; // Row 3: [1,1,3,1]

        // C at 0x3000 (word 0xC00)
        configure_gemm(16'd4, 16'd4, 16'd4,
                        32'h1000, 32'h2000, 32'h3000,
                        16'd16, 16'd16, 16'd16, 1'b1);
        irq_count = 0;
        start_gemm(1'b1, 1'b0);
        wait_done(5000, ok);

        if (!ok) begin $display("  FAIL: Did not complete"); errors = errors + 1; end
        else begin
            // Golden: [[12,15,10,14],[15,12,12,11],[14,14,17,16],[9,10,11,11]]
            verify_c_matrix(32'h3000, 16'd16, 16'd4, 16'd4,
                8'd12, 8'd15, 8'd10, 8'd14,
                8'd15, 8'd12, 8'd12, 8'd11,
                8'd14, 8'd14, 8'd17, 8'd16,
                8'd9,  8'd10, 8'd11, 8'd11);
        end

        // Check done status
        reg_read(6'h04, status);
        if (status[1] !== 1'b1) begin $display("  FAIL: done bit not set"); errors = errors + 1; end

        if (errors == 0) $display("  PASS: Test %0d passed", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 2: 8x8 multi-tile GEMM (tests multi-K accumulation)
        // A = all 1s, B[i][j] = i+1
        // C[i][j] = sum_{k=0..7} 1*(k+1) = 36 for all i,j
        // ============================================================
        test_num = 2;
        errors = 0;
        $display("\n=== TEST %0d: 8x8 multi-tile GEMM (K-accumulation) ===", test_num);
        clear_mem;

        // A at 0x1000, stride=8 bytes (2 words per row), all 1s
        // 8 rows, each row = [1,1,1,1,1,1,1,1]
        for (r = 0; r < 8; r = r + 1) begin
            main_mem[14'h0400 + r*2]     = 32'h01010101;
            main_mem[14'h0400 + r*2 + 1] = 32'h01010101;
        end

        // B at 0x2000, stride=8 bytes, B[i][j] = i+1
        for (r = 0; r < 8; r = r + 1) begin
            main_mem[14'h0800 + r*2]     = {4{r[7:0]+8'd1}};
            main_mem[14'h0800 + r*2 + 1] = {4{r[7:0]+8'd1}};
        end

        // C at 0x3000, stride=8 bytes
        configure_gemm(16'd8, 16'd8, 16'd8,
                        32'h1000, 32'h2000, 32'h3000,
                        16'd8, 16'd8, 16'd8, 1'b1);
        start_gemm(1'b1, 1'b0);
        wait_done(20000, ok);

        if (!ok) begin $display("  FAIL: Did not complete"); errors = errors + 1; end
        else begin
            // All C values should be 36 (0x24)
            for (r = 0; r < 8; r = r + 1) begin
                for (c = 0; c < 2; c = c + 1) begin
                    status = main_mem[14'h0C00 + r*2 + c];
                    if (status !== 32'h24242424) begin
                        $display("  FAIL: C row %0d word %0d = %h, expected 24242424", r, c, status);
                        errors = errors + 1;
                    end
                end
            end
        end

        if (errors == 0) $display("  PASS: Test %0d passed (all 64 elements = 36)", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 3: Back-to-back GEMM without reset
        // First: identity * B = B. Second: different A * B.
        // ============================================================
        test_num = 3;
        errors = 0;
        $display("\n=== TEST %0d: Back-to-back GEMM operations ===", test_num);
        clear_mem;

        // --- First: Identity * B ---
        main_mem[14'h0400] = 32'h00_00_00_01;
        main_mem[14'h0404] = 32'h00_00_01_00;
        main_mem[14'h0408] = 32'h00_01_00_00;
        main_mem[14'h040C] = 32'h01_00_00_00;

        main_mem[14'h0800] = 32'h04_03_02_01;
        main_mem[14'h0804] = 32'h08_07_06_05;
        main_mem[14'h0808] = 32'h0C_0B_0A_09;
        main_mem[14'h080C] = 32'h10_0F_0E_0D;

        configure_gemm(16'd4, 16'd4, 16'd4,
                        32'h1000, 32'h2000, 32'h3000,
                        16'd16, 16'd16, 16'd16, 1'b0);
        start_gemm(1'b0, 1'b0);
        wait_done(5000, ok);

        if (!ok) begin $display("  FAIL: First GEMM timeout"); errors = errors + 1; end
        else begin
            verify_c_matrix(32'h3000, 16'd16, 16'd4, 16'd4,
                8'd1, 8'd2, 8'd3, 8'd4,
                8'd5, 8'd6, 8'd7, 8'd8,
                8'd9, 8'd10, 8'd11, 8'd12,
                8'd13, 8'd14, 8'd15, 8'd16);
            if (errors == 0) $display("  PASS: First GEMM (I*B=B) correct");
        end

        // --- Second: A=[[2,0,0,0],[0,2,0,0],[0,0,2,0],[0,0,0,2]] * B = 2*B ---
        @(posedge clk); @(posedge clk); #1;
        main_mem[14'h0400] = 32'h00_00_00_02;
        main_mem[14'h0404] = 32'h00_00_02_00;
        main_mem[14'h0408] = 32'h00_02_00_00;
        main_mem[14'h040C] = 32'h02_00_00_00;

        configure_gemm(16'd4, 16'd4, 16'd4,
                        32'h1000, 32'h2000, 32'h4000,
                        16'd16, 16'd16, 16'd16, 1'b0);
        start_gemm(1'b0, 1'b0);
        wait_done(5000, ok);

        if (!ok) begin $display("  FAIL: Second GEMM timeout"); errors = errors + 1; end
        else begin
            verify_c_matrix(32'h4000, 16'd16, 16'd4, 16'd4,
                8'd2, 8'd4, 8'd6, 8'd8,
                8'd10, 8'd12, 8'd14, 8'd16,
                8'd18, 8'd20, 8'd22, 8'd24,
                8'd26, 8'd28, 8'd30, 8'd32);
            if (errors == 0) $display("  PASS: Second GEMM (2I*B=2B) correct");
        end

        if (errors == 0) $display("  PASS: Test %0d passed", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 4: Zero matrix (A=0, expect C=0)
        // ============================================================
        test_num = 4;
        errors = 0;
        $display("\n=== TEST %0d: Zero matrix A ===", test_num);
        clear_mem;

        // A = all zeros (already from clear_mem)
        // B = non-zero
        main_mem[14'h0800] = 32'hFF_FF_FF_FF;
        main_mem[14'h0804] = 32'hFF_FF_FF_FF;
        main_mem[14'h0808] = 32'hFF_FF_FF_FF;
        main_mem[14'h080C] = 32'hFF_FF_FF_FF;

        // Put non-zero garbage in C area to prove it gets overwritten
        main_mem[14'h0C00] = 32'hDEADBEEF;
        main_mem[14'h0C04] = 32'hDEADBEEF;
        main_mem[14'h0C08] = 32'hDEADBEEF;
        main_mem[14'h0C0C] = 32'hDEADBEEF;

        configure_gemm(16'd4, 16'd4, 16'd4,
                        32'h1000, 32'h2000, 32'h3000,
                        16'd16, 16'd16, 16'd16, 1'b0);
        start_gemm(1'b0, 1'b0);
        wait_done(5000, ok);

        if (!ok) begin $display("  FAIL: Timeout"); errors = errors + 1; end
        else begin
            for (r = 0; r < 4; r = r + 1) begin
                status = main_mem[14'h0C00 + r*4];
                if (status !== 32'h00000000) begin
                    $display("  FAIL: C row %0d = %h, expected 0", r, status);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) $display("  PASS: Test %0d passed (0 * B = 0)", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 5: Near-overflow accumulation
        // A = all 63, B = all 1. C[i][j] = 63*1*4 = 252 (fits in uint8)
        // ============================================================
        test_num = 5;
        errors = 0;
        $display("\n=== TEST %0d: Near-overflow accumulation (252) ===", test_num);
        clear_mem;

        // A = all 63 (0x3F)
        main_mem[14'h0400] = 32'h3F3F3F3F;
        main_mem[14'h0404] = 32'h3F3F3F3F;
        main_mem[14'h0408] = 32'h3F3F3F3F;
        main_mem[14'h040C] = 32'h3F3F3F3F;

        // B = all 1
        main_mem[14'h0800] = 32'h01010101;
        main_mem[14'h0804] = 32'h01010101;
        main_mem[14'h0808] = 32'h01010101;
        main_mem[14'h080C] = 32'h01010101;

        configure_gemm(16'd4, 16'd4, 16'd4,
                        32'h1000, 32'h2000, 32'h3000,
                        16'd16, 16'd16, 16'd16, 1'b0);
        start_gemm(1'b0, 1'b0);
        wait_done(5000, ok);

        if (!ok) begin $display("  FAIL: Timeout"); errors = errors + 1; end
        else begin
            for (r = 0; r < 4; r = r + 1) begin
                status = main_mem[14'h0C00 + r*4];
                if (status !== 32'hFCFCFCFC) begin
                    $display("  FAIL: C row %0d = %h, expected FCFCFCFC (252)", r, status);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) $display("  PASS: Test %0d passed (all C = 252)", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 6: Overflow truncation (wraps to low 8 bits)
        // A = all 64, B = all 4. C[i][j] = 64*4*4 = 1024. Low byte = 0x00.
        // ============================================================
        test_num = 6;
        errors = 0;
        $display("\n=== TEST %0d: Overflow truncation (1024 -> 0x00) ===", test_num);
        clear_mem;

        main_mem[14'h0400] = 32'h40404040; // 64
        main_mem[14'h0404] = 32'h40404040;
        main_mem[14'h0408] = 32'h40404040;
        main_mem[14'h040C] = 32'h40404040;

        main_mem[14'h0800] = 32'h04040404; // 4
        main_mem[14'h0804] = 32'h04040404;
        main_mem[14'h0808] = 32'h04040404;
        main_mem[14'h080C] = 32'h04040404;

        configure_gemm(16'd4, 16'd4, 16'd4,
                        32'h1000, 32'h2000, 32'h3000,
                        16'd16, 16'd16, 16'd16, 1'b0);
        start_gemm(1'b0, 1'b0);
        wait_done(5000, ok);

        if (!ok) begin $display("  FAIL: Timeout"); errors = errors + 1; end
        else begin
            for (r = 0; r < 4; r = r + 1) begin
                status = main_mem[14'h0C00 + r*4];
                if (status !== 32'h00000000) begin
                    $display("  FAIL: C row %0d = %h, expected 00000000 (truncated)", r, status);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) $display("  PASS: Test %0d passed (overflow truncates correctly)", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 7: IRQ verification
        // Run with irq_en=1, count IRQ pulses. Then with irq_en=0, verify none.
        // ============================================================
        test_num = 7;
        errors = 0;
        $display("\n=== TEST %0d: IRQ verification ===", test_num);
        clear_mem;

        // Simple identity * identity
        main_mem[14'h0400] = 32'h00000001;
        main_mem[14'h0404] = 32'h00000100;
        main_mem[14'h0408] = 32'h00010000;
        main_mem[14'h040C] = 32'h01000000;
        main_mem[14'h0800] = 32'h00000001;
        main_mem[14'h0804] = 32'h00000100;
        main_mem[14'h0808] = 32'h00010000;
        main_mem[14'h080C] = 32'h01000000;

        // With irq_en = 1
        irq_count = 0;
        configure_gemm(16'd4, 16'd4, 16'd4,
                        32'h1000, 32'h2000, 32'h3000,
                        16'd16, 16'd16, 16'd16, 1'b1);
        start_gemm(1'b1, 1'b0);
        wait_done(5000, ok);
        @(posedge clk); @(posedge clk); @(posedge clk); #1;

        if (!ok) begin $display("  FAIL: Timeout with irq_en=1"); errors = errors + 1; end
        if (irq_count < 1) begin
            $display("  FAIL: IRQ count = %0d with irq_en=1, expected >= 1", irq_count);
            errors = errors + 1;
        end else $display("  PASS: IRQ fired %0d times with irq_en=1", irq_count);

        // With irq_en = 0
        @(posedge clk); @(posedge clk); #1;
        irq_count = 0;
        configure_gemm(16'd4, 16'd4, 16'd4,
                        32'h1000, 32'h2000, 32'h4000,
                        16'd16, 16'd16, 16'd16, 1'b0);
        start_gemm(1'b0, 1'b0);
        wait_done(5000, ok);
        @(posedge clk); @(posedge clk); @(posedge clk); #1;

        if (!ok) begin $display("  FAIL: Timeout with irq_en=0"); errors = errors + 1; end
        if (irq_count != 0) begin
            $display("  FAIL: IRQ count = %0d with irq_en=0, expected 0", irq_count);
            errors = errors + 1;
        end else $display("  PASS: No IRQ with irq_en=0");

        if (errors == 0) $display("  PASS: Test %0d passed", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 8: Non-square M=4, K=8, N=4 (single output tile, 2 K-passes)
        // A = 4x8 all 1s, B = 8x4 where B[k][j] = k+1
        // C[i][j] = sum_{k=0..7} 1*(k+1) = 36
        // ============================================================
        test_num = 8;
        errors = 0;
        $display("\n=== TEST %0d: Non-square 4x8 * 8x4 ===", test_num);
        clear_mem;

        // A at 0x1000, stride=8 (2 words per row, 8 int8 per row), all 1s
        for (r = 0; r < 4; r = r + 1) begin
            main_mem[14'h0400 + r*2]     = 32'h01010101;
            main_mem[14'h0400 + r*2 + 1] = 32'h01010101;
        end

        // B at 0x2000, stride=4 (1 word per row, 4 int8 per row), B[k] = k+1
        for (r = 0; r < 8; r = r + 1) begin
            main_mem[14'h0800 + r] = {4{r[7:0]+8'd1}};
        end

        // C at 0x3000, stride=4
        configure_gemm(16'd4, 16'd8, 16'd4,
                        32'h1000, 32'h2000, 32'h3000,
                        16'd8, 16'd4, 16'd4, 1'b0);
        start_gemm(1'b0, 1'b0);
        wait_done(10000, ok);

        if (!ok) begin $display("  FAIL: Timeout"); errors = errors + 1; end
        else begin
            for (r = 0; r < 4; r = r + 1) begin
                status = main_mem[14'h0C00 + r];
                if (status !== 32'h24242424) begin
                    $display("  FAIL: C row %0d = %h, expected 24242424 (36)", r, status);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) $display("  PASS: Test %0d passed (4x8 * 8x4 = 36)", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 9: Cycle counter verification
        // ============================================================
        test_num = 9;
        errors = 0;
        $display("\n=== TEST %0d: Cycle counter ===", test_num);

        reg_read(6'h28, status);
        $display("  Cycle count from last GEMM: %0d", status);
        if (status == 0) begin
            $display("  FAIL: Cycle count is zero");
            errors = errors + 1;
        end else $display("  PASS: Cycle count = %0d (non-zero)", status);

        if (errors == 0) $display("  PASS: Test %0d passed", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 10: int16 end-to-end (4x4 int16 GEMM)
        // A = all 1s, B rows = [100,200,300,400]
        // C[i][j] = 400, 800, 1200, 1600
        // ============================================================
        test_num = 10;
        errors = 0;
        $display("\n=== TEST %0d: int16 4x4 GEMM end-to-end ===", test_num);
        clear_mem;

        // A at 0x5000 (word addr 0x1400), stride=8 bytes, all 1s
        for (r = 0; r < 4; r = r + 1) begin
            main_mem[14'h1400 + r*2]     = 32'h00010001;
            main_mem[14'h1400 + r*2 + 1] = 32'h00010001;
        end

        // B at 0x6000 (word addr 0x1800), stride=8 bytes, rows=[100,200,300,400]
        for (r = 0; r < 4; r = r + 1) begin
            main_mem[14'h1800 + r*2]     = {16'd200, 16'd100};
            main_mem[14'h1800 + r*2 + 1] = {16'd400, 16'd300};
        end

        // C at 0x7000 (word addr 0x1C00), stride=8 bytes
        configure_gemm(16'd4, 16'd4, 16'd4,
                        32'h5000, 32'h6000, 32'h7000,
                        16'd8, 16'd8, 16'd8, 1'b0);
        start_gemm(1'b0, 1'b1);  // mode=1 (int16)
        wait_done(5000, ok);

        if (!ok) begin $display("  FAIL: Timeout"); errors = errors + 1; end
        else begin
            for (r = 0; r < 4; r = r + 1) begin
                status = main_mem[14'h1C00 + r*2];
                if (status !== 32'h03200190) begin
                    $display("  FAIL: C row %0d word 0 = %h, expected 03200190 ({800,400})", r, status);
                    errors = errors + 1;
                end
                status = main_mem[14'h1C00 + r*2 + 1];
                if (status !== 32'h064004B0) begin
                    $display("  FAIL: C row %0d word 1 = %h, expected 064004B0 ({1600,1200})", r, status);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) $display("  PASS: Test %0d passed (int16 GEMM correct)", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 11: Non-aligned 5x5 GEMM (A=all 1s, B=all 1s => C[i][j]=5)
        // Stride 8 bytes per row (5 elements + padding)
        // ============================================================
        test_num = 11;
        errors = 0;
        $display("\n=== TEST %0d: 5x5 non-aligned GEMM ===", test_num);
        clear_mem;

        for (r = 0; r < 5; r = r + 1) begin
            main_mem[14'h2000 + r*2]     = 32'h01010101;
            main_mem[14'h2000 + r*2 + 1] = 32'h00000001;
        end
        for (r = 0; r < 5; r = r + 1) begin
            main_mem[14'h2800 + r*2]     = 32'h01010101;
            main_mem[14'h2800 + r*2 + 1] = 32'h00000001;
        end

        configure_gemm(16'd5, 16'd5, 16'd5,
                        32'h8000, 32'hA000, 32'hC000,
                        16'd8, 16'd8, 16'd8, 1'b0);
        start_gemm(1'b0, 1'b0);
        wait_done(15000, ok);

        if (!ok) begin $display("  FAIL: Timeout"); errors = errors + 1; end
        else begin
            for (r = 0; r < 5; r = r + 1) begin
                status = main_mem[14'h3000 + r*2];
                if (status !== 32'h05050505) begin
                    $display("  FAIL: C row %0d word0 = %h, expected 05050505", r, status);
                    errors = errors + 1;
                end
                status = main_mem[14'h3000 + r*2 + 1];
                if (status[7:0] !== 8'd5) begin
                    $display("  FAIL: C row %0d word1 low byte = %0d, expected 5", r, status[7:0]);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) $display("  PASS: Test %0d passed (5x5 => all 5)", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 12: 7x3 * 3x5 (A=all 1s, B=all 1s => C[i][j]=3)
        // stride_a=4, stride_b=8, stride_c=8
        // ============================================================
        test_num = 12;
        errors = 0;
        $display("\n=== TEST %0d: 7x3 * 3x5 non-aligned ===", test_num);
        clear_mem;

        for (r = 0; r < 7; r = r + 1)
            main_mem[14'h2000 + r] = 32'h01010101;
        for (r = 0; r < 3; r = r + 1) begin
            main_mem[14'h2800 + r*2]     = 32'h01010101;
            main_mem[14'h2800 + r*2 + 1] = 32'h00000001;
        end

        configure_gemm(16'd7, 16'd3, 16'd5,
                        32'h8000, 32'hA000, 32'hC000,
                        16'd4, 16'd8, 16'd8, 1'b0);
        start_gemm(1'b0, 1'b0);
        wait_done(15000, ok);

        if (!ok) begin $display("  FAIL: Timeout"); errors = errors + 1; end
        else begin
            for (r = 0; r < 7; r = r + 1) begin
                status = main_mem[14'h3000 + r*2];
                if (status !== 32'h03030303) begin
                    $display("  FAIL: C row %0d word0 = %h, expected 03030303", r, status);
                    errors = errors + 1;
                end
                status = main_mem[14'h3000 + r*2 + 1];
                if (status[7:0] !== 8'd3) begin
                    $display("  FAIL: C row %0d word1 low = %0d, expected 3", r, status[7:0]);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) $display("  PASS: Test %0d passed (7x3*3x5 => all 3)", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // TEST 13: 1x1 edge case (A=[5], B=[3] => C=[15])
        // ============================================================
        test_num = 13;
        errors = 0;
        $display("\n=== TEST %0d: 1x1 GEMM ===", test_num);
        clear_mem;

        main_mem[14'h2000] = 32'h00000005;
        main_mem[14'h2800] = 32'h00000003;

        configure_gemm(16'd1, 16'd1, 16'd1,
                        32'h8000, 32'hA000, 32'hC000,
                        16'd4, 16'd4, 16'd4, 1'b0);
        start_gemm(1'b0, 1'b0);
        wait_done(5000, ok);

        if (!ok) begin $display("  FAIL: Timeout"); errors = errors + 1; end
        else begin
            status = main_mem[14'h3000];
            if (status[7:0] !== 8'd15) begin
                $display("  FAIL: C[0][0] = %0d, expected 15", status[7:0]);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("  PASS: Test %0d passed (1x1 => 15)", test_num);
        else $display("  ** Test %0d: %0d failures **", test_num, errors);
        total_errors = total_errors + errors;

        // ============================================================
        // FINAL SUMMARY
        // ============================================================
        @(posedge clk); @(posedge clk);
        if (total_errors == 0) $display("\n*** ALL %0d INTEGRATION TESTS PASSED ***\n", test_num);
        else $display("\n*** %0d TOTAL FAILURES across %0d tests ***\n", total_errors, test_num);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #2000000;
        $display("TIMEOUT: Test did not complete in time");
        $finish;
    end

endmodule
