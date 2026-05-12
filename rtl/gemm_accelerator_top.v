// GEMM Accelerator Top-Level Integration
// Integrates: register file, tiling engine, DMA engine, double-buffered scratchpad,
//             matmul controller v2, and MAC array v2.
// Bus interfaces: AXI4-Lite slave (config), AXI4 master (main memory DMA).
// Features: clock gating for idle MAC units, interrupt output, cycle counter.
module gemm_accelerator_top #(
    parameter ARRAY_SIZE  = 8,
    parameter ACC_WIDTH   = 48,
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32
) (
    input wire clk,
    input wire rst,

    // AXI4-Lite slave: register configuration from RISC-V
    input wire [5:0]  axi_wr_addr,
    input wire [31:0] axi_wr_data,
    input wire        axi_wr_en,
    input wire [5:0]  axi_rd_addr,
    output wire [31:0] axi_rd_data,
    input wire        axi_rd_en,

    // PicoRV32 PCPI co-processor interface
    input wire        pcpi_valid,
    input wire [31:0] pcpi_insn,
    input wire [31:0] pcpi_rs1,
    input wire [31:0] pcpi_rs2,
    output wire       pcpi_wr,
    output wire [31:0] pcpi_rd,
    output wire       pcpi_wait,
    output wire       pcpi_ready,

    // AXI4 master: main memory interface for DMA
    output wire [ADDR_WIDTH-1:0] mem_addr,
    output wire                  mem_read,
    output wire                  mem_write,
    output wire [DATA_WIDTH-1:0] mem_wdata,
    output wire [3:0]            mem_burst_len,
    input wire [DATA_WIDTH-1:0]  mem_rdata,
    input wire                   mem_ready,

    // Interrupt
    output wire irq,

    // Debug / status
    output wire accel_busy,
    output wire accel_done
);

    // =====================================================
    // Internal wires
    // =====================================================

    // Register file outputs
    wire        cfg_start, cfg_mode, cfg_irq_en, cfg_output_acc32;
    wire [15:0] cfg_dim_m, cfg_dim_k, cfg_dim_n;
    wire [ADDR_WIDTH-1:0] cfg_src_a, cfg_src_b, cfg_dst_c;
    wire [15:0] cfg_stride_a, cfg_stride_b, cfg_stride_c;

    // Tiling engine -> DMA
    wire        tile_dma_start, tile_dma_dir;
    wire [ADDR_WIDTH-1:0] tile_dma_src, tile_dma_dst;
    wire [15:0] tile_dma_xcnt, tile_dma_ycnt, tile_dma_sstride, tile_dma_dstride;
    wire [3:0]  tile_dma_burst_len;
    wire        dma_done_w;

    // Tiling engine -> matmul controller
    wire        tile_matmul_start, tile_matmul_mode, tile_matmul_output_acc32;
    wire [9:0]  tile_matmul_a_base, tile_matmul_b_base, tile_matmul_c_base;
    wire        tile_matmul_accumulate;
    wire [3:0]  tile_matmul_eff_rows, tile_matmul_eff_k;
    wire [9:0]  tile_matmul_spad_stride;
    wire        matmul_done_w;

    // Double-buffer swap
    wire        swap_banks_w;

    // DMA <-> double-buffered scratchpad
    wire [9:0]  dma_spad_addr;
    wire [31:0] dma_spad_wdata;
    wire        dma_spad_we, dma_spad_re;
    wire [31:0] dma_spad_rdata;

    // Matmul controller <-> double-buffered scratchpad
    wire [9:0]  ctrl_spad_addr;
    wire [31:0] ctrl_spad_wdata;
    wire        ctrl_spad_we, ctrl_spad_re;
    wire [31:0] ctrl_spad_rdata;

    // Matmul controller <-> MAC array
    wire [15:0] mac_a_col [0:ARRAY_SIZE-1];
    wire [15:0] mac_b_row [0:ARRAY_SIZE-1];
    wire        mac_enable, mac_clear_acc;
    wire [ACC_WIDTH-1:0] mac_result [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire                 mac_valid  [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire                 mac_ovf    [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    // Tiling engine status
    wire tile_done, tile_busy;

    // PCPI adapter -> register file
    wire [5:0]  pcpi_reg_wr_addr, pcpi_reg_rd_addr;
    wire [31:0] pcpi_reg_wr_data;
    wire        pcpi_reg_wr_en, pcpi_reg_rd_en;

    // Register file mux: AXI-Lite or PCPI adapter (PCPI takes priority)
    wire [5:0]  rf_wr_addr = pcpi_reg_wr_en ? pcpi_reg_wr_addr : axi_wr_addr;
    wire [31:0] rf_wr_data = pcpi_reg_wr_en ? pcpi_reg_wr_data : axi_wr_data;
    wire        rf_wr_en   = pcpi_reg_wr_en | axi_wr_en;
    wire [5:0]  rf_rd_addr = pcpi_reg_rd_en ? pcpi_reg_rd_addr : axi_rd_addr;
    wire        rf_rd_en   = pcpi_reg_rd_en | axi_rd_en;

    // DMA raw interrupt (gated by cfg_irq_en before output)
    wire dma_irq_raw;
    assign irq = dma_irq_raw & cfg_irq_en;

    // Overall status
    assign accel_busy = tile_busy;
    assign accel_done = tile_done;

    // Clock gating: use negedge-registered enable for glitch-free gated clock.
    // For FPGA/simulation safety, the MAC array uses clk directly and
    // relies on the `enable` port to gate computation.
    wire mac_clk = clk;

    // =====================================================
    // Register File
    // =====================================================
    gemm_regfile #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_regfile (
        .clk(clk), .rst(rst),
        .wr_addr(rf_wr_addr), .wr_data(rf_wr_data), .wr_en(rf_wr_en),
        .rd_addr(rf_rd_addr), .rd_data(axi_rd_data), .rd_en(rf_rd_en),
        .cfg_start(cfg_start), .cfg_mode(cfg_mode), .cfg_irq_en(cfg_irq_en), .cfg_output_acc32(cfg_output_acc32),
        .cfg_dim_m(cfg_dim_m), .cfg_dim_k(cfg_dim_k), .cfg_dim_n(cfg_dim_n),
        .cfg_src_a(cfg_src_a), .cfg_src_b(cfg_src_b), .cfg_dst_c(cfg_dst_c),
        .cfg_stride_a(cfg_stride_a), .cfg_stride_b(cfg_stride_b), .cfg_stride_c(cfg_stride_c),
        .accel_busy(tile_busy), .accel_done(tile_done),
        .accel_error(1'b0), .accel_overflow(mac_ovf[0][0])
    );

    // =====================================================
    // PicoRV32 PCPI Adapter
    // =====================================================
    gemm_pcpi_adapter u_pcpi (
        .clk(clk), .resetn(~rst),
        .pcpi_valid(pcpi_valid), .pcpi_insn(pcpi_insn),
        .pcpi_rs1(pcpi_rs1), .pcpi_rs2(pcpi_rs2),
        .pcpi_wr(pcpi_wr), .pcpi_rd(pcpi_rd),
        .pcpi_wait(pcpi_wait), .pcpi_ready(pcpi_ready),
        .reg_wr_addr(pcpi_reg_wr_addr), .reg_wr_data(pcpi_reg_wr_data), .reg_wr_en(pcpi_reg_wr_en),
        .reg_rd_addr(pcpi_reg_rd_addr), .reg_rd_data(axi_rd_data), .reg_rd_en(pcpi_reg_rd_en),
        .accel_done(tile_done)
    );

    // =====================================================
    // Tiling Engine
    // =====================================================
    tiling_engine #(
        .TILE_SIZE(ARRAY_SIZE),
        .MACRO_TILE_SIZE(ARRAY_SIZE),
        .ARRAY_SIZE(ARRAY_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_tiling (
        .clk(clk), .rst(rst),
        .start(cfg_start), .mode(cfg_mode), .output_acc32(cfg_output_acc32),
        .dim_m(cfg_dim_m), .dim_k(cfg_dim_k), .dim_n(cfg_dim_n),
        .src_a(cfg_src_a), .src_b(cfg_src_b), .dst_c(cfg_dst_c),
        .stride_a(cfg_stride_a), .stride_b(cfg_stride_b), .stride_c(cfg_stride_c),
        .done(tile_done), .busy(tile_busy),
        .dma_start(tile_dma_start), .dma_direction(tile_dma_dir),
        .dma_src_addr(tile_dma_src), .dma_dst_addr(tile_dma_dst),
        .dma_x_count(tile_dma_xcnt), .dma_y_count(tile_dma_ycnt),
        .dma_src_stride(tile_dma_sstride), .dma_dst_stride(tile_dma_dstride),
        .dma_burst_len(tile_dma_burst_len),
        .dma_done(dma_done_w),
        .matmul_start(tile_matmul_start), .matmul_mode(tile_matmul_mode),
        .matmul_a_base(tile_matmul_a_base), .matmul_b_base(tile_matmul_b_base),
        .matmul_c_base(tile_matmul_c_base), .matmul_accumulate(tile_matmul_accumulate),
        .matmul_eff_rows(tile_matmul_eff_rows), .matmul_eff_k(tile_matmul_eff_k),
        .matmul_spad_stride(tile_matmul_spad_stride),
        .matmul_output_acc32(tile_matmul_output_acc32),
        .matmul_done(matmul_done_w),
        .swap_banks(swap_banks_w)
    );

    // =====================================================
    // DMA Engine
    // =====================================================
    dma_engine #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_dma (
        .clk(clk), .rst(rst),
        .start(tile_dma_start), .direction(tile_dma_dir),
        .src_addr(tile_dma_src), .dst_addr(tile_dma_dst),
        .x_count(tile_dma_xcnt), .y_count(tile_dma_ycnt),
        .src_stride(tile_dma_sstride), .dst_stride(tile_dma_dstride),
        .burst_len(tile_dma_burst_len),
        .done(dma_done_w), .busy(), .irq(dma_irq_raw),
        .mem_addr(mem_addr), .mem_read(mem_read), .mem_write(mem_write),
        .mem_wdata(mem_wdata), .mem_burst_len(mem_burst_len),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .spad_addr(dma_spad_addr), .spad_wdata(dma_spad_wdata),
        .spad_we(dma_spad_we), .spad_re(dma_spad_re), .spad_rdata(dma_spad_rdata)
    );

    // =====================================================
    // Double-Buffered Scratchpad
    // =====================================================
    scratchpad_double_buf #(
        .ADDR_WIDTH(10),
        .DATA_WIDTH(32),
        .BANK_DEPTH(512)
    ) u_spad (
        .clk(clk), .rst(rst),
        .swap_banks(swap_banks_w),
        .dma_addr(dma_spad_addr), .dma_wdata(dma_spad_wdata),
        .dma_we(dma_spad_we), .dma_re(dma_spad_re), .dma_rdata(dma_spad_rdata),
        .comp_addr(ctrl_spad_addr), .comp_wdata(ctrl_spad_wdata),
        .comp_we(ctrl_spad_we), .comp_re(ctrl_spad_re), .comp_rdata(ctrl_spad_rdata)
    );

    // =====================================================
    // Matmul Controller v2
    // =====================================================
    matmul_controller_v2 #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_ctrl (
        .clk(clk), .rst(rst),
        .start(tile_matmul_start), .mode(tile_matmul_mode),
        .output_acc32(tile_matmul_output_acc32),
        .accumulate(tile_matmul_accumulate),
        .eff_rows(tile_matmul_eff_rows), .eff_k(tile_matmul_eff_k),
        .spad_row_stride(tile_matmul_spad_stride),
        .a_base_addr(tile_matmul_a_base),
        .b_base_addr(tile_matmul_b_base),
        .c_base_addr(tile_matmul_c_base),
        .done(matmul_done_w), .busy(),
        .spad_addr(ctrl_spad_addr), .spad_re(ctrl_spad_re),
        .spad_rdata(ctrl_spad_rdata),
        .spad_we(ctrl_spad_we), .spad_wdata(ctrl_spad_wdata),
        .a_col(mac_a_col), .b_row(mac_b_row),
        .mac_enable(mac_enable), .mac_clear_acc(mac_clear_acc),
        .result_matrix(mac_result)
    );

    // =====================================================
    // MAC Array v2 (clock-gated)
    // =====================================================
    mac_array_v2 #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_mac (
        .clk(mac_clk), .rst(rst),
        .mode(cfg_mode), .enable(mac_enable), .clear_acc(mac_clear_acc),
        .a_col(mac_a_col), .b_row(mac_b_row),
        .result_matrix(mac_result),
        .valid_out(mac_valid),
        .overflow_flags(mac_ovf)
    );

endmodule
