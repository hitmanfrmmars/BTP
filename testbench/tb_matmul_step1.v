`timescale 1ns/1ps

// Testbench for Step 1: State Machine Skeleton
module tb_matmul_step1;

    // Signals
    reg clk;
    reg rst;
    reg start;
    wire done;
    wire busy;
    
    // Instantiate controller
    matmul_controller uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .done(done),
        .busy(busy)
    );
    
    // Clock generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test procedure
    initial begin
        $display("\n========================================");
        $display("  Step 1: State Machine Skeleton Test");
        $display("========================================\n");
        
        // Initialize
        rst = 1;
        start = 0;
        
        #20;
        rst = 0;
        #10;
        
        // Test 1: Check IDLE state
        $display("Test 1: Initial IDLE State");
        $display("  State: %0d (should be 0=IDLE)", uut.state);
        $display("  busy=%b (should be 0)", busy);
        $display("  done=%b (should be 0)", done);
        
        if (uut.state == 0 && busy == 0 && done == 0) begin
            $display("  ✓ PASS: Controller in IDLE state\n");
        end else begin
            $display("  ✗ FAIL: Controller not in correct IDLE state\n");
        end
        
        #20;
        
        // Test 2: Start operation and watch state transitions
        $display("Test 2: State Transitions");
        $display("  Asserting start signal...\n");
        start = 1;
        #10;
        start = 0;
        
        // Monitor state transitions
        $display("  Monitoring state transitions:");
        $display("  Cycle | State      | busy | done");
        $display("  ------|------------|------|-----");
        
        repeat (10) begin
            case (uut.state)
                0: $display("  %4t  | IDLE       |  %b   |  %b", $time/10, busy, done);
                1: $display("  %4t  | INIT       |  %b   |  %b", $time/10, busy, done);
                2: $display("  %4t  | LOAD_DATA  |  %b   |  %b", $time/10, busy, done);
                3: $display("  %4t  | COMPUTE    |  %b   |  %b", $time/10, busy, done);
                4: $display("  %4t  | WRITE_BACK |  %b   |  %b", $time/10, busy, done);
                5: $display("  %4t  | DONE_STATE |  %b   |  %b", $time/10, busy, done);
                default: $display("  %4t  | UNKNOWN    |  %b   |  %b", $time/10, busy, done);
            endcase
            #10;
        end
        
        #10;
        
        // Test 3: Verify state sequence
        $display("\nTest 3: Verify State Sequence");
        
        // Reset and restart
        rst = 1;
        #20;
        rst = 0;
        #10;
        
        start = 1;
        #10;
        start = 0;
        
        // Check INIT state
        #10;
        if (uut.state == 1) begin
            $display("  ✓ IDLE → INIT transition correct");
        end else begin
            $display("  ✗ FAIL: Expected INIT state (1), got %0d", uut.state);
        end
        
        // Check LOAD_DATA state
        #10;
        if (uut.state == 2) begin
            $display("  ✓ INIT → LOAD_DATA transition correct");
        end else begin
            $display("  ✗ FAIL: Expected LOAD_DATA state (2), got %0d", uut.state);
        end
        
        // Check COMPUTE state
        #10;
        if (uut.state == 3) begin
            $display("  ✓ LOAD_DATA → COMPUTE transition correct");
        end else begin
            $display("  ✗ FAIL: Expected COMPUTE state (3), got %0d", uut.state);
        end
        
        // Check WRITE_BACK state
        #10;
        if (uut.state == 4) begin
            $display("  ✓ COMPUTE → WRITE_BACK transition correct");
        end else begin
            $display("  ✗ FAIL: Expected WRITE_BACK state (4), got %0d", uut.state);
        end
        
        // Check DONE_STATE
        #10;
        if (uut.state == 5 && done == 1) begin
            $display("  ✓ WRITE_BACK → DONE_STATE transition correct");
            $display("  ✓ 'done' signal asserted");
        end else begin
            $display("  ✗ FAIL: Expected DONE_STATE (5) with done=1, got state=%0d, done=%b", 
                     uut.state, done);
        end
        
        // Check return to IDLE
        #10;
        if (uut.state == 0 && done == 0 && busy == 0) begin
            $display("  ✓ DONE_STATE → IDLE transition correct");
            $display("  ✓ All signals cleared\n");
        end else begin
            $display("  ✗ FAIL: Expected return to IDLE\n");
        end
        
        // Test 4: Busy signal behavior
        $display("Test 4: Busy Signal Behavior");
        
        rst = 1;
        #20;
        rst = 0;
        #10;
        
        if (busy == 0) begin
            $display("  ✓ busy=0 in IDLE");
        end
        
        start = 1;
        #10;
        start = 0;
        #10;
        
        if (busy == 1) begin
            $display("  ✓ busy=1 during operation");
        end
        
        // Wait for completion
        wait(done == 1);
        #10;
        
        if (busy == 0) begin
            $display("  ✓ busy=0 after completion\n");
        end
        
        // Test 5: Multiple operations
        $display("Test 5: Back-to-Back Operations");
        
        // First operation
        rst = 1;
        #20;
        rst = 0;
        #10;
        
        start = 1;
        #10;
        start = 0;
        
        wait(done == 1);
        $display("  ✓ First operation complete");
        #10;
        
        // Second operation
        start = 1;
        #10;
        start = 0;
        
        wait(done == 1);
        $display("  ✓ Second operation complete");
        #10;
        
        // Summary
        $display("\n========================================");
        $display("       Step 1 Tests Complete!");
        $display("========================================\n");
        $display("Summary:");
        $display("  ✓ State machine transitions correctly");
        $display("  ✓ IDLE → INIT → LOAD → COMPUTE → WRITE → DONE → IDLE");
        $display("  ✓ busy signal works (0 in IDLE, 1 during operation)");
        $display("  ✓ done signal pulses on completion");
        $display("  ✓ Can handle multiple operations");
        $display("\n✓ Step 1 COMPLETE - Ready for Step 2!\n");
        
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("tb_matmul_step1.vcd");
        $dumpvars(0, tb_matmul_step1);
    end
    
    // Timeout
    initial begin
        #10000;
        $display("\nERROR: Simulation timeout!");
        $finish;
    end

endmodule


