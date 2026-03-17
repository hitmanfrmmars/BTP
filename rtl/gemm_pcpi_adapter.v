// GEMM Accelerator PCPI Adapter for PicoRV32
//
// Bridges PicoRV32's Pico Co-Processor Interface (PCPI) to the GEMM
// accelerator's register file. Replaces gemm_custom_insn.v when using
// PicoRV32 as the host CPU.
//
// Instruction encoding (R-type, custom-0 opcode):
//   [31:25] funct7=0001000  [24:20] rs2  [19:15] rs1  [14:12] funct3  [11:7] rd  [6:0] 0001011
//
//   funct3=000  GEMM.CFG   rd, rs1, rs2  -- write rs1 to accel_reg[rs2], old value -> rd
//   funct3=001  GEMM.START rd            -- start computation, status -> rd
//   funct3=010  GEMM.WAIT  rd            -- stall CPU until done, cycle count -> rd
//   funct3=011  GEMM.STATUS rd           -- read status register -> rd
//
// funct7=0x08 avoids collision with PicoRV32's internal IRQ instructions (funct7 0-5).
// With ENABLE_IRQ=1, PicoRV32 handles its own custom-0 encodings internally;
// all others (including ours) are forwarded to PCPI.
//
module gemm_pcpi_adapter (
    input wire clk,
    input wire resetn,      // PicoRV32 uses active-low reset

    // PicoRV32 PCPI interface
    input  wire        pcpi_valid,
    input  wire [31:0] pcpi_insn,
    input  wire [31:0] pcpi_rs1,
    input  wire [31:0] pcpi_rs2,
    output reg         pcpi_wr,
    output reg  [31:0] pcpi_rd,
    output reg         pcpi_wait,
    output reg         pcpi_ready,

    // Register file write port
    output reg  [5:0]  reg_wr_addr,
    output reg  [31:0] reg_wr_data,
    output reg         reg_wr_en,

    // Register file read port (combinational in gemm_regfile)
    output reg  [5:0]  reg_rd_addr,
    output wire [31:0] reg_rd_data,
    output reg         reg_rd_en,

    // Accelerator status (directly from tiling engine)
    input wire         accel_done
);

    // Instruction field extraction
    wire [6:0] opcode = pcpi_insn[6:0];
    wire [2:0] funct3 = pcpi_insn[14:12];
    wire [6:0] funct7 = pcpi_insn[31:25];

    // Match our GEMM instructions: custom-0 opcode + our funct7.
    // The `responded` flag prevents re-triggering: after pcpi_ready fires,
    // PicoRV32 takes one cycle to deassert pcpi_valid. The flag stays set
    // until pcpi_valid goes low, blocking any re-decode of the same insn.
    localparam GEMM_FUNCT7 = 7'b0001000;  // 0x08
    reg responded;
    wire is_gemm = pcpi_valid && !responded
                   && (opcode == 7'b0001011) && (funct7 == GEMM_FUNCT7);

    // Sub-instruction decode
    wire is_cfg    = is_gemm && (funct3 == 3'b000);
    wire is_start  = is_gemm && (funct3 == 3'b001);
    wire is_wait   = is_gemm && (funct3 == 3'b010);
    wire is_status = is_gemm && (funct3 == 3'b011);

    // Register offsets
    localparam REG_CTRL   = 6'h00;
    localparam REG_STATUS = 6'h04;
    localparam REG_CYCLES = 6'h28;

    // FSM states
    localparam S_IDLE    = 2'd0;
    localparam S_RESPOND = 2'd1;  // 1-cycle delay for regfile read to settle
    localparam S_WAITING = 2'd2;  // stalling CPU while accelerator runs
    localparam S_WDONE   = 2'd3;  // accelerator done, read cycle counter

    reg [1:0] state;
    reg [2:0] saved_funct3;
    reg [31:0] saved_rs1;
    reg [5:0]  saved_reg_addr; // for GEMM.CFG: target register address

    always @(posedge clk) begin
        if (!resetn) begin
            state        <= S_IDLE;
            pcpi_wr      <= 1'b0;
            pcpi_rd      <= 32'd0;
            pcpi_wait    <= 1'b0;
            pcpi_ready   <= 1'b0;
            reg_wr_en    <= 1'b0;
            reg_rd_en    <= 1'b0;
            reg_wr_addr  <= 6'd0;
            reg_wr_data  <= 32'd0;
            reg_rd_addr  <= 6'd0;
            saved_funct3 <= 3'd0;
            saved_rs1    <= 32'd0;
            saved_reg_addr <= 6'd0;
            responded    <= 1'b0;
        end else begin
            // Defaults: single-cycle pulses
            pcpi_wr    <= 1'b0;
            pcpi_ready <= 1'b0;
            reg_wr_en  <= 1'b0;

            // Clear responded flag when CPU drops pcpi_valid
            if (!pcpi_valid)
                responded <= 1'b0;

            case (state)
                S_IDLE: begin
                    pcpi_wait <= 1'b0;
                    reg_rd_en <= 1'b0;

                    if (is_gemm) begin
                        saved_funct3 <= funct3;

                        case (funct3)
                            3'b000: begin // GEMM.CFG: read old value from reg[rs2]
                                reg_rd_addr    <= pcpi_rs2[5:0];
                                reg_rd_en      <= 1'b1;
                                saved_rs1      <= pcpi_rs1;
                                saved_reg_addr <= pcpi_rs2[5:0];
                                pcpi_wait      <= 1'b1;
                                state          <= S_RESPOND;
                            end
                            3'b001: begin // GEMM.START: write 1 to CTRL, read STATUS
                                reg_wr_addr <= REG_CTRL;
                                reg_wr_data <= 32'h0000_0001;
                                reg_wr_en   <= 1'b1;
                                reg_rd_addr <= REG_STATUS;
                                reg_rd_en   <= 1'b1;
                                pcpi_wait   <= 1'b1;
                                state       <= S_RESPOND;
                            end
                            3'b010: begin // GEMM.WAIT
                                if (accel_done) begin
                                    reg_rd_addr <= REG_CYCLES;
                                    reg_rd_en   <= 1'b1;
                                    pcpi_wait   <= 1'b1;
                                    state       <= S_RESPOND;
                                end else begin
                                    pcpi_wait <= 1'b1;
                                    state     <= S_WAITING;
                                end
                            end
                            3'b011: begin // GEMM.STATUS: read STATUS register
                                reg_rd_addr <= REG_STATUS;
                                reg_rd_en   <= 1'b1;
                                pcpi_wait   <= 1'b1;
                                state       <= S_RESPOND;
                            end
                            default: begin
                                // Not our instruction variant -- don't assert wait/ready
                                // PicoRV32 will timeout and raise illegal instruction
                            end
                        endcase
                    end
                end

                S_RESPOND: begin
                    pcpi_rd    <= reg_rd_data;
                    pcpi_wr    <= 1'b1;
                    pcpi_ready <= 1'b1;
                    pcpi_wait  <= 1'b0;
                    reg_rd_en  <= 1'b0;
                    responded  <= 1'b1;

                    if (saved_funct3 == 3'b000) begin
                        reg_wr_addr <= saved_reg_addr;
                        reg_wr_data <= saved_rs1;
                        reg_wr_en   <= 1'b1;
                    end

                    state <= S_IDLE;
                end

                S_WAITING: begin
                    // Hold CPU stalled while accelerator runs
                    pcpi_wait <= 1'b1;
                    reg_rd_en <= 1'b0;

                    if (accel_done) begin
                        // Accelerator finished -- read cycle counter
                        reg_rd_addr <= REG_CYCLES;
                        reg_rd_en   <= 1'b1;
                        state       <= S_WDONE;
                    end
                end

                S_WDONE: begin
                    pcpi_rd    <= reg_rd_data;
                    pcpi_wr    <= 1'b1;
                    pcpi_ready <= 1'b1;
                    pcpi_wait  <= 1'b0;
                    reg_rd_en  <= 1'b0;
                    responded  <= 1'b1;
                    state      <= S_IDLE;
                end
            endcase
        end
    end

endmodule
