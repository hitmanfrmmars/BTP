// GEMM SoC Synthesis-Friendly Top-Level
//
// Identical to gemm_soc_top.v but uses a separate dpram_bytewrite module
// for Vivado BRAM inference. The original gemm_soc_top.v is kept for
// simulation (supports $readmemh and direct memory access from testbenches).
//
// Memory map:
//   0x0000_0000 - 0x0001_FFFF : Unified memory (128KB)
//   0x4000_0000 - 0x4000_003F : GEMM registers (MMIO)
//   0x1000_0000               : Debug output
//
module gemm_soc_synth_top #(
    parameter MEM_WORDS       = 32768,
    parameter ARRAY_SIZE      = 4,
    parameter ACC_WIDTH       = 48,
    parameter STACKADDR       = 32'h0002_0000,
    parameter PROGADDR_RESET  = 32'h0000_0000
) (
    input wire clk,
    input wire resetn,

    output wire        trap,
    output wire        accel_busy,
    output wire        accel_done,
    output wire        irq,

    output reg         debug_wr,
    output reg  [31:0] debug_data
);

    // =========================================================
    // PicoRV32 CPU signals
    // =========================================================
    wire        cpu_mem_valid;
    wire        cpu_mem_instr;
    wire        cpu_mem_ready;
    wire [31:0] cpu_mem_addr;
    wire [31:0] cpu_mem_wdata;
    wire [3:0]  cpu_mem_wstrb;
    wire [31:0] cpu_mem_rdata;

    wire        pcpi_valid;
    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;
    wire        pcpi_wr;
    wire [31:0] pcpi_rd;
    wire        pcpi_wait;
    wire        pcpi_ready;

    picorv32 #(
        .ENABLE_PCPI(1),
        .ENABLE_MUL(0),
        .ENABLE_IRQ(0),
        .STACKADDR(STACKADDR),
        .PROGADDR_RESET(PROGADDR_RESET)
    ) u_cpu (
        .clk       (clk),
        .resetn    (resetn),
        .trap      (trap),

        .mem_valid (cpu_mem_valid),
        .mem_instr (cpu_mem_instr),
        .mem_ready (cpu_mem_ready),
        .mem_addr  (cpu_mem_addr),
        .mem_wdata (cpu_mem_wdata),
        .mem_wstrb (cpu_mem_wstrb),
        .mem_rdata (cpu_mem_rdata),

        .pcpi_valid(pcpi_valid),
        .pcpi_insn (pcpi_insn),
        .pcpi_rs1  (pcpi_rs1),
        .pcpi_rs2  (pcpi_rs2),
        .pcpi_wr   (pcpi_wr),
        .pcpi_rd   (pcpi_rd),
        .pcpi_wait (pcpi_wait),
        .pcpi_ready(pcpi_ready),

        .irq({32{1'b0}}),
        .eoi()
    );

    // =========================================================
    // Address decode
    // =========================================================
    wire sel_mem   = (cpu_mem_addr[31:20] == 12'h000);
    wire sel_gemm  = (cpu_mem_addr[31:8]  == 24'h400000);
    wire sel_debug = (cpu_mem_addr[31:4]  == 28'h1000000);

    // =========================================================
    // Unified memory via dpram_bytewrite (Vivado BRAM-friendly)
    // =========================================================
    localparam MEM_ADDR_BITS = $clog2(MEM_WORDS);

    wire [MEM_ADDR_BITS-1:0] cpu_word_addr = cpu_mem_addr[MEM_ADDR_BITS+1:2];

    wire        cpu_mem_en = cpu_mem_valid && !cpu_mem_ready && sel_mem;
    wire [3:0]  cpu_bwe    = cpu_mem_wstrb & {4{cpu_mem_en}};

    // DMA signals
    wire [31:0] dma_mem_addr;
    wire        dma_mem_read;
    wire        dma_mem_write;
    wire [31:0] dma_mem_wdata;
    wire [3:0]  dma_burst_len;
    reg  [31:0] dma_mem_rdata;
    reg         dma_mem_ready;

    wire [MEM_ADDR_BITS-1:0] dma_word_addr = dma_mem_addr[MEM_ADDR_BITS+1:2];

    // DMA burst state machine (outside BRAM for clean inference)
    reg [3:0]  dma_burst_cnt;
    reg [31:0] dma_burst_addr;
    reg        dma_in_burst;

    wire                    dma_bram_en;
    wire                    dma_bram_we;
    wire [MEM_ADDR_BITS-1:0] dma_bram_addr;
    wire [31:0]             dma_bram_rdata;

    assign dma_bram_en   = dma_mem_read || dma_mem_write || dma_in_burst;
    assign dma_bram_we   = dma_mem_write && !dma_in_burst;
    assign dma_bram_addr = dma_in_burst ? dma_burst_addr[MEM_ADDR_BITS+1:2] : dma_word_addr;

    // CPU read data from BRAM
    wire [31:0] cpu_bram_rdata;

    dpram_bytewrite #(
        .ADDR_WIDTH(MEM_ADDR_BITS),
        .DATA_WIDTH(32),
        .DEPTH(MEM_WORDS)
    ) u_mem (
        .clk(clk),
        .a_en(cpu_mem_en),
        .a_we(cpu_bwe),
        .a_addr(cpu_word_addr),
        .a_din(cpu_mem_wdata),
        .a_dout(cpu_bram_rdata),
        .b_en(dma_bram_en),
        .b_we(dma_bram_we),
        .b_addr(dma_bram_addr),
        .b_din(dma_mem_wdata),
        .b_dout(dma_bram_rdata)
    );

    // CPU memory ready
    reg cpu_mem_ready_r;
    always @(posedge clk) begin
        cpu_mem_ready_r <= 1'b0;
        if (cpu_mem_en)
            cpu_mem_ready_r <= 1'b1;
    end

    // DMA burst logic (separated from BRAM)
    always @(posedge clk) begin
        if (!resetn) begin
            dma_mem_ready  <= 1'b0;
            dma_mem_rdata  <= 32'd0;
            dma_burst_cnt  <= 4'd0;
            dma_burst_addr <= 32'd0;
            dma_in_burst   <= 1'b0;
        end else if (dma_in_burst) begin
            if (dma_burst_cnt == 4'd0) begin
                dma_in_burst  <= 1'b0;
                dma_mem_ready <= 1'b0;
            end else begin
                dma_mem_rdata  <= dma_bram_rdata;
                dma_mem_ready  <= 1'b1;
                dma_burst_cnt  <= dma_burst_cnt - 4'd1;
                dma_burst_addr <= dma_burst_addr + 32'd4;
            end
        end else if (dma_mem_read) begin
            dma_mem_rdata  <= dma_bram_rdata;
            dma_mem_ready  <= 1'b1;
            dma_burst_addr <= dma_mem_addr + 32'd4;
            dma_burst_cnt  <= dma_burst_len;
            dma_in_burst   <= (dma_burst_len > 4'd0);
        end else if (dma_mem_write) begin
            dma_mem_ready <= 1'b1;
        end else begin
            dma_mem_ready <= 1'b0;
        end
    end

    // =========================================================
    // GEMM register MMIO
    // =========================================================
    reg        gemm_mmio_ready;
    reg [31:0] gemm_mmio_rdata;
    wire [5:0] gemm_mmio_addr = cpu_mem_addr[5:0];

    wire gemm_mmio_wr = cpu_mem_valid && !cpu_mem_ready && sel_gemm && (cpu_mem_wstrb != 4'b0);
    wire gemm_mmio_rd = cpu_mem_valid && !cpu_mem_ready && sel_gemm && (cpu_mem_wstrb == 4'b0);

    always @(posedge clk) begin
        gemm_mmio_ready <= 1'b0;
        if (cpu_mem_valid && !cpu_mem_ready && sel_gemm)
            gemm_mmio_ready <= 1'b1;
    end

    // =========================================================
    // Debug output register
    // =========================================================
    reg debug_ready;

    always @(posedge clk) begin
        debug_wr    <= 1'b0;
        debug_ready <= 1'b0;
        if (cpu_mem_valid && !cpu_mem_ready && sel_debug && (cpu_mem_wstrb != 4'b0)) begin
            debug_data  <= cpu_mem_wdata;
            debug_wr    <= 1'b1;
            debug_ready <= 1'b1;
        end else if (cpu_mem_valid && !cpu_mem_ready && sel_debug && (cpu_mem_wstrb == 4'b0)) begin
            debug_ready <= 1'b1;
        end
    end

    // =========================================================
    // CPU bus mux
    // =========================================================
    assign cpu_mem_ready = cpu_mem_ready_r | gemm_mmio_ready | debug_ready;
    assign cpu_mem_rdata = sel_gemm ? gemm_mmio_rdata :
                           sel_mem  ? cpu_bram_rdata   : 32'd0;

    wire [31:0] gemm_rf_rd_data;
    always @(posedge clk) begin
        if (gemm_mmio_rd)
            gemm_mmio_rdata <= gemm_rf_rd_data;
    end

    // =========================================================
    // GEMM Accelerator
    // =========================================================
    gemm_accelerator_top #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_gemm (
        .clk(clk),
        .rst(~resetn),
        .axi_wr_addr (gemm_mmio_addr),
        .axi_wr_data (cpu_mem_wdata),
        .axi_wr_en   (gemm_mmio_wr),
        .axi_rd_addr (gemm_mmio_addr),
        .axi_rd_data (gemm_rf_rd_data),
        .axi_rd_en   (gemm_mmio_rd),
        .pcpi_valid(pcpi_valid),
        .pcpi_insn (pcpi_insn),
        .pcpi_rs1  (pcpi_rs1),
        .pcpi_rs2  (pcpi_rs2),
        .pcpi_wr   (pcpi_wr),
        .pcpi_rd   (pcpi_rd),
        .pcpi_wait (pcpi_wait),
        .pcpi_ready(pcpi_ready),
        .mem_addr     (dma_mem_addr),
        .mem_read     (dma_mem_read),
        .mem_write    (dma_mem_write),
        .mem_wdata    (dma_mem_wdata),
        .mem_burst_len(dma_burst_len),
        .mem_rdata    (dma_mem_rdata),
        .mem_ready    (dma_mem_ready),
        .irq       (irq),
        .accel_busy(accel_busy),
        .accel_done(accel_done)
    );

endmodule
