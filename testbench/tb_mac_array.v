`timescale 1ns/1ps

// Testbench for MAC Array
module tb_mac_array;

    // Parameters
    parameter ARRAY_SIZE = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH = 32;
    
    // Clock and reset
    reg clk;
    reg rst;
    
    // Control signals
    reg enable;
    reg accumulate;
    
    // Input matrices
    reg [DATA_WIDTH-1:0] a_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    reg [DATA_WIDTH-1:0] b_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    
    // Output matrices
    wire [ACC_WIDTH-1:0] result_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire [ARRAY_SIZE-1:0] overflow_flags [0:ARRAY_SIZE-1];
    
    // Instantiate MAC array
    mac_array #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .accumulate(accumulate),
        .a_matrix(a_matrix),
        .b_matrix(b_matrix),
        .result_matrix(result_matrix),
        .overflow_flags(overflow_flags)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end
    
    // Helper task to initialize matrices
    task init_matrices;
        integer i, j;
        begin
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                    a_matrix[i][j] = 8'd0;
                    b_matrix[i][j] = 8'd0;
                end
            end
        end
    endtask
    
    // Helper task to set matrix values
    task set_matrices_identity;
        integer i, j;
        begin
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                    if (i == j) begin
                        a_matrix[i][j] = 8'd1;
                        b_matrix[i][j] = 8'd1;
                    end else begin
                        a_matrix[i][j] = 8'd0;
                        b_matrix[i][j] = 8'd0;
                    end
                end
            end
        end
    endtask
    
    // Helper task to set simple test values
    task set_matrices_simple;
        integer i, j;
        begin
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                    a_matrix[i][j] = 8'd2;
                    b_matrix[i][j] = 8'd3;
                end
            end
        end
    endtask
    
    // Helper task to display results
    task display_results;
        integer i, j;
        begin
            $display("\nMAC Array Results:");
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                    $display("result[%0d][%0d] = %0d", i, j, result_matrix[i][j]);
                end
            end
        end
    endtask
    
    // Test stimulus
    initial begin
        // Initialize
        rst = 1;
        enable = 0;
        accumulate = 0;
        init_matrices();
        
        // Wait for reset
        #20;
        rst = 0;
        #10;
        
        // Test 1: Simple multiplication (2 * 3 = 6)
        $display("=== Test 1: Simple Multiplication ===");
        $display("All elements: a=2, b=3, expected result=6");
        set_matrices_simple();
        enable = 1;
        accumulate = 0;
        #10;
        enable = 0;
        #10;
        display_results();
        
        // Verify results
        if (result_matrix[0][0] == 32'd6 && result_matrix[1][1] == 32'd6)
            $display("PASS: Multiplication working correctly");
        else
            $display("FAIL: Expected 6, got result[0][0]=%0d", result_matrix[0][0]);
        
        #20;
        
        // Test 2: Accumulation
        $display("\n=== Test 2: Accumulation ===");
        $display("First operation: 2*3=6, then accumulate: 6 + (2*3) = 12");
        rst = 1;
        #10;
        rst = 0;
        #10;
        
        // First multiplication
        set_matrices_simple();
        enable = 1;
        accumulate = 0;
        #10;
        enable = 0;
        #10;
        $display("After first mult: result[0][0] = %0d", result_matrix[0][0]);
        
        // Second multiplication with accumulation
        enable = 1;
        accumulate = 1;
        #10;
        enable = 0;
        #10;
        display_results();
        
        if (result_matrix[0][0] == 32'd12)
            $display("PASS: Accumulation working correctly");
        else
            $display("FAIL: Expected 12, got %0d", result_matrix[0][0]);
        
        #20;
        
        // Test 3: Identity matrix behavior
        $display("\n=== Test 3: Identity-like Pattern ===");
        rst = 1;
        #10;
        rst = 0;
        #10;
        
        set_matrices_identity();
        enable = 1;
        accumulate = 0;
        #10;
        enable = 0;
        #10;
        display_results();
        
        if (result_matrix[0][0] == 32'd1 && result_matrix[0][1] == 32'd0)
            $display("PASS: Identity pattern working correctly");
        else
            $display("FAIL: Identity pattern not working as expected");
        
        #50;
        $display("\n=== MAC Array Tests Complete ===\n");
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("tb_mac_array.vcd");
        $dumpvars(0, tb_mac_array);
    end

endmodule


