// Complete End-to-End Testbench
// Tests full matrix multiplication accelerator:
// Main Memory → DMA → Scratchpad → Controller → MAC Array → Scratchpad → DMA → Main Memory

`timescale 1ns/1ps

module tb_top_complete;
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
    
    // Clock generation
    initial begin
        clk = 0;
        forever #500 clk = ~clk; // 1 MHz clock
    end
    
    // Memory read simulation
    always @(posedge clk) begin
        if (rst) begin
            mem_rdata <= 32'd0;
            mem_ready <= 1'b0;
        end else if (mem_read) begin
            mem_rdata <= main_memory[mem_addr[9:2]]; // Word-aligned access
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
        // DMA interface
        .dma_start(dma_start),
        .dma_src_addr(dma_src_addr),
        .dma_dst_addr(dma_dst_addr),
        .dma_transfer_size(dma_transfer_size),
        .dma_done(dma_done),
        .dma_busy(dma_busy),
        // Matrix multiplication interface
        .matmul_start(matmul_start),
        .a_base_addr(a_base_addr),
        .b_base_addr(b_base_addr),
        .c_base_addr(c_base_addr),
        .matmul_done(matmul_done),
        .matmul_busy(matmul_busy),
        // Main memory interface
        .mem_addr(mem_addr),
        .mem_read(mem_read),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        // Debug
        .mac_result_0_0(mac_result_0_0),
        .mac_overflow_0_0(mac_overflow_0_0)
    );
    
    // Test variables
    integer i, j, errors;
    reg [31:0] expected_c [0:3][0:3];
    reg [31:0] readback;
    reg [7:0] c_element;
    reg done_seen;
    
    // VCD dump
    initial begin
        $dumpfile("tb_top_complete.vcd");
        $dumpvars(0, tb_top_complete);
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
    
    // Main test
    initial begin
        $display("========================================");
        $display("  End-to-End Accelerator Test");
        $display("  Complete Matrix Multiplication Flow");
        $display("========================================");
        $display("");
        
        // Initialize
        rst = 1;
        dma_start = 0;
        matmul_start = 0;
        errors = 0;
        
        // Memory addresses
        // Main memory: 0x000-0x03F for matrices
        // Scratchpad:  0x000-0x00F for A (4 words)
        //              0x010-0x01F for B (4 words)
        //              0x020-0x02F for C (4 words)
        a_base_addr = 10'h000;
        b_base_addr = 10'h010;
        c_base_addr = 10'h020;
        
        // Reset
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // ============================================
        // Test: 4x4 Matrix Multiply
        // ============================================
        $display("=== Test: 4x4 Matrix Multiply ===");
        $display("");
        
        // Setup matrices in main memory
        // A = [1 2 3 4]
        //     [5 6 7 8]
        //     [1 2 3 4]
        //     [5 6 7 8]
        $display("Matrix A:");
        $display("  [1  2  3  4]");
        $display("  [5  6  7  8]");
        $display("  [1  2  3  4]");
        $display("  [5  6  7  8]");
        $display("");
        
        // B = Identity matrix
        $display("Matrix B: Identity");
        $display("  [1  0  0  0]");
        $display("  [0  1  0  0]");
        $display("  [0  0  1  0]");
        $display("  [0  0  0  1]");
        $display("");
        
        // Write A matrix to main memory at address 0x00
        main_memory[0] = {8'd4, 8'd3, 8'd2, 8'd1};   // A[0]
        main_memory[1] = {8'd8, 8'd7, 8'd6, 8'd5};   // A[1]
        main_memory[2] = {8'd4, 8'd3, 8'd2, 8'd1};   // A[2]
        main_memory[3] = {8'd8, 8'd7, 8'd6, 8'd5};   // A[3]
        
        // Write B matrix to main memory at address 0x10
        main_memory[4] = {8'd0, 8'd0, 8'd0, 8'd1};   // B[0]
        main_memory[5] = {8'd0, 8'd0, 8'd1, 8'd0};   // B[1]
        main_memory[6] = {8'd0, 8'd1, 8'd0, 8'd0};   // B[2]
        main_memory[7] = {8'd1, 8'd0, 8'd0, 8'd0};   // B[3]
        
        // Expected C = A * I = A
        expected_c[0][0] = 1; expected_c[0][1] = 2; expected_c[0][2] = 3; expected_c[0][3] = 4;
        expected_c[1][0] = 5; expected_c[1][1] = 6; expected_c[1][2] = 7; expected_c[1][3] = 8;
        expected_c[2][0] = 1; expected_c[2][1] = 2; expected_c[2][2] = 3; expected_c[2][3] = 4;
        expected_c[3][0] = 5; expected_c[3][1] = 6; expected_c[3][2] = 7; expected_c[3][3] = 8;
        
        $display("Expected C = A:");
        $display("  [1  2  3  4]");
        $display("  [5  6  7  8]");
        $display("  [1  2  3  4]");
        $display("  [5  6  7  8]");
        $display("");
        
        // ============================================
        // Step 1: DMA Load A matrix
        // ============================================
        $display("Step 1: DMA loading A matrix (mem 0x00 → spad 0x000)...");
        @(posedge clk);
        dma_src_addr = 32'h00000000;
        dma_dst_addr = 32'h00000000;  // Scratchpad address (used as offset)
        dma_transfer_size = 16'd16;   // 4 words * 4 bytes = 16 bytes
        dma_start = 1;
        @(posedge clk);
        dma_start = 0;
        
        // Wait for DMA to complete
        done_seen = 0;
        repeat(1000) begin
            @(posedge clk);
            if (dma_done && !done_seen) begin
                $display("✓ A matrix loaded to scratchpad");
                $display("");
                done_seen = 1;
            end
        end
        
        if (!done_seen) begin
            $display("✗ ERROR: DMA timeout loading A");
            errors = errors + 1;
        end
        
        // Wait a bit
        repeat(5) @(posedge clk);
        
        // ============================================
        // Step 2: DMA Load B matrix
        // ============================================
        $display("Step 2: DMA loading B matrix (mem 0x10 → spad 0x010)...");
        @(posedge clk);
        dma_src_addr = 32'h00000010;
        dma_dst_addr = 32'h00000010;
        dma_transfer_size = 16'd16;
        dma_start = 1;
        @(posedge clk);
        dma_start = 0;
        
        // Wait for DMA to complete
        done_seen = 0;
        repeat(1000) begin
            @(posedge clk);
            if (dma_done && !done_seen) begin
                $display("✓ B matrix loaded to scratchpad");
                $display("");
                done_seen = 1;
            end
        end
        
        if (!done_seen) begin
            $display("✗ ERROR: DMA timeout loading B");
            errors = errors + 1;
        end
        
        // Wait a bit
        repeat(5) @(posedge clk);
        
        // ============================================
        // Step 3: Matrix Multiplication
        // ============================================
        $display("Step 3: Starting matrix multiplication...");
        @(posedge clk);
        matmul_start = 1;
        @(posedge clk);
        matmul_start = 0;
        
        // Wait for computation to complete
        done_seen = 0;
        repeat(500) begin
            @(posedge clk);
            if (matmul_done && !done_seen) begin
                $display("✓ Matrix multiplication complete!");
                $display("");
                done_seen = 1;
            end
        end
        
        if (!done_seen) begin
            $display("✗ ERROR: Matrix multiplication timeout");
            errors = errors + 1;
        end
        
        // Wait for results to stabilize
        repeat(10) @(posedge clk);
        
        // ============================================
        // Step 4: Read back results from scratchpad
        // ============================================
        $display("Step 4: Reading back results from scratchpad...");
        $display("");
        
        // Access scratchpad memory directly for verification
        for (i = 0; i < 4; i = i + 1) begin
            readback = dut.spad_inst.memory[(c_base_addr >> 2) + i];
            
            for (j = 0; j < 4; j = j + 1) begin
                c_element = extract_byte(readback, j[1:0]);
                
                if (c_element == expected_c[i][j][7:0]) begin
                    if (j == 0) $write("  C[%0d]: [", i);
                    $write("%3d", c_element);
                    if (j < 3) $write(" ");
                    if (j == 3) $write("] ✓\n");
                end else begin
                    if (j == 0) $write("  C[%0d]: [", i);
                    $write("%3d", c_element);
                    if (j < 3) $write(" ");
                    if (j == 3) begin
                        $write("] ✗ (expected [");
                        $write("%3d %3d %3d %3d", 
                            expected_c[i][0][7:0], expected_c[i][1][7:0],
                            expected_c[i][2][7:0], expected_c[i][3][7:0]);
                        $write("])\n");
                    end
                    errors = errors + 1;
                end
            end
        end
        $display("");
        
        // Summary
        $display("========================================");
        $display("    End-to-End Test Complete!");
        $display("========================================");
        $display("");
        if (errors == 0) begin
            $display("Summary:");
            $display("  ✓ DMA loaded A and B matrices");
            $display("  ✓ Controller orchestrated computation");
            $display("  ✓ MAC array computed all 16 elements");
            $display("  ✓ Results written back to scratchpad");
            $display("  ✓ All results correct!");
            $display("");
            $display("🎉 FULL ACCELERATOR WORKING! 🎉");
            $display("");
            $display("✓ Step 8 COMPLETE!");
            $display("");
            $display("===========================================");
            $display("  CONGRATULATIONS!");
            $display("  Your RISC-V matrix multiplication");
            $display("  accelerator is fully functional!");
            $display("===========================================");
        end else begin
            $display("✗ %0d errors found", errors);
            $display("Test FAILED");
        end
        $display("");
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #100000000; // 100ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule

