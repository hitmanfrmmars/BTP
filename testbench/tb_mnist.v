// SoC testbench: Real MNIST inference with TFLite-quantized weights
`timescale 1ns/1ps

module tb_mnist;
    reg clk, resetn;
    wire trap, accel_busy, accel_done, irq;
    wire debug_wr;
    wire [31:0] debug_data;

    gemm_soc_top #(
        .MEM_WORDS     (32768),
        .FIRMWARE_FILE ("mnist_inference.hex"),
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

    reg test_done;
    integer gemm_pass, gemm_fail, cur_img;

    always @(posedge clk) begin
        if (debug_wr) begin
            if ((debug_data & 32'hFFFF0000) == 32'hDD010000) begin
                cur_img = debug_data & 32'hFFFF;
                $display("");
                $display("[MNIST] === Image %0d ===", cur_img);
            end
            else if (debug_data == 32'hDD020001)
                $display("[MNIST]   Conv1 GEMM (169x9 * 9x8):");
            else if (debug_data == 32'hDD020002)
                $display("[MNIST]   Conv2 GEMM (36x72 * 72x16):");
            else if (debug_data == 32'hDD020003)
                $display("[MNIST]   FC GEMM (1x576 * 576x10):");
            else if ((debug_data & 32'hFFFF0000) == 32'hDD030000) begin
                $display("[MNIST]   -> Predicted digit: %0d (TFLite reference)",
                         (debug_data >> 8) & 8'hFF);
            end
            else if (debug_data == 32'h0000600D) begin
                $display("[MNIST]     PASS (matches golden)");
                gemm_pass = gemm_pass + 1;
            end
            else if (debug_data == 32'h0000FA11) begin
                $display("[MNIST]     FAILED <<<");
                gemm_fail = gemm_fail + 1;
            end
            else if (debug_data == 32'h0000DEAD)
                test_done = 1;
            else
                $display("[MNIST]     checksum = 0x%08X", debug_data);
        end
    end

    always @(posedge clk) begin
        if (trap) begin
            $display("[FATAL] PicoRV32 trapped at t=%0t", $time);
            $finish;
        end
    end

    initial begin
        clk = 0; resetn = 0; test_done = 0;
        gemm_pass = 0; gemm_fail = 0; cur_img = 0;

        repeat (20) @(posedge clk);
        resetn = 1;

        $display("===========================================================");
        $display(" MNIST Digit Recognition on GEMM Accelerator");
        $display(" TFLite-quantized model (96.6%% accuracy, int8)");
        $display(" Conv2D(1->8) -> ReLU -> Conv2D(8->16) -> ReLU -> FC(576->10)");
        $display("===========================================================");

        fork
            begin wait (test_done); end
            begin
                repeat (100_000_000) @(posedge clk);
                $display("[TIMEOUT] MNIST test did not complete.");
                $finish;
            end
        join_any
        disable fork;

        repeat (10) @(posedge clk);

        $display("");
        $display("===========================================================");
        $display(" MNIST INFERENCE SUMMARY");
        $display("   GEMM layers verified: %0d / %0d", gemm_pass, gemm_pass + gemm_fail);
        $display("   Failures:             %0d", gemm_fail);
        if (gemm_fail == 0 && gemm_pass > 0)
            $display("   RESULT: ALL GEMM LAYERS MATCH GOLDEN MODEL");
        else
            $display("   RESULT: FAILURES DETECTED");
        $display("===========================================================");
        $finish;
    end
endmodule
