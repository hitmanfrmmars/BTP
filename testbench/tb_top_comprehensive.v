// Comprehensive End-to-End Testbench
// Tests complete functionality with multiple test cases

`timescale 1ns/1ps

module tb_top_comprehensive;
    reg clk;
    reg rst;
    reg dma_start;
    reg [31:0] dma_src_addr;
    reg [31:0] dma_dst_addr;
    reg [15:0] dma_transfer_size;
    wire dma_done;
    wire dma_busy;
    
    reg matmul_start;
    reg [9:0] a_base_addr;
    reg [9:0] b_base_addr;
    reg [9:0] c_base_addr;
    wire matmul_done;
    wire matmul_busy;
    
    wire [31:0] mem_addr;
    wire mem_read;
    reg [31:0] mem_rdata;
    reg mem_ready;
    
    wire [31:0] mac_result_0_0;
    wire mac_overflow_0_0;
    
    // Simulated main memory (256 words)
    reg [31:0] main_memory [0:255];
    reg [31:0] result_memory [0:15]; // For DMA write-back verification
    
    // Clock generation
    initial begin
        clk = 0;
        forever #500 clk = ~clk;
    end
    
    // Memory read simulation
    always @(posedge clk) begin
        if (rst) begin
            mem_rdata <= 32'd0;
            mem_ready <= 1'b0;
        end else if (mem_read) begin
            mem_rdata <= main_memory[mem_addr[9:2]];
            mem_ready <= 1'b1;
        end else begin
            mem_ready <= 1'b0;
        end
    end
    
    // Instantiate top module
    top #(
        .ARRAY_SIZE(4),
        .DATA_WIDTH(8),
        .ACC_WIDTH(32),
        .ADDR_WIDTH(32)
    ) dut (
        .clk(clk),
        .rst(rst),
        .dma_start(dma_start),
        .dma_src_addr(dma_src_addr),
        .dma_dst_addr(dma_dst_addr),
        .dma_transfer_size(dma_transfer_size),
        .dma_done(dma_done),
        .dma_busy(dma_busy),
        .matmul_start(matmul_start),
        .a_base_addr(a_base_addr),
        .b_base_addr(b_base_addr),
        .c_base_addr(c_base_addr),
        .matmul_done(matmul_done),
        .matmul_busy(matmul_busy),
        .mem_addr(mem_addr),
        .mem_read(mem_read),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        .mac_result_0_0(mac_result_0_0),
        .mac_overflow_0_0(mac_overflow_0_0)
    );
    
    // Test variables
    integer i, j, k, errors, test_num;
    reg [31:0] expected_c [0:3][0:3];
    reg [31:0] readback;
    reg [7:0] c_element;
    reg done_seen;
    reg [7:0] test_a [0:3][0:3];
    reg [7:0] test_b [0:3][0:3];
    
    // VCD dump
    initial begin
        $dumpfile("tb_top_comprehensive.vcd");
        $dumpvars(0, tb_top_comprehensive);
    end
    
    // Extract byte from word
    function [7:0] extract_byte;
        input [31:0] word;
        input [1:0] byte_sel;
        begin
            case (byte_sel)
                2'd0: extract_byte = word[7:0];
                2'd1: extract_byte = word[15:8];
                2'd2: extract_byte = word[23:16];
                2'd3: extract_byte = word[31:24];
            endcase
        end
    endfunction
    
    // Calculate expected result manually
    task calculate_expected;
        integer i, j, k;
        begin
            for (i = 0; i < 4; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    expected_c[i][j] = 0;
                    for (k = 0; k < 4; k = k + 1) begin
                        expected_c[i][j] = expected_c[i][j] + (test_a[i][k] * test_b[k][j]);
                    end
                end
            end
        end
    endtask
    
    // Load matrix to main memory
    task load_matrix_to_mem;
        input [31:0] base_addr;
        integer i;
        begin
            for (i = 0; i < 4; i = i + 1) begin
                main_memory[(base_addr >> 2) + i] = {
                    test_a[i][3], test_a[i][2], 
                    test_a[i][1], test_a[i][0]
                };
            end
        end
    endtask
    
    // Load B matrix to main memory
    task load_b_matrix_to_mem;
        input [31:0] base_addr;
        integer i;
        begin
            for (i = 0; i < 4; i = i + 1) begin
                main_memory[(base_addr >> 2) + i] = {
                    test_b[i][3], test_b[i][2], 
                    test_b[i][1], test_b[i][0]
                };
            end
        end
    endtask
    
    // DMA load task
    task dma_load;
        input [31:0] src;
        input [31:0] dst;
        input [15:0] size;
        begin
            @(posedge clk);
            dma_src_addr = src;
            dma_dst_addr = dst;
            dma_transfer_size = size;
            dma_start = 1;
            @(posedge clk);
            dma_start = 0;
            
            done_seen = 0;
            repeat(1000) begin
                @(posedge clk);
                if (dma_done && !done_seen) begin
                    done_seen = 1;
                end
            end
            
            if (!done_seen) begin
                $display("  ✗ DMA timeout");
                errors = errors + 1;
            end
        end
    endtask
    
    // Matrix multiply task
    task matmul_compute;
        begin
            @(posedge clk);
            matmul_start = 1;
            @(posedge clk);
            matmul_start = 0;
            
            done_seen = 0;
            repeat(500) begin
                @(posedge clk);
                if (matmul_done && !done_seen) begin
                    done_seen = 1;
                end
            end
            
            if (!done_seen) begin
                $display("  ✗ Matrix multiply timeout");
                errors = errors + 1;
            end
        end
    endtask
    
    // Verify results
    task verify_results;
        integer i, j;
        reg all_correct;
        begin
            all_correct = 1;
            for (i = 0; i < 4; i = i + 1) begin
                readback = dut.spad_inst.memory[(c_base_addr >> 2) + i];
                for (j = 0; j < 4; j = j + 1) begin
                    c_element = extract_byte(readback, j[1:0]);
                    if (c_element != expected_c[i][j][7:0]) begin
                        $display("  ✗ C[%0d][%0d] = %3d (expected %3d)", 
                            i, j, c_element, expected_c[i][j][7:0]);
                        errors = errors + 1;
                        all_correct = 0;
                    end
                end
            end
            if (all_correct) begin
                $display("  ✓ All 16 elements correct!");
            end
        end
    endtask
    
    // Main test
    initial begin
        $display("========================================");
        $display("  Comprehensive End-to-End Test");
        $display("========================================");
        $display("");
        
        errors = 0;
        test_num = 0;
        
        // Initialize
        rst = 1;
        dma_start = 0;
        matmul_start = 0;
        a_base_addr = 10'h000;
        b_base_addr = 10'h010;
        c_base_addr = 10'h020;
        
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // ============================================
        // Test 1: Identity Matrix
        // ============================================
        test_num = test_num + 1;
        $display("=== Test %0d: Identity Matrix ===", test_num);
        $display("A × I = A");
        $display("");
        
        // Setup matrices
        test_a[0][0]=1; test_a[0][1]=2; test_a[0][2]=3; test_a[0][3]=4;
        test_a[1][0]=5; test_a[1][1]=6; test_a[1][2]=7; test_a[1][3]=8;
        test_a[2][0]=1; test_a[2][1]=2; test_a[2][2]=3; test_a[2][3]=4;
        test_a[3][0]=5; test_a[3][1]=6; test_a[3][2]=7; test_a[3][3]=8;
        
        test_b[0][0]=1; test_b[0][1]=0; test_b[0][2]=0; test_b[0][3]=0;
        test_b[1][0]=0; test_b[1][1]=1; test_b[1][2]=0; test_b[1][3]=0;
        test_b[2][0]=0; test_b[2][1]=0; test_b[2][2]=1; test_b[2][3]=0;
        test_b[3][0]=0; test_b[3][1]=0; test_b[3][2]=0; test_b[3][3]=1;
        
        calculate_expected();
        load_matrix_to_mem(32'h0000);
        load_b_matrix_to_mem(32'h0010);
        
        $display("  Loading matrices...");
        dma_load(32'h0000, 32'h0000, 16'd16);
        dma_load(32'h0010, 32'h0010, 16'd16);
        
        $display("  Computing...");
        matmul_compute();
        
        $display("  Verifying...");
        verify_results();
        $display("");
        
        // Reset for next test
        rst = 1;
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // ============================================
        // Test 2: 2×2 Sub-matrix
        // ============================================
        test_num = test_num + 1;
        $display("=== Test %0d: 2×2 Matrix ===", test_num);
        $display("A = [[1,2],[3,4]], B = [[5,6],[7,8]]");
        $display("Expected: C = [[19,22],[43,50]]");
        $display("");
        
        test_a[0][0]=1; test_a[0][1]=2; test_a[0][2]=0; test_a[0][3]=0;
        test_a[1][0]=3; test_a[1][1]=4; test_a[1][2]=0; test_a[1][3]=0;
        test_a[2][0]=0; test_a[2][1]=0; test_a[2][2]=0; test_a[2][3]=0;
        test_a[3][0]=0; test_a[3][1]=0; test_a[3][2]=0; test_a[3][3]=0;
        
        test_b[0][0]=5; test_b[0][1]=6; test_b[0][2]=0; test_b[0][3]=0;
        test_b[1][0]=7; test_b[1][1]=8; test_b[1][2]=0; test_b[1][3]=0;
        test_b[2][0]=0; test_b[2][1]=0; test_b[2][2]=0; test_b[2][3]=0;
        test_b[3][0]=0; test_b[3][1]=0; test_b[3][2]=0; test_b[3][3]=0;
        
        calculate_expected();
        load_matrix_to_mem(32'h0000);
        load_b_matrix_to_mem(32'h0010);
        
        $display("  Loading matrices...");
        dma_load(32'h0000, 32'h0000, 16'd16);
        dma_load(32'h0010, 32'h0010, 16'd16);
        
        $display("  Computing...");
        matmul_compute();
        
        $display("  Verifying...");
        verify_results();
        $display("");
        
        // Reset
        rst = 1;
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // ============================================
        // Test 3: Random Values
        // ============================================
        test_num = test_num + 1;
        $display("=== Test %0d: Random Values ===", test_num);
        $display("");
        
        test_a[0][0]=10; test_a[0][1]=20; test_a[0][2]=30; test_a[0][3]=40;
        test_a[1][0]=50; test_a[1][1]=60; test_a[1][2]=70; test_a[1][3]=80;
        test_a[2][0]=11; test_a[2][1]=22; test_a[2][2]=33; test_a[2][3]=44;
        test_a[3][0]=55; test_a[3][1]=66; test_a[3][2]=77; test_a[3][3]=88;
        
        test_b[0][0]=1; test_b[0][1]=2; test_b[0][2]=3; test_b[0][3]=4;
        test_b[1][0]=5; test_b[1][1]=6; test_b[1][2]=7; test_b[1][3]=8;
        test_b[2][0]=9; test_b[2][1]=10; test_b[2][2]=11; test_b[2][3]=12;
        test_b[3][0]=13; test_b[3][1]=14; test_b[3][2]=15; test_b[3][3]=16;
        
        calculate_expected();
        load_matrix_to_mem(32'h0000);
        load_b_matrix_to_mem(32'h0010);
        
        $display("  Loading matrices...");
        dma_load(32'h0000, 32'h0000, 16'd16);
        dma_load(32'h0010, 32'h0010, 16'd16);
        
        $display("  Computing...");
        matmul_compute();
        
        $display("  Verifying...");
        verify_results();
        $display("");
        
        // Reset
        rst = 1;
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // ============================================
        // Test 4: Edge Case - Zeros
        // ============================================
        test_num = test_num + 1;
        $display("=== Test %0d: Zero Matrix ===", test_num);
        $display("A = 0, B = random");
        $display("");
        
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                test_a[i][j] = 0;
            end
        end
        
        test_b[0][0]=1; test_b[0][1]=2; test_b[0][2]=3; test_b[0][3]=4;
        test_b[1][0]=5; test_b[1][1]=6; test_b[1][2]=7; test_b[1][3]=8;
        test_b[2][0]=9; test_b[2][1]=10; test_b[2][2]=11; test_b[2][3]=12;
        test_b[3][0]=13; test_b[3][1]=14; test_b[3][2]=15; test_b[3][3]=16;
        
        calculate_expected();
        load_matrix_to_mem(32'h0000);
        load_b_matrix_to_mem(32'h0010);
        
        $display("  Loading matrices...");
        dma_load(32'h0000, 32'h0000, 16'd16);
        dma_load(32'h0010, 32'h0010, 16'd16);
        
        $display("  Computing...");
        matmul_compute();
        
        $display("  Verifying...");
        verify_results();
        $display("");
        
        // ============================================
        // Summary
        // ============================================
        $display("========================================");
        $display("  Comprehensive Test Complete!");
        $display("========================================");
        $display("");
        $display("Tests Run: %0d", test_num);
        if (errors == 0) begin
            $display("Errors: 0");
            $display("");
            $display("✓ ALL TESTS PASSED!");
            $display("");
            $display("Verified:");
            $display("  ✓ Identity matrix property");
            $display("  ✓ 2×2 sub-matrix computation");
            $display("  ✓ Random value computation");
            $display("  ✓ Edge case (zero matrix)");
            $display("  ✓ DMA data loading");
            $display("  ✓ Matrix multiplication");
            $display("  ✓ Result write-back");
        end else begin
            $display("Errors: %0d", errors);
            $display("✗ SOME TESTS FAILED");
        end
        $display("");
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #200000000; // 200ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule

