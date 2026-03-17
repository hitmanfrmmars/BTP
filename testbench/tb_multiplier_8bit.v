`timescale 1ns/1ps

// Testbench for 8-bit Multiplier
module tb_multiplier_8bit;

    // Clock and reset
    reg clk;
    reg rst;
    
    // Inputs
    reg [7:0] a;
    reg [7:0] b;
    reg valid_in;
    
    // Outputs
    wire [15:0] product;
    wire valid_out;
    
    // Instantiate the multiplier
    multiplier_8bit uut (
        .clk(clk),
        .rst(rst),
        .a(a),
        .b(b),
        .valid_in(valid_in),
        .product(product),
        .valid_out(valid_out)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end
    
    // Test stimulus
    initial begin
        // Initialize
        rst = 1;
        a = 0;
        b = 0;
        valid_in = 0;
        
        // Wait for reset
        #20;
        rst = 0;
        #10;
        
        // Test case 1: 5 * 6 = 30
        $display("Test 1: 5 * 6");
        a = 8'd5;
        b = 8'd6;
        valid_in = 1;
        #10;
        // Check immediately when valid_out should be high
        if (product == 16'd30 && valid_out)
            $display("PASS: 5 * 6 = %d", product);
        else
            $display("FAIL: Expected 30, got %d, valid_out=%b", product, valid_out);
        valid_in = 0;
        #10;
        
        // Test case 2: 15 * 10 = 150
        $display("\nTest 2: 15 * 10");
        a = 8'd15;
        b = 8'd10;
        valid_in = 1;
        #10;
        if (product == 16'd150 && valid_out)
            $display("PASS: 15 * 10 = %d", product);
        else
            $display("FAIL: Expected 150, got %d, valid_out=%b", product, valid_out);
        valid_in = 0;
        #10;
        
        // Test case 3: 255 * 255 = 65025 (max values)
        $display("\nTest 3: 255 * 255");
        a = 8'd255;
        b = 8'd255;
        valid_in = 1;
        #10;
        if (product == 16'd65025 && valid_out)
            $display("PASS: 255 * 255 = %d", product);
        else
            $display("FAIL: Expected 65025, got %d, valid_out=%b", product, valid_out);
        valid_in = 0;
        #10;
        
        // Test case 4: 0 * 100 = 0
        $display("\nTest 4: 0 * 100");
        a = 8'd0;
        b = 8'd100;
        valid_in = 1;
        #10;
        if (product == 16'd0 && valid_out)
            $display("PASS: 0 * 100 = %d", product);
        else
            $display("FAIL: Expected 0, got %d, valid_out=%b", product, valid_out);
        valid_in = 0;
        #10;
        
        #50;
        $display("\n=== Multiplier Tests Complete ===\n");
        $finish;
    end
    
    // Waveform dump (for viewing in GTKWave or similar)
    initial begin
        $dumpfile("tb_multiplier_8bit.vcd");
        $dumpvars(0, tb_multiplier_8bit);
    end

endmodule

