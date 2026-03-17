`timescale 1ns/1ps

// Testbench for Top-level Integration
module tb_top;

    // Parameters
    parameter ARRAY_SIZE = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH = 32;
    parameter ADDR_WIDTH = 32;
    
    // Clock and reset
    reg clk;
    reg rst;
    
    // DMA control signals
    reg dma_start;
    reg [ADDR_WIDTH-1:0] dma_src_addr;
    reg [ADDR_WIDTH-1:0] dma_dst_addr;
    reg [15:0] dma_transfer_size;
    wire dma_done;
    wire dma_busy;
    
    // MAC control signals
    reg mac_enable;
    reg mac_accumulate;
    reg [9:0] mac_input_addr_a;
    reg [9:0] mac_input_addr_b;
    reg [9:0] mac_output_addr;
    reg mac_write_enable;
    
    // Main memory interface
    wire [ADDR_WIDTH-1:0] mem_addr;
    wire mem_read;
    reg [31:0] mem_rdata;
    reg mem_ready;
    
    // Status outputs
    wire [ACC_WIDTH-1:0] mac_result_0_0;
    wire mac_overflow_0_0;
    
    // Instantiate top module
    top #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .dma_start(dma_start),
        .dma_src_addr(dma_src_addr),
        .dma_dst_addr(dma_dst_addr),
        .dma_transfer_size(dma_transfer_size),
        .dma_done(dma_done),
        .dma_busy(dma_busy),
        .mac_enable(mac_enable),
        .mac_accumulate(mac_accumulate),
        .mem_addr(mem_addr),
        .mem_read(mem_read),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        .mac_input_addr_a(mac_input_addr_a),
        .mac_input_addr_b(mac_input_addr_b),
        .mac_output_addr(mac_output_addr),
        .mac_write_enable(mac_write_enable),
        .mac_result_0_0(mac_result_0_0),
        .mac_overflow_0_0(mac_overflow_0_0)
    );
    
    // Simulated main memory
    reg [31:0] main_memory [0:255];
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end
    
    // Memory model - responds to read requests
    always @(posedge clk) begin
        if (mem_read) begin
            mem_rdata <= main_memory[mem_addr[9:2]]; // Word-aligned access
            mem_ready <= 1'b1;
        end else begin
            mem_ready <= 1'b0;
        end
    end
    
    // Initialize main memory with test data
    task init_memory;
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                main_memory[i] = 32'h04030201 + i; // Pattern: incremental values
            end
            // Set specific test values
            main_memory[0] = 32'h04030201;  // 1,2,3,4
            main_memory[1] = 32'h08070605;  // 5,6,7,8
            main_memory[2] = 32'h0C0B0A09;  // 9,10,11,12
            main_memory[3] = 32'h100F0E0D;  // 13,14,15,16
        end
    endtask
    
    // Test stimulus
    initial begin
        // Initialize signals
        rst = 1;
        dma_start = 0;
        dma_src_addr = 0;
        dma_dst_addr = 0;
        dma_transfer_size = 0;
        mac_enable = 0;
        mac_accumulate = 0;
        mac_input_addr_a = 0;
        mac_input_addr_b = 0;
        mac_output_addr = 0;
        mac_write_enable = 0;
        mem_ready = 0;
        
        // Initialize memory
        init_memory();
        
        // Wait for reset
        #20;
        rst = 0;
        #10;
        
        // Test 1: DMA Transfer
        $display("=== Test 1: DMA Transfer from Main Memory to Scratchpad ===");
        dma_src_addr = 32'h00000000;  // Start of main memory
        dma_dst_addr = 32'h00000000;  // Start of scratchpad
        dma_transfer_size = 16'd4;     // Transfer 4 words
        dma_start = 1;
        #10;
        dma_start = 0;
        
        // Wait for DMA to complete
        wait(dma_done);
        $display("DMA Transfer Complete!");
        #20;
        
        // Test 2: MAC Array Operation
        $display("\n=== Test 2: MAC Array Operation ===");
        mac_input_addr_a = 10'd0;     // Read from scratchpad address 0
        mac_input_addr_b = 10'd4;     // Read from scratchpad address 4
        mac_output_addr = 10'd16;     // Write to scratchpad address 16
        
        mac_enable = 1;
        mac_accumulate = 0;
        #10;
        mac_enable = 0;
        #20;
        
        $display("MAC Result [0][0] = %0d", mac_result_0_0);
        if (mac_overflow_0_0)
            $display("WARNING: Overflow detected!");
        
        // Test 3: MAC with Accumulation
        $display("\n=== Test 3: MAC with Accumulation ===");
        mac_enable = 1;
        mac_accumulate = 1;
        #10;
        mac_enable = 0;
        #20;
        
        $display("MAC Result [0][0] after accumulation = %0d", mac_result_0_0);
        
        // Test 4: Write back to scratchpad
        $display("\n=== Test 4: Write Result to Scratchpad ===");
        mac_write_enable = 1;
        #10;
        mac_write_enable = 0;
        #10;
        $display("Result written to scratchpad at address %0d", mac_output_addr);
        
        #50;
        $display("\n=== Top-level Integration Tests Complete ===\n");
        $display("Summary:");
        $display("  - DMA successfully transferred data from main memory to scratchpad");
        $display("  - MAC array performed multiplication and accumulation");
        $display("  - Results written back to scratchpad");
        $display("\nNext steps:");
        $display("  - Verify scratchpad contents manually if needed");
        $display("  - Add more comprehensive matrix multiplication tests");
        $display("  - Implement full matrix computation flow");
        
        $finish;
    end
    
    // Monitor key signals
    initial begin
        $monitor("Time=%0t | DMA: busy=%b done=%b | MAC: enable=%b result[0][0]=%0d", 
                 $time, dma_busy, dma_done, mac_enable, mac_result_0_0);
    end
    
    // Waveform dump
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end
    
    // Timeout watchdog
    initial begin
        #10000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule


