// Testbench for scratchpad_mem (dual-port SRAM)
// Tests: basic write/read, dual-port concurrent access, byte addressing,
// conflict test, read-during-write, boundary address
`timescale 1ns/1ps

module tb_scratchpad_mem;
    parameter ADDR_WIDTH = 10;
    parameter DATA_WIDTH = 32;

    reg clk, rst;
    reg [ADDR_WIDTH-1:0] addr_a, addr_b;
    reg [DATA_WIDTH-1:0] wdata_a, wdata_b;
    reg we_a, re_a, we_b, re_b;
    wire [DATA_WIDTH-1:0] rdata_a, rdata_b;

    integer errors = 0;

    scratchpad_mem #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .addr_a(addr_a), .wdata_a(wdata_a), .we_a(we_a), .re_a(re_a), .rdata_a(rdata_a),
        .addr_b(addr_b), .wdata_b(wdata_b), .we_b(we_b), .re_b(re_b), .rdata_b(rdata_b)
    );

    always #5 clk = ~clk;

    task check(input [DATA_WIDTH-1:0] actual, expected, input [159:0] msg);
        if (actual !== expected) begin
            $display("FAIL: %0s - got %h, expected %h", msg, actual, expected);
            errors = errors + 1;
        end else begin
            $display("PASS: %0s = %h", msg, actual);
        end
    endtask

    initial begin
        $dumpfile("tb_scratchpad_mem.vcd");
        $dumpvars(0, tb_scratchpad_mem);

        clk = 0; rst = 1;
        addr_a = 0; addr_b = 0; wdata_a = 0; wdata_b = 0;
        we_a = 0; re_a = 0; we_b = 0; re_b = 0;

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;

        // Test 1: Write via Port A, read via Port A
        $display("\n=== Test 1: Port A write + read ===");
        addr_a = 10'h000; wdata_a = 32'hDEADBEEF; we_a = 1;
        @(posedge clk); #1;
        we_a = 0; re_a = 1; addr_a = 10'h000;
        @(posedge clk); #1;
        re_a = 0;
        check(rdata_a, 32'hDEADBEEF, "Port A read-after-write");

        // Test 2: Write via Port A, read via Port B (dual-port)
        $display("\n=== Test 2: Port A write, Port B read ===");
        addr_a = 10'h004; wdata_a = 32'hCAFEBABE; we_a = 1;
        @(posedge clk); #1;
        we_a = 0; addr_b = 10'h004; re_b = 1;
        @(posedge clk); #1;
        re_b = 0;
        check(rdata_b, 32'hCAFEBABE, "Port B reads Port A's data");

        // Test 3: Simultaneous writes to different addresses
        $display("\n=== Test 3: Simultaneous dual-port writes ===");
        addr_a = 10'h008; wdata_a = 32'h11111111; we_a = 1;
        addr_b = 10'h00C; wdata_b = 32'h22222222; we_b = 1;
        @(posedge clk); #1;
        we_a = 0; we_b = 0;
        addr_a = 10'h008; re_a = 1;
        addr_b = 10'h00C; re_b = 1;
        @(posedge clk); #1;
        re_a = 0; re_b = 0;
        check(rdata_a, 32'h11111111, "Port A after dual write");
        check(rdata_b, 32'h22222222, "Port B after dual write");

        // Test 4: Multiple sequential writes
        $display("\n=== Test 4: Sequential writes ===");
        addr_a = 10'h010; wdata_a = 32'hAAAAAAAA; we_a = 1;
        @(posedge clk); #1;
        addr_a = 10'h014; wdata_a = 32'hBBBBBBBB;
        @(posedge clk); #1;
        addr_a = 10'h018; wdata_a = 32'hCCCCCCCC;
        @(posedge clk); #1;
        addr_a = 10'h01C; wdata_a = 32'hDDDDDDDD;
        @(posedge clk); #1;
        we_a = 0;

        // Read them all back via Port B
        addr_b = 10'h010; re_b = 1;
        @(posedge clk); #1;
        check(rdata_b, 32'hAAAAAAAA, "Seq read 0");
        addr_b = 10'h014;
        @(posedge clk); #1;
        check(rdata_b, 32'hBBBBBBBB, "Seq read 1");
        addr_b = 10'h018;
        @(posedge clk); #1;
        check(rdata_b, 32'hCCCCCCCC, "Seq read 2");
        addr_b = 10'h01C;
        @(posedge clk); #1;
        re_b = 0;
        check(rdata_b, 32'hDDDDDDDD, "Seq read 3");

        // Test 5: Boundary address test (last word, addr 0x3FC = word 255)
        $display("\n=== Test 5: Boundary address (last word 0x3FC) ===");
        addr_a = 10'h3FC; wdata_a = 32'hFEEDFACE; we_a = 1;
        @(posedge clk); #1;
        we_a = 0; re_a = 1; addr_a = 10'h3FC;
        @(posedge clk); #1;
        re_a = 0;
        check(rdata_a, 32'hFEEDFACE, "Boundary addr 0x3FC write/read");

        // Also verify via Port B
        addr_b = 10'h3FC; re_b = 1;
        @(posedge clk); #1;
        re_b = 0;
        check(rdata_b, 32'hFEEDFACE, "Boundary addr 0x3FC via Port B");

        // Verify addr 0x000 still intact from Test 1
        addr_a = 10'h000; re_a = 1;
        @(posedge clk); #1;
        re_a = 0;
        check(rdata_a, 32'hDEADBEEF, "Addr 0x000 still intact");

        // Test 6: Simultaneous write to same address from both ports (conflict)
        $display("\n=== Test 6: Write conflict (same address, both ports) ===");
        addr_a = 10'h100; wdata_a = 32'hAAAA_0001; we_a = 1;
        addr_b = 10'h100; wdata_b = 32'hBBBB_0002; we_b = 1;
        @(posedge clk); #1;
        we_a = 0; we_b = 0;
        addr_a = 10'h100; re_a = 1;
        @(posedge clk); #1;
        re_a = 0;
        if (rdata_a === 32'hAAAA_0001 || rdata_a === 32'hBBBB_0002) begin
            $display("PASS: Conflict write result = %h (one of two valid values)", rdata_a);
        end else begin
            $display("FAIL: Conflict write result = %h (neither expected value)", rdata_a);
            errors = errors + 1;
        end

        // Test 7: Read-during-write hazard (write and read same address same cycle)
        $display("\n=== Test 7: Read-during-write hazard ===");
        // First, write a known value
        addr_a = 10'h200; wdata_a = 32'h1111_1111; we_a = 1;
        @(posedge clk); #1;
        // Simultaneously write new value and read same address on Port A
        addr_a = 10'h200; wdata_a = 32'h2222_2222; we_a = 1; re_a = 1;
        @(posedge clk); #1;
        we_a = 0; re_a = 0;
        if (rdata_a === 32'h1111_1111 || rdata_a === 32'h2222_2222) begin
            $display("PASS: Read-during-write result = %h (valid)", rdata_a);
        end else begin
            $display("FAIL: Read-during-write result = %h (unexpected)", rdata_a);
            errors = errors + 1;
        end
        // Verify the write took effect
        addr_a = 10'h200; re_a = 1;
        @(posedge clk); #1;
        re_a = 0;
        check(rdata_a, 32'h2222_2222, "Write-during-read value persisted");

        // Summary
        @(posedge clk); @(posedge clk);
        if (errors == 0)
            $display("\n*** ALL SCRATCHPAD TESTS PASSED ***\n");
        else
            $display("\n*** %0d TESTS FAILED ***\n", errors);
        $finish;
    end

endmodule
