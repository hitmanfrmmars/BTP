// Testbench for Matrix Multiplication Controller - Step 7: Write-Back
// Tests result write-back to scratchpad memory

`timescale 1ns/1ps

module tb_matmul_step7;
    reg clk;
    reg rst;
    reg start;
    wire done;
    wire busy;
    
    // Scratchpad signals
    wire [9:0] spad_addr_b;
    wire spad_re_b;
    wire [31:0] spad_rdata_b;
    wire spad_we_b;
    wire [31:0] spad_wdata_b;
    
    // MAC array signals
    wire [7:0] a_matrix [0:3][0:3];
    wire [7:0] b_matrix [0:3][0:3];
    wire mac_enable;
    wire mac_accumulate;
    wire [31:0] result_matrix [0:3][0:3];
    
    // Base addresses
    localparam A_BASE = 10'h000;
    localparam B_BASE = 10'h010;
    localparam C_BASE = 10'h020;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #500 clk = ~clk; // 1 MHz clock
    end
    
    // Instantiate scratchpad memory
    scratchpad_mem spad (
        .clk(clk),
        .rst(rst),
        // Port A (unused in this test)
        .addr_a(10'd0),
        .we_a(1'b0),
        .re_a(1'b0),
        .wdata_a(32'd0),
        .rdata_a(),
        // Port B (controller)
        .addr_b(spad_addr_b),
        .we_b(spad_we_b),
        .re_b(spad_re_b),
        .wdata_b(spad_wdata_b),
        .rdata_b(spad_rdata_b)
    );
    
    // Instantiate MAC array
    mac_array #(
        .ARRAY_SIZE(4),
        .DATA_WIDTH(8),
        .ACC_WIDTH(32)
    ) mac_inst (
        .clk(clk),
        .rst(rst),
        .enable(mac_enable),
        .accumulate(mac_accumulate),
        .a_matrix(a_matrix),
        .b_matrix(b_matrix),
        .result_matrix(result_matrix),
        .overflow_flags()
    );
    
    // Instantiate controller
    matmul_controller ctrl (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a_base_addr(A_BASE),
        .b_base_addr(B_BASE),
        .c_base_addr(C_BASE),
        .done(done),
        .busy(busy),
        .spad_addr(spad_addr_b),
        .spad_re(spad_re_b),
        .spad_rdata(spad_rdata_b),
        .spad_we(spad_we_b),
        .spad_wdata(spad_wdata_b),
        .a_matrix(a_matrix),
        .b_matrix(b_matrix),
        .mac_enable(mac_enable),
        .mac_accumulate(mac_accumulate),
        .result_matrix(result_matrix)
    );
    
    // Test variables
    integer i, j, errors;
    reg [31:0] expected_c [0:3][0:3];
    reg [31:0] readback;
    reg [7:0] c_element;
    reg done_seen;
    
    // VCD dump
    initial begin
        $dumpfile("tb_matmul_step7.vcd");
        $dumpvars(0, tb_matmul_step7);
    end
    
    // Helper task to write to scratchpad
    task write_spad;
        input [9:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            spad.memory[addr[9:2]] = data;  // Convert byte addr to word addr
        end
    endtask
    
    // Helper task to read from scratchpad
    task read_spad;
        input [9:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            data = spad.memory[addr[9:2]];  // Convert byte addr to word addr
        end
    endtask
    
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
        $display("  Step 7: Write-Back Test");
        $display("========================================");
        $display("");
        
        // Initialize
        rst = 1;
        start = 0;
        errors = 0;
        
        // Reset
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // ============================================
        // Test 1: 2x2 Matrix Multiply with Write-Back
        // ============================================
        $display("=== Test 1: 2x2 Matrix Multiply ===");
        $display("");
        
        // Setup matrices in scratchpad
        // A = [1 2 0 0]    B = [5 6 0 0]
        //     [3 4 0 0]        [7 8 0 0]
        //     [0 0 0 0]        [0 0 0 0]
        //     [0 0 0 0]        [0 0 0 0]
        // Expected C = [19 22 0 0]
        //              [43 50 0 0]
        //              [ 0  0 0 0]
        //              [ 0  0 0 0]
        
        $display("Matrix A (2x2 in 4x4 framework):");
        $display("  [1  2  0  0]");
        $display("  [3  4  0  0]");
        $display("  [0  0  0  0]");
        $display("  [0  0  0  0]");
        $display("");
        $display("Matrix B:");
        $display("  [5  6  0  0]");
        $display("  [7  8  0  0]");
        $display("  [0  0  0  0]");
        $display("  [0  0  0  0]");
        $display("");
        
        // Write A matrix (row-wise, packed 4 bytes per word)
        write_spad(A_BASE + 0, {8'd0, 8'd0, 8'd2, 8'd1});  // A[0][0..3] = 1,2,0,0
        write_spad(A_BASE + 4, {8'd0, 8'd0, 8'd4, 8'd3});  // A[1][0..3] = 3,4,0,0
        write_spad(A_BASE + 8, {8'd0, 8'd0, 8'd0, 8'd0});  // A[2][0..3] = 0,0,0,0
        write_spad(A_BASE + 12, {8'd0, 8'd0, 8'd0, 8'd0}); // A[3][0..3] = 0,0,0,0
        
        // Write B matrix (row-wise, packed 4 bytes per word)
        write_spad(B_BASE + 0, {8'd0, 8'd0, 8'd6, 8'd5});  // B[0][0..3] = 5,6,0,0
        write_spad(B_BASE + 4, {8'd0, 8'd0, 8'd8, 8'd7});  // B[1][0..3] = 7,8,0,0
        write_spad(B_BASE + 8, {8'd0, 8'd0, 8'd0, 8'd0});  // B[2][0..3] = 0,0,0,0
        write_spad(B_BASE + 12, {8'd0, 8'd0, 8'd0, 8'd0}); // B[3][0..3] = 0,0,0,0
        
        // Calculate expected results (4x4 multiply with zeros)
        expected_c[0][0] = 1*5 + 2*7 + 0*0 + 0*0;  // 19
        expected_c[0][1] = 1*6 + 2*8 + 0*0 + 0*0;  // 22
        expected_c[0][2] = 1*0 + 2*0 + 0*0 + 0*0;  // 0
        expected_c[0][3] = 1*0 + 2*0 + 0*0 + 0*0;  // 0
        
        expected_c[1][0] = 3*5 + 4*7 + 0*0 + 0*0;  // 43
        expected_c[1][1] = 3*6 + 4*8 + 0*0 + 0*0;  // 50
        expected_c[1][2] = 3*0 + 4*0 + 0*0 + 0*0;  // 0
        expected_c[1][3] = 3*0 + 4*0 + 0*0 + 0*0;  // 0
        
        // Rest are zeros
        for (i = 2; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                expected_c[i][j] = 0;
            end
        end
        
        $display("Expected C:");
        $display("  [19  22   0   0]");
        $display("  [43  50   0   0]");
        $display("  [ 0   0   0   0]");
        $display("  [ 0   0   0   0]");
        $display("");
        
        // Start computation
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Wait for completion (with timeout)
        done_seen = 0;
        repeat(200) begin
            @(posedge clk);
            if (done && !done_seen) begin
                $display("✓ Computation complete!");
                $display("");
                done_seen = 1;
            end
        end
        
        if (!done_seen) begin
            $display("✗ ERROR: Timeout waiting for done signal");
            errors = errors + 1;
        end
        
        // Wait a bit for writes to complete
        repeat(5) @(posedge clk);
        
        // Read back results from scratchpad
        $display("=== Reading Back Results from Scratchpad ===");
        $display("");
        
        for (i = 0; i < 4; i = i + 1) begin
            read_spad(C_BASE + (i * 4), readback);
            $display("C[%0d]: addr=0x%03x, data=0x%08x", i, C_BASE + (i * 4), readback);
            
            for (j = 0; j < 4; j = j + 1) begin
                c_element = extract_byte(readback, j[1:0]);
                
                if (c_element == expected_c[i][j][7:0]) begin
                    $display("  ✓ C[%0d][%0d] = %3d (expected %3d)", i, j, c_element, expected_c[i][j][7:0]);
                end else begin
                    $display("  ✗ C[%0d][%0d] = %3d (expected %3d) FAIL", i, j, c_element, expected_c[i][j][7:0]);
                    errors = errors + 1;
                end
            end
        end
        $display("");
        
        // ============================================
        // Test 2: Full 4x4 Matrix Multiply
        // ============================================
        $display("=== Test 2: Full 4x4 Matrix Multiply ===");
        $display("");
        
        // Reset
        rst = 1;
        @(posedge clk);
        @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        // A = [1 2 3 4]    B = [1 0 0 0]  (B is identity)
        //     [5 6 7 8]        [0 1 0 0]
        //     [1 2 3 4]        [0 0 1 0]
        //     [5 6 7 8]        [0 0 0 1]
        // Expected: C = A (since B is identity)
        
        $display("Matrix A:");
        $display("  [1  2  3  4]");
        $display("  [5  6  7  8]");
        $display("  [1  2  3  4]");
        $display("  [5  6  7  8]");
        $display("");
        $display("Matrix B: Identity");
        $display("");
        
        // Write A matrix
        write_spad(A_BASE + 0, {8'd4, 8'd3, 8'd2, 8'd1});
        write_spad(A_BASE + 4, {8'd8, 8'd7, 8'd6, 8'd5});
        write_spad(A_BASE + 8, {8'd4, 8'd3, 8'd2, 8'd1});
        write_spad(A_BASE + 12, {8'd8, 8'd7, 8'd6, 8'd5});
        
        // Write B matrix (identity)
        write_spad(B_BASE + 0, {8'd0, 8'd0, 8'd0, 8'd1});
        write_spad(B_BASE + 4, {8'd0, 8'd0, 8'd1, 8'd0});
        write_spad(B_BASE + 8, {8'd0, 8'd1, 8'd0, 8'd0});
        write_spad(B_BASE + 12, {8'd1, 8'd0, 8'd0, 8'd0});
        
        // Expected: C = A * I = A
        expected_c[0][0] = 1; expected_c[0][1] = 2; expected_c[0][2] = 3; expected_c[0][3] = 4;
        expected_c[1][0] = 5; expected_c[1][1] = 6; expected_c[1][2] = 7; expected_c[1][3] = 8;
        expected_c[2][0] = 1; expected_c[2][1] = 2; expected_c[2][2] = 3; expected_c[2][3] = 4;
        expected_c[3][0] = 5; expected_c[3][1] = 6; expected_c[3][2] = 7; expected_c[3][3] = 8;
        
        // Start computation
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Wait for completion
        done_seen = 0;
        repeat(200) begin
            @(posedge clk);
            if (done && !done_seen) begin
                $display("✓ Computation complete!");
                $display("");
                done_seen = 1;
            end
        end
        
        if (!done_seen) begin
            $display("✗ ERROR: Timeout waiting for done signal");
            errors = errors + 1;
        end
        
        // Wait for writes
        repeat(5) @(posedge clk);
        
        // Read back and verify
        $display("=== Reading Back Results ===");
        $display("");
        
        for (i = 0; i < 4; i = i + 1) begin
            read_spad(C_BASE + (i * 4), readback);
            
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
                    if (j == 3) $write("] ✗ FAIL\n");
                    errors = errors + 1;
                end
            end
        end
        $display("");
        
        // Summary
        $display("========================================");
        $display("       Step 7 Tests Complete!");
        $display("========================================");
        $display("");
        if (errors == 0) begin
            $display("Summary:");
            $display("  ✓ Write-back working");
            $display("  ✓ Results written to correct addresses");
            $display("  ✓ All elements verified");
            $display("  ✓ Memory readback correct");
            $display("");
            $display("Write-back verified!");
            $display("✓ Step 7 COMPLETE - Ready for Step 8!");
        end else begin
            $display("✗ %0d errors found", errors);
            $display("Step 7 FAILED");
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

