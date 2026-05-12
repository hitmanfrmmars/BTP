// SoC-level testbench for complete NN inference pipeline
// Conv2D -> ReLU -> Conv2D -> ReLU -> FC -> Argmax
// Verifies each layer's output against Python golden model
`timescale 1ns/1ps

module tb_nn_inference;

    reg clk, resetn;
    wire trap, accel_busy, accel_done, irq;
    wire debug_wr;
    wire [31:0] debug_data;

    gemm_soc_top #(
        .MEM_WORDS     (32768),
        .FIRMWARE_FILE ("nn_inference.hex"),
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
    reg [31:0] current_layer;
    integer    layer_pass, layer_fail;
    integer    debug_seq;
    integer    t_layer_start;

    always @(posedge clk) begin
        if (debug_wr) begin
            // Layer start markers
            if (debug_data == 32'hCCCC0001) begin
                current_layer = debug_data;
                t_layer_start = $time;
                debug_seq = 0;
                $display("");
                $display("[NN] === Conv1 Layer (8x8x1 -> 6x6x4) ===");
                $display("[NN]   im2col: 36x9 -> GEMM 36x9 * 9x4 = 36x4");
                $display("[NN]   DMA strides: a=12(padded), b=4, c=4");
            end
            else if (debug_data == 32'hCCCC0002) begin
                current_layer = debug_data;
                t_layer_start = $time;
                debug_seq = 0;
                $display("");
                $display("[NN] === Conv2 Layer (6x6x4 -> 4x4x8) ===");
                $display("[NN]   im2col: 16x36 -> GEMM 16x36 * 36x8 = 16x8");
                $display("[NN]   DMA strides: a=36, b=8, c=8");
            end
            else if (debug_data == 32'hCCCC0003) begin
                current_layer = debug_data;
                t_layer_start = $time;
                debug_seq = 0;
                $display("");
                $display("[NN] === FC Layer (128 -> 4) ===");
                $display("[NN]   GEMM: 1x128 * 128x4 = 1x4");
                $display("[NN]   DMA strides: a=128, b=4, c=4");
            end
            else if (debug_data == 32'hCCCC0004) begin
                current_layer = debug_data;
                debug_seq = 0;
                $display("");
                $display("[NN] === Classification (Argmax) ===");
            end
            // Done
            else if (debug_data == 32'h0000DEAD) begin
                test_done = 1'b1;
            end
            // Pass/Fail
            else if (debug_data == 32'h0000600D) begin
                layer_pass = layer_pass + 1;
                if (current_layer == 32'hCCCC0001)
                    $display("[NN]   Conv1: PASSED  (%0d ns)", $time - t_layer_start);
                else if (current_layer == 32'hCCCC0002)
                    $display("[NN]   Conv2: PASSED  (%0d ns)", $time - t_layer_start);
                else if (current_layer == 32'hCCCC0003)
                    $display("[NN]   FC:    PASSED  (%0d ns)", $time - t_layer_start);
                else if (current_layer == 32'hCCCC0004)
                    $display("[NN]   Classification: CORRECT");
            end
            else if (debug_data == 32'h0000FA11) begin
                layer_fail = layer_fail + 1;
                $display("[NN]   *** FAILED ***");
            end
            // Data values
            else begin
                if (current_layer == 32'hCCCC0004) begin
                    if (debug_seq == 0) begin
                        $display("[NN]   Predicted class: %0d", debug_data);
                        debug_seq = 1;
                    end
                    else if (debug_seq >= 1 && debug_seq <= 4) begin
                        $display("[NN]   Score[%0d] = %0d (0x%02X)",
                                 debug_seq - 1, debug_data, debug_data);
                        debug_seq = debug_seq + 1;
                    end
                end
                else begin
                    if (debug_seq == 0) begin
                        $display("[NN]   Output checksum: 0x%08X", debug_data);
                        debug_seq = 1;
                    end
                end
            end
        end
    end

    always @(posedge clk) begin
        if (trap) begin
            $display("[FATAL] PicoRV32 trapped at t=%0t", $time);
            $finish;
        end
    end

    initial begin
        clk        = 0;
        resetn     = 0;
        test_done  = 0;
        layer_pass = 0;
        layer_fail = 0;
        debug_seq  = 0;
        current_layer = 0;
        t_layer_start = 0;

        repeat (20) @(posedge clk);
        resetn = 1;

        $display("===========================================================");
        $display(" Complete Neural Network Inference on GEMM Accelerator");
        $display("  Conv2D(1->4) -> ReLU -> Conv2D(4->8) -> ReLU -> FC(128->4)");
        $display("  8x8 MAC array, golden model verification");
        $display("===========================================================");

        fork
            begin wait (test_done); end
            begin
                repeat (30_000_000) @(posedge clk);
                $display("[TIMEOUT] NN inference did not complete in 30M cycles.");
                $finish;
            end
        join_any
        disable fork;

        repeat (10) @(posedge clk);

        $display("");
        $display("===========================================================");
        $display(" NN INFERENCE SUMMARY");
        $display("  Layers passed:  %0d / 4", layer_pass);
        $display("  Layers failed:  %0d", layer_fail);
        if (layer_fail == 0 && layer_pass == 4)
            $display("  RESULT: COMPLETE NN INFERENCE PASSED");
        else
            $display("  RESULT: FAILURES DETECTED");
        $display("===========================================================");
        $finish;
    end

endmodule
