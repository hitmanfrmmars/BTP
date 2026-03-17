// GEMM Accelerator Memory-Mapped Register File
// AXI4-Lite slave interface for RISC-V configuration
// Register map:
//   0x00 CTRL     [0]=start, [1]=mode(int8/int16), [2]=irq_enable
//   0x04 STATUS   [0]=busy, [1]=done, [2]=error, [3]=overflow
//   0x08 DIM_MK   [31:16]=M, [15:0]=K
//   0x0C DIM_N    [15:0]=N
//   0x10 SRC_A    base address for matrix A
//   0x14 SRC_B    base address for matrix B
//   0x18 DST_C    base address for matrix C
//   0x1C STRIDE_A row stride for A (bytes)
//   0x20 STRIDE_B row stride for B (bytes)
//   0x24 STRIDE_C row stride for C (bytes)
//   0x28 CYCLES   cycle counter (read-only, cleared on start)
module gemm_regfile #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter REG_ADDR_BITS = 6   // 64 bytes address space
) (
    input wire clk,
    input wire rst,

    // AXI4-Lite slave write channel
    input wire [REG_ADDR_BITS-1:0] wr_addr,
    input wire [DATA_WIDTH-1:0]    wr_data,
    input wire                     wr_en,

    // AXI4-Lite slave read channel
    input wire [REG_ADDR_BITS-1:0] rd_addr,
    output reg [DATA_WIDTH-1:0]    rd_data,
    input wire                     rd_en,

    // Outputs to accelerator
    output wire        cfg_start,
    output wire        cfg_mode,
    output wire        cfg_irq_en,
    output wire [15:0] cfg_dim_m,
    output wire [15:0] cfg_dim_k,
    output wire [15:0] cfg_dim_n,
    output wire [ADDR_WIDTH-1:0] cfg_src_a,
    output wire [ADDR_WIDTH-1:0] cfg_src_b,
    output wire [ADDR_WIDTH-1:0] cfg_dst_c,
    output wire [15:0] cfg_stride_a,
    output wire [15:0] cfg_stride_b,
    output wire [15:0] cfg_stride_c,

    // Status inputs from accelerator
    input wire accel_busy,
    input wire accel_done,
    input wire accel_error,
    input wire accel_overflow
);

    // Register storage
    reg [DATA_WIDTH-1:0] reg_ctrl;
    reg [DATA_WIDTH-1:0] reg_dim_mk;
    reg [DATA_WIDTH-1:0] reg_dim_n;
    reg [DATA_WIDTH-1:0] reg_src_a;
    reg [DATA_WIDTH-1:0] reg_src_b;
    reg [DATA_WIDTH-1:0] reg_dst_c;
    reg [DATA_WIDTH-1:0] reg_stride_a;
    reg [DATA_WIDTH-1:0] reg_stride_b;
    reg [DATA_WIDTH-1:0] reg_stride_c;
    reg [DATA_WIDTH-1:0] reg_cycles;

    // Start is self-clearing (pulse)
    reg start_pulse;

    // Latched done flag (persists until next start)
    reg done_latched;
    always @(posedge clk) begin
        if (rst)
            done_latched <= 1'b0;
        else if (start_pulse)
            done_latched <= 1'b0;
        else if (accel_done)
            done_latched <= 1'b1;
    end

    // Cycle counter
    always @(posedge clk) begin
        if (rst)
            reg_cycles <= 32'd0;
        else if (start_pulse)
            reg_cycles <= 32'd0;
        else if (accel_busy)
            reg_cycles <= reg_cycles + 1;
    end

    // Write logic
    always @(posedge clk) begin
        if (rst) begin
            reg_ctrl     <= 32'd0;
            reg_dim_mk   <= 32'd0;
            reg_dim_n    <= 32'd0;
            reg_src_a    <= 32'd0;
            reg_src_b    <= 32'd0;
            reg_dst_c    <= 32'd0;
            reg_stride_a <= 32'd0;
            reg_stride_b <= 32'd0;
            reg_stride_c <= 32'd0;
            start_pulse  <= 1'b0;
        end else begin
            start_pulse <= 1'b0; // self-clearing

            if (wr_en) begin
                case (wr_addr[5:0])
                    6'h00: begin
                        reg_ctrl    <= wr_data;
                        start_pulse <= wr_data[0]; // bit 0 = start
                    end
                    6'h08: reg_dim_mk   <= wr_data;
                    6'h0C: reg_dim_n    <= wr_data;
                    6'h10: reg_src_a    <= wr_data;
                    6'h14: reg_src_b    <= wr_data;
                    6'h18: reg_dst_c    <= wr_data;
                    6'h1C: reg_stride_a <= wr_data;
                    6'h20: reg_stride_b <= wr_data;
                    6'h24: reg_stride_c <= wr_data;
                endcase
            end

            // Auto-clear start bit after pulse
            if (start_pulse)
                reg_ctrl[0] <= 1'b0;
        end
    end

    // Read logic
    always @(*) begin
        rd_data = 32'd0;
        if (rd_en) begin
            case (rd_addr[5:0])
                6'h00: rd_data = reg_ctrl;
                6'h04: rd_data = {28'd0, accel_overflow, accel_error, done_latched, accel_busy};
                6'h08: rd_data = reg_dim_mk;
                6'h0C: rd_data = reg_dim_n;
                6'h10: rd_data = reg_src_a;
                6'h14: rd_data = reg_src_b;
                6'h18: rd_data = reg_dst_c;
                6'h1C: rd_data = reg_stride_a;
                6'h20: rd_data = reg_stride_b;
                6'h24: rd_data = reg_stride_c;
                6'h28: rd_data = reg_cycles;
                default: rd_data = 32'd0;
            endcase
        end
    end

    // Output assignments
    assign cfg_start    = start_pulse;
    assign cfg_mode     = reg_ctrl[1];
    assign cfg_irq_en   = reg_ctrl[2];
    assign cfg_dim_m    = reg_dim_mk[31:16];
    assign cfg_dim_k    = reg_dim_mk[15:0];
    assign cfg_dim_n    = reg_dim_n[15:0];
    assign cfg_src_a    = reg_src_a;
    assign cfg_src_b    = reg_src_b;
    assign cfg_dst_c    = reg_dst_c;
    assign cfg_stride_a = reg_stride_a[15:0];
    assign cfg_stride_b = reg_stride_b[15:0];
    assign cfg_stride_c = reg_stride_c[15:0];

endmodule
