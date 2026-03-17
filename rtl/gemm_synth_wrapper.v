// Synthesis wrapper for GEMM Accelerator (standalone, no CPU)
//
// Registers all I/O for realistic timing analysis.
// Vivado synthesizes this as the top module for accelerator-only metrics.
//
module gemm_accel_synth_wrapper #(
    parameter ARRAY_SIZE = 4,
    parameter ACC_WIDTH  = 48
) (
    input  wire        clk,
    input  wire        rst,

    // AXI-Lite config
    input  wire [5:0]  axi_wr_addr,
    input  wire [31:0] axi_wr_data,
    input  wire        axi_wr_en,
    input  wire [5:0]  axi_rd_addr,
    output wire [31:0] axi_rd_data,
    input  wire        axi_rd_en,

    // PCPI
    input  wire        pcpi_valid,
    input  wire [31:0] pcpi_insn,
    input  wire [31:0] pcpi_rs1,
    input  wire [31:0] pcpi_rs2,
    output wire        pcpi_wr,
    output wire [31:0] pcpi_rd,
    output wire        pcpi_wait,
    output wire        pcpi_ready,

    // DMA memory interface
    output wire [31:0] mem_addr,
    output wire        mem_read,
    output wire        mem_write,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_burst_len,
    input  wire [31:0] mem_rdata,
    input  wire        mem_ready,

    output wire        irq,
    output wire        accel_busy,
    output wire        accel_done
);

    // Input registers
    reg [5:0]  r_axi_wr_addr;
    reg [31:0] r_axi_wr_data;
    reg        r_axi_wr_en;
    reg [5:0]  r_axi_rd_addr;
    reg        r_axi_rd_en;
    reg        r_pcpi_valid;
    reg [31:0] r_pcpi_insn;
    reg [31:0] r_pcpi_rs1;
    reg [31:0] r_pcpi_rs2;
    reg [31:0] r_mem_rdata;
    reg        r_mem_ready;

    always @(posedge clk) begin
        r_axi_wr_addr <= axi_wr_addr;
        r_axi_wr_data <= axi_wr_data;
        r_axi_wr_en   <= axi_wr_en;
        r_axi_rd_addr <= axi_rd_addr;
        r_axi_rd_en   <= axi_rd_en;
        r_pcpi_valid   <= pcpi_valid;
        r_pcpi_insn    <= pcpi_insn;
        r_pcpi_rs1     <= pcpi_rs1;
        r_pcpi_rs2     <= pcpi_rs2;
        r_mem_rdata    <= mem_rdata;
        r_mem_ready    <= mem_ready;
    end

    // Output registers
    wire [31:0] w_axi_rd_data;
    wire        w_pcpi_wr, w_pcpi_wait, w_pcpi_ready;
    wire [31:0] w_pcpi_rd;
    wire [31:0] w_mem_addr, w_mem_wdata;
    wire        w_mem_read, w_mem_write;
    wire [3:0]  w_mem_burst_len;
    wire        w_irq, w_busy, w_done;

    reg [31:0] r_axi_rd_data;
    reg        r_pcpi_wr, r_pcpi_wait, r_pcpi_ready;
    reg [31:0] r_pcpi_rd;
    reg [31:0] r_mem_addr, r_mem_wdata;
    reg        r_mem_read, r_mem_write;
    reg [3:0]  r_mem_burst_len;
    reg        r_irq, r_busy, r_done;

    always @(posedge clk) begin
        r_axi_rd_data  <= w_axi_rd_data;
        r_pcpi_wr      <= w_pcpi_wr;
        r_pcpi_rd      <= w_pcpi_rd;
        r_pcpi_wait    <= w_pcpi_wait;
        r_pcpi_ready   <= w_pcpi_ready;
        r_mem_addr     <= w_mem_addr;
        r_mem_read     <= w_mem_read;
        r_mem_write    <= w_mem_write;
        r_mem_wdata    <= w_mem_wdata;
        r_mem_burst_len<= w_mem_burst_len;
        r_irq          <= w_irq;
        r_busy         <= w_busy;
        r_done         <= w_done;
    end

    assign axi_rd_data  = r_axi_rd_data;
    assign pcpi_wr      = r_pcpi_wr;
    assign pcpi_rd      = r_pcpi_rd;
    assign pcpi_wait    = r_pcpi_wait;
    assign pcpi_ready   = r_pcpi_ready;
    assign mem_addr     = r_mem_addr;
    assign mem_read     = r_mem_read;
    assign mem_write    = r_mem_write;
    assign mem_wdata    = r_mem_wdata;
    assign mem_burst_len= r_mem_burst_len;
    assign irq          = r_irq;
    assign accel_busy   = r_busy;
    assign accel_done   = r_done;

    gemm_accelerator_top #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_accel (
        .clk(clk),
        .rst(rst),
        .axi_wr_addr(r_axi_wr_addr),
        .axi_wr_data(r_axi_wr_data),
        .axi_wr_en(r_axi_wr_en),
        .axi_rd_addr(r_axi_rd_addr),
        .axi_rd_data(w_axi_rd_data),
        .axi_rd_en(r_axi_rd_en),
        .pcpi_valid(r_pcpi_valid),
        .pcpi_insn(r_pcpi_insn),
        .pcpi_rs1(r_pcpi_rs1),
        .pcpi_rs2(r_pcpi_rs2),
        .pcpi_wr(w_pcpi_wr),
        .pcpi_rd(w_pcpi_rd),
        .pcpi_wait(w_pcpi_wait),
        .pcpi_ready(w_pcpi_ready),
        .mem_addr(w_mem_addr),
        .mem_read(w_mem_read),
        .mem_write(w_mem_write),
        .mem_wdata(w_mem_wdata),
        .mem_burst_len(w_mem_burst_len),
        .mem_rdata(r_mem_rdata),
        .mem_ready(r_mem_ready),
        .irq(w_irq),
        .accel_busy(w_busy),
        .accel_done(w_done)
    );

endmodule


// Synthesis wrapper for the full SoC (PicoRV32 + GEMM + memory)
//
// Minimal I/O: clk, resetn, status outputs.
// Internal memory is inferred as block RAM by Vivado.
//
module gemm_soc_synth_wrapper (
    input  wire clk,
    input  wire resetn,
    output wire trap,
    output wire accel_busy,
    output wire accel_done,
    output wire irq
);

    wire       debug_wr;
    wire [31:0] debug_data;

    gemm_soc_synth_top #(
        .MEM_WORDS(32768),
        .ARRAY_SIZE(4),
        .ACC_WIDTH(48),
        .STACKADDR(32'h0002_0000),
        .PROGADDR_RESET(32'h0000_0000)
    ) u_soc (
        .clk(clk),
        .resetn(resetn),
        .trap(trap),
        .accel_busy(accel_busy),
        .accel_done(accel_done),
        .irq(irq),
        .debug_wr(debug_wr),
        .debug_data(debug_data)
    );

endmodule
