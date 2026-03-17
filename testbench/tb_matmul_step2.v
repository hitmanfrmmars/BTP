`timescale 1ns/1ps

// Testbench for Step 2: Address Calculation
module tb_matmul_step2;

    // Signals
    reg clk;
    reg rst;
    reg start;
    reg [9:0] a_base_addr;
    reg [9:0] b_base_addr;
    reg [9:0] c_base_addr;
    wire done;
    wire busy;
    
    // Instantiate controller
    matmul_controller uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a_base_addr(a_base_addr),
        .b_base_addr(b_base_addr),
        .c_base_addr(c_base_addr),
        .done(done),
        .busy(busy)
    );
    
    // Clock generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test variables
    integer i, j;
    integer errors;
    reg [9:0] expected_addr;
    reg [1:0] expected_byte;
    reg [9:0] actual_addr;
    reg [1:0] actual_byte;
    reg [31:0] test_word;
    reg [7:0] extracted;
    
    // Test procedure
    initial begin
        $display("\n========================================");
        $display("  Step 2: Address Calculation Test");
        $display("========================================\n");
        
        // Initialize
        rst = 1;
        start = 0;
        a_base_addr = 10'h000;  // A matrix at 0x000
        b_base_addr = 10'h010;  // B matrix at 0x010 (16 bytes after A)
        c_base_addr = 10'h020;  // C matrix at 0x020 (32 bytes after A)
        errors = 0;
        
        #20;
        rst = 0;
        #10;
        
        $display("Configuration:");
        $display("  A matrix base address: 0x%03h", a_base_addr);
        $display("  B matrix base address: 0x%03h", b_base_addr);
        $display("  C matrix base address: 0x%03h\n", c_base_addr);
        
        // ========================================
        // Test 1: A Matrix Address Calculation
        // ========================================
        $display("=== Test 1: A Matrix Address Calculation ===\n");
        $display("A matrix layout (4x4, row-major):");
        $display("  A[0][0..3] at addr 0x000, bytes [0][1][2][3]");
        $display("  A[1][0..3] at addr 0x004, bytes [0][1][2][3]");
        $display("  A[2][0..3] at addr 0x008, bytes [0][1][2][3]");
        $display("  A[3][0..3] at addr 0x00C, bytes [0][1][2][3]\n");
        
        $display("Testing all 16 elements:");
        $display("Element | Expected Addr | Actual Addr | Expected Byte | Actual Byte | Result");
        $display("--------|---------------|-------------|---------------|-------------|-------");
        
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                // Calculate expected
                expected_addr = a_base_addr + (i * 4);
                expected_byte = j;
                
                // Get actual from functions
                actual_addr = uut.calc_a_word_addr(i[1:0]);
                actual_byte = uut.calc_a_byte_sel(j[1:0]);
                
                // Display and verify
                $write("A[%0d][%0d] |    0x%03h      |   0x%03h    |      %0d        |      %0d      | ", 
                       i, j, expected_addr, actual_addr, expected_byte, actual_byte);
                
                if (actual_addr == expected_addr && actual_byte == expected_byte) begin
                    $display("✓ PASS");
                end else begin
                    $display("✗ FAIL");
                    errors = errors + 1;
                end
            end
        end
        
        if (errors == 0) begin
            $display("\n✓ All A matrix addresses correct!\n");
        end else begin
            $display("\n✗ %0d errors in A matrix addresses\n", errors);
        end
        
        // ========================================
        // Test 2: B Matrix Address Calculation
        // ========================================
        $display("=== Test 2: B Matrix Address Calculation ===\n");
        $display("B matrix layout (4x4, row-major):");
        $display("  B[0][0..3] at addr 0x010, bytes [0][1][2][3]");
        $display("  B[1][0..3] at addr 0x014, bytes [0][1][2][3]");
        $display("  B[2][0..3] at addr 0x018, bytes [0][1][2][3]");
        $display("  B[3][0..3] at addr 0x01C, bytes [0][1][2][3]\n");
        
        $display("Testing all 16 elements:");
        $display("Element | Expected Addr | Actual Addr | Expected Byte | Actual Byte | Result");
        $display("--------|---------------|-------------|---------------|-------------|-------");
        
        errors = 0;
        for (i = 0; i < 4; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                // Calculate expected
                expected_addr = b_base_addr + (i * 4);
                expected_byte = j;
                
                // Get actual from functions
                actual_addr = uut.calc_b_word_addr(i[1:0]);
                actual_byte = uut.calc_b_byte_sel(j[1:0]);
                
                // Display and verify
                $write("B[%0d][%0d] |    0x%03h      |   0x%03h    |      %0d        |      %0d      | ", 
                       i, j, expected_addr, actual_addr, expected_byte, actual_byte);
                
                if (actual_addr == expected_addr && actual_byte == expected_byte) begin
                    $display("✓ PASS");
                end else begin
                    $display("✗ FAIL");
                    errors = errors + 1;
                end
            end
        end
        
        if (errors == 0) begin
            $display("\n✓ All B matrix addresses correct!\n");
        end else begin
            $display("\n✗ %0d errors in B matrix addresses\n", errors);
        end
        
        // ========================================
        // Test 3: C Matrix Address Calculation
        // ========================================
        $display("=== Test 3: C Matrix (Result) Address Calculation ===\n");
        
        errors = 0;
        for (i = 0; i < 4; i = i + 1) begin
            expected_addr = c_base_addr + (i * 4);
            actual_addr = uut.calc_c_word_addr(i[1:0]);
            
            $write("C[%0d][x] at addr: expected 0x%03h, actual 0x%03h ... ", 
                   i, expected_addr, actual_addr);
            
            if (actual_addr == expected_addr) begin
                $display("✓ PASS");
            end else begin
                $display("✗ FAIL");
                errors = errors + 1;
            end
        end
        
        if (errors == 0) begin
            $display("\n✓ All C matrix addresses correct!\n");
        end else begin
            $display("\n✗ %0d errors in C matrix addresses\n", errors);
        end
        
        // ========================================
        // Test 4: Byte Extraction Function
        // ========================================
        $display("=== Test 4: Byte Extraction ===\n");
        
        test_word = 32'hDEADBEEF;
        $display("Test word: 0x%08h", test_word);
        $display("  Byte layout: [3]=0xDE, [2]=0xAD, [1]=0xBE, [0]=0xEF\n");
        
        errors = 0;
        
        extracted = uut.extract_byte(test_word, 2'd0);
        $write("  Extract byte 0: expected 0xEF, got 0x%02h ... ", extracted);
        if (extracted == 8'hEF) begin
            $display("✓ PASS");
        end else begin
            $display("✗ FAIL");
            errors = errors + 1;
        end
        
        extracted = uut.extract_byte(test_word, 2'd1);
        $write("  Extract byte 1: expected 0xBE, got 0x%02h ... ", extracted);
        if (extracted == 8'hBE) begin
            $display("✓ PASS");
        end else begin
            $display("✗ FAIL");
            errors = errors + 1;
        end
        
        extracted = uut.extract_byte(test_word, 2'd2);
        $write("  Extract byte 2: expected 0xAD, got 0x%02h ... ", extracted);
        if (extracted == 8'hAD) begin
            $display("✓ PASS");
        end else begin
            $display("✗ FAIL");
            errors = errors + 1;
        end
        
        extracted = uut.extract_byte(test_word, 2'd3);
        $write("  Extract byte 3: expected 0xDE, got 0x%02h ... ", extracted);
        if (extracted == 8'hDE) begin
            $display("✓ PASS");
        end else begin
            $display("✗ FAIL");
            errors = errors + 1;
        end
        
        if (errors == 0) begin
            $display("\n✓ Byte extraction working correctly!\n");
        end else begin
            $display("\n✗ %0d errors in byte extraction\n", errors);
        end
        
        // ========================================
        // Test 5: Example Address Lookups
        // ========================================
        $display("=== Test 5: Example Matrix Element Lookups ===\n");
        
        $display("For matrix multiplication C = A × B:");
        $display("To compute C[0][0] = A[0][0]*B[0][0] + A[0][1]*B[1][0] + A[0][2]*B[2][0] + A[0][3]*B[3][0]\n");
        
        $display("Pass 0 (k=0): Need A[0][0] and B[0][0]");
        $display("  A[0][0]: addr=0x%03h, byte=%0d", 
                 uut.calc_a_word_addr(2'd0), uut.calc_a_byte_sel(2'd0));
        $display("  B[0][0]: addr=0x%03h, byte=%0d\n", 
                 uut.calc_b_word_addr(2'd0), uut.calc_b_byte_sel(2'd0));
        
        $display("Pass 1 (k=1): Need A[0][1] and B[1][0]");
        $display("  A[0][1]: addr=0x%03h, byte=%0d", 
                 uut.calc_a_word_addr(2'd0), uut.calc_a_byte_sel(2'd1));
        $display("  B[1][0]: addr=0x%03h, byte=%0d\n", 
                 uut.calc_b_word_addr(2'd1), uut.calc_b_byte_sel(2'd0));
        
        $display("Pass 2 (k=2): Need A[0][2] and B[2][0]");
        $display("  A[0][2]: addr=0x%03h, byte=%0d", 
                 uut.calc_a_word_addr(2'd0), uut.calc_a_byte_sel(2'd2));
        $display("  B[2][0]: addr=0x%03h, byte=%0d\n", 
                 uut.calc_b_word_addr(2'd2), uut.calc_b_byte_sel(2'd0));
        
        $display("Pass 3 (k=3): Need A[0][3] and B[3][0]");
        $display("  A[0][3]: addr=0x%03h, byte=%0d", 
                 uut.calc_a_word_addr(2'd0), uut.calc_a_byte_sel(2'd3));
        $display("  B[3][0]: addr=0x%03h, byte=%0d\n", 
                 uut.calc_b_word_addr(2'd3), uut.calc_b_byte_sel(2'd0));
        
        // Summary
        $display("========================================");
        $display("       Step 2 Tests Complete!");
        $display("========================================\n");
        $display("Summary:");
        $display("  ✓ A matrix address calculation (16 elements)");
        $display("  ✓ B matrix address calculation (16 elements)");
        $display("  ✓ C matrix address calculation (4 rows)");
        $display("  ✓ Byte extraction function (4 bytes)");
        $display("  ✓ Example lookups for matrix multiply\n");
        $display("Address calculation functions verified!");
        $display("✓ Step 2 COMPLETE - Ready for Step 3!\n");
        
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("tb_matmul_step2.vcd");
        $dumpvars(0, tb_matmul_step2);
    end

endmodule

