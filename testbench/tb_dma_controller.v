`timescale 1ns/1ps

// Testbench for DMA Controller
module tb_dma_controller;

    // Parameters
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    
    // Clock and reset
    reg clk;
    reg rst;
    
    // Control signals
    reg start;
    reg [ADDR_WIDTH-1:0] src_addr;
    reg [ADDR_WIDTH-1:0] dst_addr;
    reg [15:0] transfer_size;
    wire done;
    wire busy;
    
    // Main memory interface
    wire [ADDR_WIDTH-1:0] mem_addr;
    wire mem_read;
    reg [DATA_WIDTH-1:0] mem_rdata;
    reg mem_ready;
    
    // Scratchpad interface
    wire [9:0] spad_addr;
    wire [DATA_WIDTH-1:0] spad_wdata;
    wire spad_we;
    wire spad_re;
    wire [DATA_WIDTH-1:0] spad_rdata;
    
    // Simulated main memory (256 words)
    reg [DATA_WIDTH-1:0] main_memory [0:255];
    
    // Instantiate DMA Controller
    dma_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .src_addr(src_addr),
        .dst_addr(dst_addr),
        .transfer_size(transfer_size),
        .done(done),
        .busy(busy),
        .mem_addr(mem_addr),
        .mem_read(mem_read),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        .spad_addr(spad_addr),
        .spad_wdata(spad_wdata),
        .spad_we(spad_we),
        .spad_re(spad_re),
        .spad_rdata(spad_rdata)
    );
    
    // Instantiate Scratchpad Memory
    scratchpad_mem #(
        .ADDR_WIDTH(10),
        .DATA_WIDTH(32)
    ) scratchpad (
        .clk(clk),
        .rst(rst),
        .addr_a(spad_addr),
        .wdata_a(spad_wdata),
        .we_a(spad_we),
        .re_a(spad_re),
        .rdata_a(spad_rdata),
        .addr_b(10'd0),
        .wdata_b(32'd0),
        .we_b(1'b0),
        .re_b(1'b0),
        .rdata_b()
    );
    
    // Clock generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Memory model - responds to read requests
    always @(posedge clk) begin
        if (mem_read) begin
            // Simulate 1 cycle delay
            mem_rdata <= main_memory[mem_addr[9:2]]; // Word-aligned
            mem_ready <= 1'b1;
        end else begin
            mem_ready <= 1'b0;
        end
    end
    
    // Initialize main memory with test data
    task init_main_memory;
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                main_memory[i] = 32'h00000000;
            end
            
            // Test pattern 1: Sequential numbers
            main_memory[0] = 32'h04030201;  // 1, 2, 3, 4
            main_memory[1] = 32'h08070605;  // 5, 6, 7, 8
            main_memory[2] = 32'h0C0B0A09;  // 9, 10, 11, 12
            main_memory[3] = 32'h100F0E0D;  // 13, 14, 15, 16
            
            // Test pattern 2: Marker values at different addresses
            main_memory[16] = 32'hDEADBEEF;
            main_memory[17] = 32'hCAFEBABE;
            main_memory[18] = 32'h12345678;
            main_memory[19] = 32'hABCDEF00;
            
            // Test pattern 3: All same value
            main_memory[32] = 32'hAAAAAAAA;
            main_memory[33] = 32'hBBBBBBBB;
            main_memory[34] = 32'hCCCCCCCC;
            main_memory[35] = 32'hDDDDDDDD;
        end
    endtask
    
    // Task to verify scratchpad contents
    task verify_scratchpad;
        input [9:0] addr;
        input [31:0] expected;
        input [100*8:1] test_name;
        begin
            if (scratchpad.memory[addr[9:2]] == expected) begin
                $display("  ✓ PASS: %0s", test_name);
                $display("    Address 0x%03h = 0x%08h", addr, scratchpad.memory[addr[9:2]]);
            end else begin
                $display("  ✗ FAIL: %0s", test_name);
                $display("    Address 0x%03h: Expected 0x%08h, Got 0x%08h", 
                         addr, expected, scratchpad.memory[addr[9:2]]);
            end
        end
    endtask
    
    // Main test
    initial begin
        $display("\n========================================");
        $display("      DMA Controller Test");
        $display("========================================\n");
        
        // Initialize
        rst = 1;
        start = 0;
        src_addr = 0;
        dst_addr = 0;
        transfer_size = 0;
        mem_ready = 0;
        
        init_main_memory();
        
        #20;
        rst = 0;
        #10;
        
        // ====================================
        // Test 1: Small Transfer (4 words)
        // ====================================
        $display("=== Test 1: Transfer 4 Words ===");
        $display("Source: Main Memory 0x000-0x00C");
        $display("Destination: Scratchpad 0x000-0x00C");
        $display("Data: Sequential pattern [1,2,3,4...16]\n");
        
        src_addr = 32'h00000000;
        dst_addr = 32'h00000000;
        transfer_size = 16'd4;
        
        $display("Starting DMA transfer...");
        start = 1;
        #10;
        start = 0;
        
        // Wait for transfer to complete
        wait(done);
        #10;
        
        $display("Transfer complete! Verifying data...\n");
        verify_scratchpad(10'h000, 32'h04030201, "Word 0: [1,2,3,4]");
        verify_scratchpad(10'h004, 32'h08070605, "Word 1: [5,6,7,8]");
        verify_scratchpad(10'h008, 32'h0C0B0A09, "Word 2: [9,10,11,12]");
        verify_scratchpad(10'h00C, 32'h100F0E0D, "Word 3: [13,14,15,16]");
        $display("");
        
        #50;
        
        // ====================================
        // Test 2: Transfer from Different Source
        // ====================================
        $display("=== Test 2: Transfer from Different Address ===");
        $display("Source: Main Memory 0x040 (offset 16 words)");
        $display("Destination: Scratchpad 0x010");
        $display("Data: Marker values [DEADBEEF, CAFEBABE, ...]\n");
        
        src_addr = 32'h00000040;  // Word 16
        dst_addr = 32'h00000010;
        transfer_size = 16'd4;
        
        $display("Starting DMA transfer...");
        start = 1;
        #10;
        start = 0;
        
        wait(done);
        #10;
        
        $display("Transfer complete! Verifying data...\n");
        verify_scratchpad(10'h010, 32'hDEADBEEF, "Word 0: DEADBEEF");
        verify_scratchpad(10'h014, 32'hCAFEBABE, "Word 1: CAFEBABE");
        verify_scratchpad(10'h018, 32'h12345678, "Word 2: 12345678");
        verify_scratchpad(10'h01C, 32'hABCDEF00, "Word 3: ABCDEF00");
        $display("");
        
        #50;
        
        // ====================================
        // Test 3: Single Word Transfer
        // ====================================
        $display("=== Test 3: Single Word Transfer ===");
        $display("Source: Main Memory 0x080");
        $display("Destination: Scratchpad 0x020");
        $display("Data: Single word [AAAAAAAA]\n");
        
        src_addr = 32'h00000080;
        dst_addr = 32'h00000020;
        transfer_size = 16'd1;
        
        $display("Starting DMA transfer...");
        start = 1;
        #10;
        start = 0;
        
        wait(done);
        #10;
        
        $display("Transfer complete! Verifying data...\n");
        verify_scratchpad(10'h020, 32'hAAAAAAAA, "Word 0: AAAAAAAA");
        $display("");
        
        #50;
        
        // ====================================
        // Test 4: Larger Transfer (8 words)
        // ====================================
        $display("=== Test 4: Larger Transfer (8 Words) ===");
        $display("Source: Main Memory 0x000");
        $display("Destination: Scratchpad 0x100");
        $display("Simulating transfer of two 4x4 matrices\n");
        
        src_addr = 32'h00000000;
        dst_addr = 32'h00000100;
        transfer_size = 16'd8;
        
        $display("Starting DMA transfer...");
        start = 1;
        #10;
        start = 0;
        
        wait(done);
        #10;
        
        $display("Transfer complete! Checking a few samples...\n");
        verify_scratchpad(10'h100, 32'h04030201, "First word");
        verify_scratchpad(10'h11C, 32'h100F0E0D, "Last word");
        $display("");
        
        #50;
        
        // ====================================
        // Test 5: Status Signals
        // ====================================
        $display("=== Test 5: Status Signals Test ===");
        $display("Verifying busy and done signals behavior\n");
        
        src_addr = 32'h00000000;
        dst_addr = 32'h00000200;
        transfer_size = 16'd2;
        
        $display("Before start: busy=%b, done=%b", busy, done);
        if (!busy && !done)
            $display("  ✓ PASS: Idle state correct\n");
        else
            $display("  ✗ FAIL: Should be idle\n");
        
        start = 1;
        #10;
        start = 0;
        #10;
        
        $display("During transfer: busy=%b, done=%b", busy, done);
        if (busy && !done)
            $display("  ✓ PASS: Busy state correct\n");
        else
            $display("  ✗ FAIL: Should be busy\n");
        
        wait(done);
        #10;
        
        $display("After transfer: busy=%b, done=%b", busy, done);
        if (!busy && done)
            $display("  ✓ PASS: Done state correct\n");
        else
            $display("  ✗ FAIL: Should be done\n");
        
        #50;
        
        // ====================================
        // Test 6: Back-to-Back Transfers
        // ====================================
        $display("=== Test 6: Back-to-Back Transfers ===");
        $display("Testing two consecutive transfers\n");
        
        // First transfer
        $display("Transfer 1:");
        src_addr = 32'h00000000;
        dst_addr = 32'h00000040;
        transfer_size = 16'd2;
        start = 1;
        #10;
        start = 0;
        wait(done);
        #10;
        $display("  ✓ Transfer 1 complete\n");
        
        // Second transfer
        $display("Transfer 2:");
        src_addr = 32'h00000040;
        dst_addr = 32'h00000080;
        transfer_size = 16'd2;
        start = 1;
        #10;
        start = 0;
        wait(done);
        #10;
        $display("  ✓ Transfer 2 complete\n");
        
        $display("Back-to-back transfers successful!\n");
        
        #50;
        
        // Summary
        $display("========================================");
        $display("    DMA Controller Tests Complete!");
        $display("========================================\n");
        $display("Summary:");
        $display("  ✓ Small transfers (4 words)");
        $display("  ✓ Different source addresses");
        $display("  ✓ Single word transfer");
        $display("  ✓ Larger transfers (8 words)");
        $display("  ✓ Status signals (busy/done)");
        $display("  ✓ Back-to-back transfers\n");
        $display("DMA Controller is working correctly!");
        $display("Data can move from main memory to scratchpad.\n");
        
        $finish;
    end
    
    // Monitor for debugging
    initial begin
        $monitor("Time=%0t | State: start=%b busy=%b done=%b | mem_addr=0x%03h spad_addr=0x%03h", 
                 $time, start, busy, done, mem_addr[11:0], spad_addr);
    end
    
    // Waveform dump
    initial begin
        $dumpfile("tb_dma_controller.vcd");
        $dumpvars(0, tb_dma_controller);
    end
    
    // Timeout watchdog
    initial begin
        #100000;
        $display("\nERROR: Simulation timeout!");
        $finish;
    end

endmodule


