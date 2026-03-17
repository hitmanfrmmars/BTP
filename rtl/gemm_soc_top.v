// GEMM SoC Top-Level
//
// Integrates PicoRV32 RISC-V CPU with the GEMM accelerator.
//
// Memory map:
//   0x0000_0000 - 0x0001_FFFF : Unified memory (128KB, firmware + data)
//   0x4000_0000 - 0x4000_003F : GEMM accelerator registers (MMIO)
//   0x1000_0000              : Debug output (testbench captures writes here)
//
// CPU accesses memory and MMIO through the PicoRV32 native interface.
// DMA accesses memory through a dedicated second port (no arbitration needed).
// GEMM custom instructions go through PCPI.
//
module gemm_soc_top #(
    parameter MEM_WORDS       = 32768,  // 128KB = 32K x 32-bit
    parameter FIRMWARE_FILE   = "firmware.hex",
    parameter ARRAY_SIZE      = 4,
    parameter ACC_WIDTH        = 48,
    parameter STACKADDR       = 32'h0002_0000,
    parameter PROGADDR_RESET  = 32'h0000_0000
) (
    input wire clk,
    input wire resetn,

    output wire        trap,
    output wire        accel_busy,
    output wire        accel_done,
    output wire        irq,

    // Debug output port (directly exposed for testbench)
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

    // PCPI
    wire        pcpi_valid;
    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;
    wire        pcpi_wr;
    wire [31:0] pcpi_rd;
    wire        pcpi_wait;
    wire        pcpi_ready;

    // IRQ (directly from GEMM accelerator)
    wire [31:0] cpu_irq = {28'd0, irq, 3'd0};
    wire [31:0] cpu_eoi;

    // =========================================================
    // PicoRV32 CPU
    // =========================================================
    picorv32 #(
        .ENABLE_COUNTERS     (1),
        .ENABLE_COUNTERS64   (0),
        .ENABLE_REGS_16_31   (1),
        .ENABLE_REGS_DUALPORT(1),
        .ENABLE_PCPI         (1),
        .ENABLE_MUL          (0),
        .ENABLE_FAST_MUL     (0),
        .ENABLE_DIV          (0),
        .ENABLE_IRQ          (1),
        .ENABLE_IRQ_QREGS    (0),
        .ENABLE_IRQ_TIMER    (0),
        .ENABLE_TRACE        (0),
        .REGS_INIT_ZERO      (1),
        .STACKADDR           (STACKADDR),
        .PROGADDR_RESET      (PROGADDR_RESET),
        .PROGADDR_IRQ        (32'h0000_0010),
        .BARREL_SHIFTER      (0),
        .COMPRESSED_ISA      (0),
        .CATCH_MISALIGN      (0),
        .CATCH_ILLINSN       (1),
        .LATCHED_MEM_RDATA   (0)
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

        .mem_la_read  (),
        .mem_la_write (),
        .mem_la_addr  (),
        .mem_la_wdata (),
        .mem_la_wstrb (),

        .pcpi_valid(pcpi_valid),
        .pcpi_insn (pcpi_insn),
        .pcpi_rs1  (pcpi_rs1),
        .pcpi_rs2  (pcpi_rs2),
        .pcpi_wr   (pcpi_wr),
        .pcpi_rd   (pcpi_rd),
        .pcpi_wait (pcpi_wait),
        .pcpi_ready(pcpi_ready),

        .irq       (cpu_irq),
        .eoi       (cpu_eoi),

        .trace_valid(),
        .trace_data ()
    );

    // =========================================================
    // Address decode
    // =========================================================
    wire sel_mem   = (cpu_mem_addr[31:20] == 12'h000);   // 0x000xxxxx
    wire sel_gemm  = (cpu_mem_addr[31:8]  == 24'h400000); // 0x400000xx
    wire sel_debug = (cpu_mem_addr[31:4]  == 28'h1000000); // 0x1000000x

    // =========================================================
    // Unified memory (dual-port: Port A = CPU, Port B = DMA)
    // =========================================================
    localparam MEM_ADDR_BITS = $clog2(MEM_WORDS);

    reg [31:0] memory [0:MEM_WORDS-1];

    initial begin
        $readmemh(FIRMWARE_FILE, memory);
    end

    wire [MEM_ADDR_BITS-1:0] cpu_word_addr = cpu_mem_addr[MEM_ADDR_BITS+1:2];

    // Port A: CPU read/write
    reg        cpu_mem_ready_r;
    reg [31:0] cpu_mem_rdata_r;

    always @(posedge clk) begin
        cpu_mem_ready_r <= 1'b0;
        if (cpu_mem_valid && !cpu_mem_ready && sel_mem) begin
            cpu_mem_ready_r <= 1'b1;
            cpu_mem_rdata_r <= memory[cpu_word_addr];
            if (cpu_mem_wstrb[0]) memory[cpu_word_addr][ 7: 0] <= cpu_mem_wdata[ 7: 0];
            if (cpu_mem_wstrb[1]) memory[cpu_word_addr][15: 8] <= cpu_mem_wdata[15: 8];
            if (cpu_mem_wstrb[2]) memory[cpu_word_addr][23:16] <= cpu_mem_wdata[23:16];
            if (cpu_mem_wstrb[3]) memory[cpu_word_addr][31:24] <= cpu_mem_wdata[31:24];
        end
    end

    // Port B: DMA read/write
    wire [31:0] dma_mem_addr;
    wire        dma_mem_read;
    wire        dma_mem_write;
    wire [31:0] dma_mem_wdata;
    wire [3:0]  dma_burst_len;
    reg  [31:0] dma_mem_rdata;
    reg         dma_mem_ready;

    wire [MEM_ADDR_BITS-1:0] dma_word_addr = dma_mem_addr[MEM_ADDR_BITS+1:2];

    // DMA burst state machine
    reg [3:0]  dma_burst_cnt;
    reg [31:0] dma_burst_addr;
    reg        dma_in_burst;

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
                dma_mem_rdata  <= memory[dma_burst_addr[MEM_ADDR_BITS+1:2]];
                dma_mem_ready  <= 1'b1;
                dma_burst_cnt  <= dma_burst_cnt - 4'd1;
                dma_burst_addr <= dma_burst_addr + 32'd4;
            end
        end else if (dma_mem_read) begin
            dma_mem_rdata  <= memory[dma_word_addr];
            dma_mem_ready  <= 1'b1;
            dma_burst_addr <= dma_mem_addr + 32'd4;
            dma_burst_cnt  <= dma_burst_len;
            dma_in_burst   <= (dma_burst_len > 4'd0);
        end else if (dma_mem_write) begin
            memory[dma_word_addr] <= dma_mem_wdata;
            dma_mem_ready <= 1'b1;
        end else begin
            dma_mem_ready <= 1'b0;
        end
    end

    // =========================================================
    // GEMM register MMIO (CPU load/store to 0x40000000+)
    // =========================================================
    reg        gemm_mmio_ready;
    reg [31:0] gemm_mmio_rdata;
    wire [5:0] gemm_mmio_addr = cpu_mem_addr[5:0];

    wire       gemm_mmio_wr = cpu_mem_valid && !cpu_mem_ready && sel_gemm && (cpu_mem_wstrb != 4'b0);
    wire       gemm_mmio_rd = cpu_mem_valid && !cpu_mem_ready && sel_gemm && (cpu_mem_wstrb == 4'b0);

    always @(posedge clk) begin
        gemm_mmio_ready <= 1'b0;
        if (cpu_mem_valid && !cpu_mem_ready && sel_gemm) begin
            gemm_mmio_ready <= 1'b1;
        end
    end

    // =========================================================
    // Debug output register (write to 0x10000000)
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
                           sel_mem  ? cpu_mem_rdata_r  : 32'd0;

    // Latch GEMM read data from the regfile's combinational output
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

        // AXI-Lite MMIO from CPU load/store
        .axi_wr_addr (gemm_mmio_addr),
        .axi_wr_data (cpu_mem_wdata),
        .axi_wr_en   (gemm_mmio_wr),
        .axi_rd_addr (gemm_mmio_addr),
        .axi_rd_data (gemm_rf_rd_data),
        .axi_rd_en   (gemm_mmio_rd),

        // PCPI from PicoRV32
        .pcpi_valid(pcpi_valid),
        .pcpi_insn (pcpi_insn),
        .pcpi_rs1  (pcpi_rs1),
        .pcpi_rs2  (pcpi_rs2),
        .pcpi_wr   (pcpi_wr),
        .pcpi_rd   (pcpi_rd),
        .pcpi_wait (pcpi_wait),
        .pcpi_ready(pcpi_ready),

        // DMA memory interface (Port B of unified memory)
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
