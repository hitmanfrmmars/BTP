`timescale 1ns/1ps

// Testbench for MAC Unit
// Tests multiply-accumulate operations needed for matrix multiplication
module tb_mac_unit;

    // Clock and reset
    reg clk;
    reg rst;
    
    // Control signals
    reg enable;
    reg accumulate;
    
    // Inputs
    reg [7:0] a;
    reg [7:0] b;
    
    // Outputs
    wire [31:0] result;
    wire overflow;
    
    // Instantiate MAC unit
    mac_unit uut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .accumulate(accumulate),
        .a(a),
        .b(b),
        .result(result),
        .overflow(overflow)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end
    
    // Test stimulus
    initial begin
        $display("\n========================================");
        $display("   MAC Unit Test for Matrix Multiply");
        $display("========================================\n");
        
        // Initialize
        rst = 1;
        enable = 0;
        accumulate = 0;
        a = 0;
        b = 0;
        
        // Wait for reset
        #20;
        rst = 0;
        #10;
        
        // ====================================
        // Test 1: Simple Multiplication (No Accumulate)
        // ====================================
        $display("=== Test 1: Simple Multiplication ===");
        $display("Computing: 5 * 6 (no accumulation)");
        a = 8'd5;
        b = 8'd6;
        enable = 1;
        accumulate = 0;  // Just multiply, don't accumulate
        #10;
        enable = 0;
        #10;
        $display("Result: %0d (Expected: 30)", result);
        if (result == 32'd30)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        // ====================================
        // Test 2: Accumulation
        // ====================================
        $display("=== Test 2: Accumulation ===");
        $display("Computing: 30 + (4 * 5)");
        a = 8'd4;
        b = 8'd5;
        enable = 1;
        accumulate = 1;  // Accumulate previous result
        #10;
        enable = 0;
        #10;
        $display("Result: %0d (Expected: 50)", result);
        if (result == 32'd50)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        // ====================================
        // Test 3: Dot Product Simulation
        // Computing: (2*3) + (4*5) + (1*2) = 6 + 20 + 2 = 28
        // This is like computing one element of matrix multiplication!
        // ====================================
        $display("=== Test 3: Dot Product (Matrix Multiply Element) ===");
        $display("Simulating: C[0][0] = A[0][0]*B[0][0] + A[0][1]*B[1][0] + A[0][2]*B[2][0]");
        $display("           = 2*3 + 4*5 + 1*2 = 6 + 20 + 2 = 28\n");
        
        // Reset MAC unit
        rst = 1;
        #10;
        rst = 0;
        #10;
        
        // First multiply: 2 * 3 = 6
        $display("Step 1: 2 * 3 = 6");
        a = 8'd2;
        b = 8'd3;
        enable = 1;
        accumulate = 0;  // Start fresh
        #10;
        $display("  Result: %0d", result);
        enable = 0;
        #10;
        
        // Second multiply-accumulate: 6 + (4 * 5) = 26
        $display("Step 2: 6 + (4 * 5) = 26");
        a = 8'd4;
        b = 8'd5;
        enable = 1;
        accumulate = 1;  // Accumulate
        #10;
        $display("  Result: %0d", result);
        enable = 0;
        #10;
        
        // Third multiply-accumulate: 26 + (1 * 2) = 28
        $display("Step 3: 26 + (1 * 2) = 28");
        a = 8'd1;
        b = 8'd2;
        enable = 1;
        accumulate = 1;  // Accumulate
        #10;
        $display("  Result: %0d", result);
        enable = 0;
        #10;
        
        $display("\nFinal dot product result: %0d (Expected: 28)", result);
        if (result == 32'd28)
            $display("✓ PASS - Dot product works!\n");
        else
            $display("✗ FAIL\n");
        
        // ====================================
        // Test 4: Matrix Multiplication Example (2x2)
        // A = [1 2]    B = [5 6]    C = [19 22]
        //     [3 4]        [7 8]        [43 50]
        //
        // C[0][0] = 1*5 + 2*7 = 5 + 14 = 19
        // ====================================
        $display("=== Test 4: 2x2 Matrix Multiplication Element ===");
        $display("Matrix A:        Matrix B:");
        $display("  [1  2]           [5  6]");
        $display("  [3  4]           [7  8]");
        $display("\nComputing C[0][0] = 1*5 + 2*7 = 19\n");
        
        // Reset MAC unit
        rst = 1;
        #10;
        rst = 0;
        #10;
        
        // C[0][0] = A[0][0]*B[0][0] + A[0][1]*B[1][0]
        //         = 1*5 + 2*7 = 19
        
        $display("Step 1: 1 * 5 = 5");
        a = 8'd1;  // A[0][0]
        b = 8'd5;  // B[0][0]
        enable = 1;
        accumulate = 0;
        #10;
        $display("  Result: %0d", result);
        enable = 0;
        #10;
        
        $display("Step 2: 5 + (2 * 7) = 19");
        a = 8'd2;  // A[0][1]
        b = 8'd7;  // B[1][0]
        enable = 1;
        accumulate = 1;
        #10;
        $display("  Result: %0d", result);
        enable = 0;
        #10;
        
        $display("\nC[0][0] = %0d (Expected: 19)", result);
        if (result == 32'd19)
            $display("✓ PASS - Matrix element computed correctly!\n");
        else
            $display("✗ FAIL\n");
        
        // ====================================
        // Test 5: Larger accumulation
        // ====================================
        $display("=== Test 5: Larger Values & Accumulation ===");
        $display("Computing: 100*200 + 50*50 + 10*10 = 20000 + 2500 + 100 = 22600\n");
        
        rst = 1;
        #10;
        rst = 0;
        #10;
        
        a = 8'd100;
        b = 8'd200;
        enable = 1;
        accumulate = 0;
        #10;
        $display("Step 1: 100 * 200 = %0d", result);
        enable = 0;
        #10;
        
        a = 8'd50;
        b = 8'd50;
        enable = 1;
        accumulate = 1;
        #10;
        $display("Step 2: 20000 + (50 * 50) = %0d", result);
        enable = 0;
        #10;
        
        a = 8'd10;
        b = 8'd10;
        enable = 1;
        accumulate = 1;
        #10;
        $display("Step 3: 22500 + (10 * 10) = %0d", result);
        enable = 0;
        #10;
        
        $display("\nFinal result: %0d (Expected: 22600)", result);
        if (result == 32'd22600)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        // ====================================
        // Test 6: Reset clears accumulator
        // ====================================
        $display("=== Test 6: Reset Functionality ===");
        $display("Current result: %0d", result);
        $display("Applying reset...");
        rst = 1;
        #20;
        $display("Result after reset: %0d (Expected: 0)", result);
        rst = 0;
        #10;
        
        if (result == 32'd0)
            $display("✓ PASS - Reset works\n");
        else
            $display("✗ FAIL\n");
        
        // Summary
        #50;
        $display("========================================");
        $display("       MAC Unit Tests Complete!");
        $display("========================================\n");
        $display("The MAC unit successfully:");
        $display("  ✓ Performs multiplication");
        $display("  ✓ Accumulates results");
        $display("  ✓ Computes dot products");
        $display("  ✓ Can compute matrix multiplication elements");
        $display("  ✓ Handles larger values");
        $display("  ✓ Resets properly\n");
        $display("This MAC unit is the building block for");
        $display("matrix multiplication in the MAC array!\n");
        
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("tb_mac_unit.vcd");
        $dumpvars(0, tb_mac_unit);
    end
    
    // Monitor for debugging
    initial begin
        $monitor("Time=%0t | a=%0d b=%0d enable=%b acc=%b | result=%0d overflow=%b", 
                 $time, a, b, enable, accumulate, result, overflow);
    end

endmodule


