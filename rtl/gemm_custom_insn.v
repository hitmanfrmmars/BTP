// RISC-V Custom Instruction Decoder for GEMM Accelerator
// Decodes custom-0 opcode (0x0B) into accelerator register file operations.
//
// Instruction encoding (R-type):
//   [31:25] funct7  [24:20] rs2  [19:15] rs1  [14:12] funct3  [11:7] rd  [6:0] opcode
//
// Custom instructions:
//   funct3=000: GEMM.CFG  rd, rs1, rs2  -- write rs1 to reg[rs2], old value -> rd
//   funct3=001: GEMM.START rd            -- start computation, status -> rd
//   funct3=010: GEMM.WAIT  rd            -- poll until done, cycle count -> rd
//   funct3=011: GEMM.STATUS rd           -- read status register -> rd
module gemm_custom_insn (
    input wire        clk,
    input wire        rst,

    // From RISC-V decode stage
    input wire [31:0] instruction,
    input wire        valid,          // instruction is a valid custom-0
    input wire [31:0] rs1_data,       // data from register rs1
    input wire [31:0] rs2_data,       // data from register rs2

    // To RISC-V writeback
    output reg [31:0] rd_data,        // result to write to rd
    output reg        rd_valid,       // result is valid
    output reg        stall,          // stall pipeline (GEMM.WAIT)

    // Register file interface
    output reg [5:0]  reg_wr_addr,
    output reg [31:0] reg_wr_data,
    output reg        reg_wr_en,
    output reg [5:0]  reg_rd_addr,
    input wire [31:0] reg_rd_data,
    output reg        reg_rd_en,

    // Accelerator status
    input wire        accel_busy,
    input wire        accel_done
);

    wire [6:0]  opcode = instruction[6:0];
    wire [4:0]  rd     = instruction[11:7];
    wire [2:0]  funct3 = instruction[14:12];
    wire [4:0]  rs1    = instruction[19:15];
    wire [4:0]  rs2    = instruction[24:20];

    wire is_custom0 = (opcode == 7'h0B);

    // Stall state for GEMM.WAIT
    reg waiting;

    always @(posedge clk) begin
        if (rst) begin
            rd_data     <= 32'd0;
            rd_valid    <= 1'b0;
            stall       <= 1'b0;
            reg_wr_addr <= 6'd0;
            reg_wr_data <= 32'd0;
            reg_wr_en   <= 1'b0;
            reg_rd_addr <= 6'd0;
            reg_rd_en   <= 1'b0;
            waiting     <= 1'b0;
        end else begin
            rd_valid  <= 1'b0;
            reg_wr_en <= 1'b0;
            reg_rd_en <= 1'b0;

            if (waiting) begin
                // Poll until accelerator done
                if (accel_done) begin
                    waiting  <= 1'b0;
                    stall    <= 1'b0;
                    // Return cycle count from register 0x28
                    reg_rd_addr <= 6'h28;
                    reg_rd_en   <= 1'b1;
                    rd_data     <= reg_rd_data;
                    rd_valid    <= 1'b1;
                end
            end else if (valid && is_custom0) begin
                case (funct3)
                    3'b000: begin // GEMM.CFG: write rs1 to reg[rs2], return old
                        reg_rd_addr <= rs2_data[5:0];
                        reg_rd_en   <= 1'b1;
                        rd_data     <= reg_rd_data;
                        rd_valid    <= 1'b1;
                        reg_wr_addr <= rs2_data[5:0];
                        reg_wr_data <= rs1_data;
                        reg_wr_en   <= 1'b1;
                    end

                    3'b001: begin // GEMM.START: write start bit, return status
                        reg_wr_addr <= 6'h00;
                        reg_wr_data <= 32'h0000_0001; // start=1
                        reg_wr_en   <= 1'b1;
                        reg_rd_addr <= 6'h04; // STATUS
                        reg_rd_en   <= 1'b1;
                        rd_data     <= reg_rd_data;
                        rd_valid    <= 1'b1;
                    end

                    3'b010: begin // GEMM.WAIT: stall until done
                        if (accel_done) begin
                            reg_rd_addr <= 6'h28; // CYCLES
                            reg_rd_en   <= 1'b1;
                            rd_data     <= reg_rd_data;
                            rd_valid    <= 1'b1;
                        end else begin
                            stall   <= 1'b1;
                            waiting <= 1'b1;
                        end
                    end

                    3'b011: begin // GEMM.STATUS: read status
                        reg_rd_addr <= 6'h04;
                        reg_rd_en   <= 1'b1;
                        rd_data     <= reg_rd_data;
                        rd_valid    <= 1'b1;
                    end

                    default: begin
                        rd_data  <= 32'd0;
                        rd_valid <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
