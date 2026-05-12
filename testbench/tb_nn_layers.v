// SoC-level testbench for NN layers demo firmware
// Boots PicoRV32, runs FC + Conv2D layer tests, reports SW vs HW cycle counts
`timescale 1ns/1ps

module tb_nn_layers;

    reg clk, resetn;
    wire trap, accel_busy, accel_done, irq;
    wire debug_wr;
    wire [31:0] debug_data;

    gemm_soc_top #(
        .MEM_WORDS     (32768),
        .FIRMWARE_FILE ("nn_layers.hex"),
        .ARRAY_SIZE    (8),
        .ACC_WIDTH     (48),
        .STACKADDR     (32'h0002_0000),
        .PROGADDR_RESET(32'h0000_0000)
    ) dut (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (trap),
        .accel_busy(accel_busy),
        .accel_done(accel_done),
        .irq       (irq),
        .debug_wr  (debug_wr),
        .debug_data(debug_data)
    );

    always #5 clk = ~clk;

    reg        test_done;
    reg [31:0] layer_type;
    reg [31:0] hw_cyc, sw_cyc;
    integer    fc_pass, fc_fail, conv_pass, conv_fail;
    integer    debug_seq;

    always @(posedge clk) begin
        if (debug_wr) begin
            $display("[NN] t=%0t  data=0x%08X", $time, debug_data);

            if (debug_data == 32'hBBBB0001) begin
                layer_type = debug_data;
                debug_seq  = 0;
                $display("  >> FC Layer Test Started");
            end
            else if (debug_data == 32'hBBBB0002) begin
                layer_type = debug_data;
                debug_seq  = 0;
                $display("  >> Conv2D Layer Test Started");
            end
            else if (debug_data == 32'h0000DEAD) begin
                test_done = 1'b1;
            end
            else if (debug_data == 32'h0000600D) begin
                if (layer_type == 32'hBBBB0001) begin
                    fc_pass = fc_pass + 1;
                    $display("  >> FC Layer: PASSED (HW=%0d cyc, SW=%0d cyc, speedup=%.1fx)",
                             hw_cyc, sw_cyc, $itor(sw_cyc) / $itor(hw_cyc > 0 ? hw_cyc : 1));
                end else begin
                    conv_pass = conv_pass + 1;
                    $display("  >> Conv2D Layer: PASSED (HW=%0d cyc, SW=%0d cyc, speedup=%.1fx)",
                             hw_cyc, sw_cyc, $itor(sw_cyc) / $itor(hw_cyc > 0 ? hw_cyc : 1));
                end
            end
            else if (debug_data == 32'h0000FA11) begin
                if (layer_type == 32'hBBBB0001) begin
                    fc_fail = fc_fail + 1;
                    $display("  >> FC Layer: FAILED <<<");
                end else begin
                    conv_fail = conv_fail + 1;
                    $display("  >> Conv2D Layer: FAILED <<<");
                end
            end
            else begin
                if (debug_seq == 0) begin
                    hw_cyc = debug_data;
                    debug_seq = 1;
                end else if (debug_seq == 1) begin
                    sw_cyc = debug_data;
                    debug_seq = 2;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (trap) begin
            $display("[FATAL] PicoRV32 trapped at t=%0t, PC=%08X", $time,
                     dut.u_cpu.mem_addr);
            $finish;
        end
    end

    initial begin
        $dumpfile("tb_nn_layers.vcd");
        $dumpvars(0, tb_nn_layers);

        clk       = 0;
        resetn    = 0;
        test_done = 0;
        fc_pass   = 0;  fc_fail  = 0;
        conv_pass = 0;  conv_fail = 0;
        hw_cyc    = 0;  sw_cyc   = 0;
        layer_type = 0;
        debug_seq  = 0;

        repeat (20) @(posedge clk);
        resetn = 1;

        $display("=== Neural Network Layer Demo (FC + Conv2D, 8x8 array) ===");
        $display("");

        fork
            begin wait (test_done); end
            begin
                repeat (10_000_000) @(posedge clk);
                $display("[TIMEOUT] NN layer test did not complete in 10M cycles.");
                $finish;
            end
        join_any
        disable fork;

        repeat (10) @(posedge clk);

        $display("");
        $display("=== NN LAYERS SUMMARY ===");
        $display("  FC Layer:    %0d passed, %0d failed", fc_pass, fc_fail);
        $display("  Conv2D Layer: %0d passed, %0d failed", conv_pass, conv_fail);
        if (fc_fail == 0 && conv_fail == 0 && (fc_pass + conv_pass) > 0)
            $display("  RESULT: ALL PASSED");
        else
            $display("  RESULT: FAILURES DETECTED");
        $display("=========================");
        $finish;
    end

endmodule
