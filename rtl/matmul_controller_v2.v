// Streaming Matrix Multiplication Controller v2 (Parameterized)
// Uses output-stationary dataflow with broadcast MAC array.
// Supports int8/int16 modes, configurable spad_row_stride for macro-tile addressing.
// Fully parameterized for any power-of-2 ARRAY_SIZE (4, 8, 16, ...).
module matmul_controller_v2 #(
    parameter ARRAY_SIZE = 4,
    parameter ACC_WIDTH  = 48
) (
    input wire clk,
    input wire rst,

    input wire        start,
    input wire        mode,              // 0=int8, 1=int16
    input wire        output_acc32,      // 1=write full 32-bit accumulator per element
    input wire        accumulate,        // 1=don't clear accumulators
    input wire [3:0]  eff_rows,          // 0=ARRAY_SIZE, 1..ARRAY_SIZE-1=partial
    input wire [3:0]  eff_k,             // 0=ARRAY_SIZE, 1..ARRAY_SIZE-1=partial
    input wire [9:0]  spad_row_stride,
    input wire [9:0]  a_base_addr,
    input wire [9:0]  b_base_addr,
    input wire [9:0]  c_base_addr,
    output reg        done,
    output reg        busy,

    output reg [9:0]  spad_addr,
    output reg        spad_re,
    input wire [31:0] spad_rdata,
    output reg        spad_we,
    output reg [31:0] spad_wdata,

    output reg [15:0] a_col [0:ARRAY_SIZE-1],
    output reg [15:0] b_row [0:ARRAY_SIZE-1],
    output reg        mac_enable,
    output reg        mac_clear_acc,
    input wire [ACC_WIDTH-1:0] result_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1]
);

    // ======================== Derived Parameters ========================
    localparam WPR8      = ARRAY_SIZE / 4;            // words per row, int8
    localparam WPR16     = ARRAY_SIZE / 2;            // words per row, int16
    localparam MAX_A_WDS = ARRAY_SIZE * WPR16;        // max A words (int16)
    localparam MAX_B_WDS = WPR16;                     // max B words per K-row
    localparam MAX_WB    = ARRAY_SIZE * ARRAY_SIZE;   // max write-back words (acc32)
    localparam MAX_IDX   = (MAX_A_WDS > MAX_WB) ? MAX_A_WDS : MAX_WB;
    localparam IDX_W     = $clog2(MAX_IDX + 1);      // index bit-width
    localparam [9:0] C_STRIDE_ACC32 = ARRAY_SIZE * 4; // C row stride in acc32 mode (bytes)

    // ======================== FSM States ========================
    localparam S_IDLE        = 4'd0;
    localparam S_INIT        = 4'd1;
    localparam S_LOAD_A_WAIT = 4'd2;
    localparam S_LOAD_A_CAP  = 4'd3;
    localparam S_LOAD_B_WAIT = 4'd4;
    localparam S_LOAD_B_CAP  = 4'd5;
    localparam S_COMPUTE     = 4'd6;
    localparam S_DRAIN       = 4'd7;
    localparam S_WRITE_BACK  = 4'd8;
    localparam S_DONE        = 4'd9;

    reg [3:0]  state;
    reg [3:0]  pass_k;
    reg [IDX_W-1:0] a_load_idx;
    reg [IDX_W-1:0] write_idx;
    reg [1:0]  drain_cnt;
    reg [2:0]  b_word_sub;
    reg [31:0] a_row_words [0:MAX_A_WDS-1];
    reg [31:0] b_row_words [0:MAX_B_WDS-1];

    reg [3:0]  eff_rows_reg, eff_k_reg;
    reg [9:0]  stride_reg;
    reg        mode_reg;
    reg        output_acc32_reg;

    // ======================== Computed Limits ========================
    wire [IDX_W-1:0] a_load_max = mode_reg
        ? (eff_rows_reg * WPR16 - 1)
        : (eff_rows_reg * WPR8  - 1);
    wire [IDX_W-1:0] write_max = output_acc32_reg
        ? (eff_rows_reg * ARRAY_SIZE[IDX_W-1:0] - 1)
        : a_load_max;
    wire [2:0] b_wpr = mode_reg ? WPR16[2:0] : WPR8[2:0];

    // Write-back row/column decode
    wire [3:0] wb_row  = output_acc32_reg
        ? (write_idx / ARRAY_SIZE)
        : (mode_reg ? (write_idx / WPR16) : (write_idx / WPR8));
    wire [3:0] wb_woff = mode_reg ? (write_idx % WPR16) : (write_idx % WPR8);
    wire [3:0] wb_col0 = output_acc32_reg
        ? (write_idx % ARRAY_SIZE)
        : (mode_reg ? (wb_woff * 2) : (wb_woff * 4));

    // ======================== Address Functions ========================
    function [9:0] a_addr;
        input [IDX_W-1:0] idx;
        reg [IDX_W-1:0] row, woff;
        begin
            if (mode_reg) begin
                row  = idx / WPR16;
                woff = idx % WPR16;
            end else begin
                row  = idx / WPR8;
                woff = idx % WPR8;
            end
            a_addr = a_base_addr + row[3:0] * stride_reg + {4'd0, woff[2:0], 2'b00};
        end
    endfunction

    function [9:0] b_addr;
        input [3:0] pk;
        input [2:0] wsub;
        begin
            b_addr = b_base_addr + pk * stride_reg + {5'd0, wsub, 2'b00};
        end
    endfunction

    function [9:0] c_addr;
        input [IDX_W-1:0] idx;
        reg [IDX_W-1:0] row, woff;
        begin
            if (output_acc32_reg) begin
                row  = idx / ARRAY_SIZE;
                woff = idx % ARRAY_SIZE;
                c_addr = c_base_addr + row[3:0] * C_STRIDE_ACC32 + {4'd0, woff[2:0], 2'b00};
            end else if (mode_reg) begin
                row  = idx / WPR16;
                woff = idx % WPR16;
                c_addr = c_base_addr + row[3:0] * stride_reg + {4'd0, woff[2:0], 2'b00};
            end else begin
                row  = idx / WPR8;
                woff = idx % WPR8;
                c_addr = c_base_addr + row[3:0] * stride_reg + {4'd0, woff[2:0], 2'b00};
            end
        end
    endfunction

    function [7:0] extract_byte;
        input [31:0] word;
        input [1:0]  sel;
        begin
            case (sel)
                2'd0: extract_byte = word[7:0];
                2'd1: extract_byte = word[15:8];
                2'd2: extract_byte = word[23:16];
                2'd3: extract_byte = word[31:24];
            endcase
        end
    endfunction

    function [15:0] extract_halfword;
        input [31:0] word;
        input        sel;
        begin
            extract_halfword = sel ? word[31:16] : word[15:0];
        end
    endfunction

    // ======================== Main FSM ========================
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            done       <= 1'b0;
            busy       <= 1'b0;
            spad_addr  <= 10'd0;
            spad_re    <= 1'b0;
            spad_we    <= 1'b0;
            spad_wdata <= 32'd0;
            mac_enable    <= 1'b0;
            mac_clear_acc <= 1'b0;
            pass_k     <= 4'd0;
            a_load_idx <= {IDX_W{1'b0}};
            write_idx  <= {IDX_W{1'b0}};
            drain_cnt  <= 2'd0;
            b_word_sub <= 3'd0;
            eff_rows_reg     <= ARRAY_SIZE[3:0];
            eff_k_reg        <= ARRAY_SIZE[3:0];
            stride_reg       <= 10'd4;
            mode_reg         <= 1'b0;
            output_acc32_reg <= 1'b0;
            for (i = 0; i < MAX_B_WDS; i = i + 1)
                b_row_words[i] <= 32'd0;
            for (i = 0; i < MAX_A_WDS; i = i + 1)
                a_row_words[i] <= 32'd0;
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                a_col[i] <= 16'd0;
                b_row[i] <= 16'd0;
            end
        end else begin
            mac_enable    <= 1'b0;
            mac_clear_acc <= 1'b0;
            spad_we       <= 1'b0;
            spad_re       <= 1'b0;

            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    if (start) begin
                        busy             <= 1'b1;
                        pass_k           <= 4'd0;
                        a_load_idx       <= {IDX_W{1'b0}};
                        write_idx        <= {IDX_W{1'b0}};
                        b_word_sub       <= 3'd0;
                        eff_rows_reg     <= (eff_rows == 4'd0) ? ARRAY_SIZE[3:0] : eff_rows;
                        eff_k_reg        <= (eff_k == 4'd0)    ? ARRAY_SIZE[3:0] : eff_k;
                        stride_reg       <= spad_row_stride;
                        mode_reg         <= mode;
                        output_acc32_reg <= output_acc32;
                        state            <= S_INIT;
                    end
                end

                S_INIT: begin
                    spad_addr  <= a_addr({IDX_W{1'b0}});
                    spad_re    <= 1'b1;
                    a_load_idx <= {IDX_W{1'b0}};
                    state      <= S_LOAD_A_WAIT;
                end

                S_LOAD_A_WAIT: begin
                    state <= S_LOAD_A_CAP;
                end

                S_LOAD_A_CAP: begin
                    a_row_words[a_load_idx] <= spad_rdata;

                    if (a_load_idx < a_load_max) begin
                        spad_addr  <= a_addr(a_load_idx + 1);
                        spad_re    <= 1'b1;
                        a_load_idx <= a_load_idx + 1;
                        state      <= S_LOAD_A_WAIT;
                    end else begin
                        b_word_sub <= 3'd0;
                        spad_addr  <= b_addr(pass_k, 3'd0);
                        spad_re    <= 1'b1;
                        state      <= S_LOAD_B_WAIT;
                    end
                end

                S_LOAD_B_WAIT: begin
                    state <= S_LOAD_B_CAP;
                end

                S_LOAD_B_CAP: begin
                    b_row_words[b_word_sub] <= spad_rdata;

                    if (b_word_sub < b_wpr - 3'd1) begin
                        b_word_sub <= b_word_sub + 3'd1;
                        spad_addr  <= b_addr(pass_k, b_word_sub + 3'd1);
                        spad_re    <= 1'b1;
                        state      <= S_LOAD_B_WAIT;
                    end else begin
                        b_word_sub <= 3'd0;
                        state      <= S_COMPUTE;
                    end
                end

                S_COMPUTE: begin
                    for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                        if (mode_reg == 1'b0) begin
                            a_col[i] <= {8'd0, extract_byte(
                                a_row_words[i * WPR8 + (pass_k >> 2)],
                                pass_k[1:0])};
                            b_row[i] <= {8'd0, extract_byte(
                                b_row_words[i / 4],
                                i % 4)};
                        end else begin
                            a_col[i] <= extract_halfword(
                                a_row_words[i * WPR16 + (pass_k >> 1)],
                                pass_k[0]);
                            b_row[i] <= extract_halfword(
                                b_row_words[i / 2],
                                i % 2);
                        end
                    end
                    mac_enable    <= 1'b1;
                    mac_clear_acc <= (pass_k == 4'd0) & ~accumulate;

                    if (pass_k < (eff_k_reg - 4'd1)) begin
                        pass_k     <= pass_k + 4'd1;
                        b_word_sub <= 3'd0;
                        spad_addr  <= b_addr(pass_k + 4'd1, 3'd0);
                        spad_re    <= 1'b1;
                        state      <= S_LOAD_B_WAIT;
                    end else begin
                        drain_cnt <= 2'd0;
                        state     <= S_DRAIN;
                    end
                end

                S_DRAIN: begin
                    if (drain_cnt >= 2'd1) begin
                        write_idx <= {IDX_W{1'b0}};
                        state     <= S_WRITE_BACK;
                    end else begin
                        drain_cnt <= drain_cnt + 2'd1;
                    end
                end

                S_WRITE_BACK: begin
                    spad_addr <= c_addr(write_idx);

                    if (output_acc32_reg) begin
                        spad_wdata <= result_matrix[wb_row[2:0]][wb_col0[2:0]][31:0];
                    end else if (mode_reg == 1'b0) begin
                        spad_wdata <= {
                            result_matrix[wb_row[2:0]][wb_col0[2:0] + 3'd3][7:0],
                            result_matrix[wb_row[2:0]][wb_col0[2:0] + 3'd2][7:0],
                            result_matrix[wb_row[2:0]][wb_col0[2:0] + 3'd1][7:0],
                            result_matrix[wb_row[2:0]][wb_col0[2:0] + 3'd0][7:0]
                        };
                    end else begin
                        spad_wdata <= {
                            result_matrix[wb_row[2:0]][wb_col0[2:0] + 3'd1][15:0],
                            result_matrix[wb_row[2:0]][wb_col0[2:0] + 3'd0][15:0]
                        };
                    end
                    spad_we <= 1'b1;

                    if (write_idx >= write_max)
                        state <= S_DONE;
                    else
                        write_idx <= write_idx + 1;
                end

                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
