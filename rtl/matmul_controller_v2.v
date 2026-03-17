// Streaming Matrix Multiplication Controller v2
// Uses output-stationary dataflow with broadcast MAC array.
// Supports int8/int16 modes, configurable spad_row_stride for macro-tile addressing.
module matmul_controller_v2 #(
    parameter ARRAY_SIZE = 4,
    parameter ACC_WIDTH  = 48
) (
    input wire clk,
    input wire rst,

    input wire        start,
    input wire        mode,              // 0=int8, 1=int16
    input wire        accumulate,        // 1=don't clear accumulators
    input wire [2:0]  eff_rows,          // 1..4 valid A/C rows
    input wire [2:0]  eff_k,             // 1..4 valid K passes
    input wire [9:0]  spad_row_stride,   // byte distance between rows in scratchpad
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
    reg [1:0]  pass_k;
    reg [2:0]  a_load_idx;
    reg [2:0]  write_idx;
    reg [1:0]  drain_cnt;
    reg        b_word_sub;
    reg [31:0] a_row_words [0:7];
    reg [31:0] b_row_words [0:1];

    reg [2:0]  eff_rows_reg, eff_k_reg;
    reg [9:0]  stride_reg;
    reg        mode_reg;

    wire [3:0] a_words_int8  = {1'b0, eff_rows_reg} - 4'd1;
    wire [3:0] a_words_int16 = {eff_rows_reg, 1'b0} - 4'd1;
    wire [2:0] a_load_max = mode_reg ? a_words_int16[2:0] : a_words_int8[2:0];
    wire [2:0] write_max  = mode_reg ? a_words_int16[2:0] : a_words_int8[2:0];

    // Address computations using stride_reg
    // int8: 1 word/row, row r at base + r * stride
    // int16: 2 words/row, row r word w at base + r * stride + w*4
    // For A loading, a_load_idx: int8 idx=row, int16 idx=row*2+word
    function [9:0] a_addr;
        input [2:0] idx;
        begin
            if (mode_reg)
                a_addr = a_base_addr + {1'b0, idx[2:1]} * stride_reg + {7'd0, idx[0], 2'b00};
            else
                a_addr = a_base_addr + {1'b0, idx[1:0]} * stride_reg;
        end
    endfunction

    function [9:0] b_addr;
        input [1:0] pk;
        input       wsub;
        begin
            b_addr = b_base_addr + {2'd0, pk} * stride_reg + {7'd0, wsub, 2'b00};
        end
    endfunction

    function [9:0] c_addr;
        input [2:0] idx;
        begin
            if (mode_reg)
                c_addr = c_base_addr + {1'b0, idx[2:1]} * stride_reg + {7'd0, idx[0], 2'b00};
            else
                c_addr = c_base_addr + {1'b0, idx[1:0]} * stride_reg;
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
            pass_k     <= 2'd0;
            a_load_idx <= 3'd0;
            write_idx  <= 3'd0;
            drain_cnt  <= 2'd0;
            b_word_sub <= 1'b0;
            eff_rows_reg  <= 3'd4;
            eff_k_reg     <= 3'd4;
            stride_reg    <= 10'd4;
            mode_reg      <= 1'b0;
            b_row_words[0] <= 32'd0;
            b_row_words[1] <= 32'd0;
            for (i = 0; i < 8; i = i + 1)
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
                        busy         <= 1'b1;
                        pass_k       <= 2'd0;
                        a_load_idx   <= 3'd0;
                        write_idx    <= 3'd0;
                        b_word_sub   <= 1'b0;
                        eff_rows_reg <= (eff_rows == 3'd0) ? 3'd4 : eff_rows;
                        eff_k_reg    <= (eff_k == 3'd0) ? 3'd4 : eff_k;
                        stride_reg   <= spad_row_stride;
                        mode_reg     <= mode;
                        state        <= S_INIT;
                    end
                end

                S_INIT: begin
                    spad_addr  <= a_addr(3'd0);
                    spad_re    <= 1'b1;
                    a_load_idx <= 3'd0;
                    state      <= S_LOAD_A_WAIT;
                end

                S_LOAD_A_WAIT: begin
                    state <= S_LOAD_A_CAP;
                end

                S_LOAD_A_CAP: begin
                    a_row_words[a_load_idx] <= spad_rdata;

                    if (a_load_idx < a_load_max) begin
                        spad_addr  <= a_addr(a_load_idx + 3'd1);
                        spad_re    <= 1'b1;
                        a_load_idx <= a_load_idx + 3'd1;
                        state      <= S_LOAD_A_WAIT;
                    end else begin
                        b_word_sub <= 1'b0;
                        spad_addr  <= b_addr(2'd0, 1'b0);
                        spad_re    <= 1'b1;
                        state      <= S_LOAD_B_WAIT;
                    end
                end

                S_LOAD_B_WAIT: begin
                    state <= S_LOAD_B_CAP;
                end

                S_LOAD_B_CAP: begin
                    b_row_words[b_word_sub] <= spad_rdata;

                    if (mode_reg && b_word_sub == 1'b0) begin
                        b_word_sub <= 1'b1;
                        spad_addr  <= b_addr(pass_k, 1'b1);
                        spad_re    <= 1'b1;
                        state      <= S_LOAD_B_WAIT;
                    end else begin
                        b_word_sub <= 1'b0;
                        state      <= S_COMPUTE;
                    end
                end

                S_COMPUTE: begin
                    for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                        if (mode_reg == 1'b0) begin
                            a_col[i] <= {8'd0, extract_byte(a_row_words[i], pass_k)};
                            b_row[i] <= {8'd0, b_row_words[0][i*8 +: 8]};
                        end else begin
                            a_col[i] <= extract_halfword(a_row_words[i*2 + pass_k[1]], pass_k[0]);
                            b_row[i] <= extract_halfword(b_row_words[i/2], i%2);
                        end
                    end
                    mac_enable    <= 1'b1;
                    mac_clear_acc <= (pass_k == 2'd0) & ~accumulate;

                    if (pass_k < (eff_k_reg - 3'd1)) begin
                        pass_k     <= pass_k + 2'd1;
                        b_word_sub <= 1'b0;
                        spad_addr  <= b_addr(pass_k + 2'd1, 1'b0);
                        spad_re    <= 1'b1;
                        state      <= S_LOAD_B_WAIT;
                    end else begin
                        drain_cnt <= 2'd0;
                        state     <= S_DRAIN;
                    end
                end

                S_DRAIN: begin
                    if (drain_cnt >= 2'd1) begin
                        write_idx <= 3'd0;
                        state     <= S_WRITE_BACK;
                    end else begin
                        drain_cnt <= drain_cnt + 2'd1;
                    end
                end

                S_WRITE_BACK: begin
                    spad_addr <= c_addr(write_idx);

                    if (mode_reg == 1'b0) begin
                        spad_wdata <= {
                            result_matrix[write_idx[1:0]][3][7:0],
                            result_matrix[write_idx[1:0]][2][7:0],
                            result_matrix[write_idx[1:0]][1][7:0],
                            result_matrix[write_idx[1:0]][0][7:0]
                        };
                    end else begin
                        if (write_idx[0] == 1'b0)
                            spad_wdata <= {
                                result_matrix[write_idx[2:1]][1][15:0],
                                result_matrix[write_idx[2:1]][0][15:0]
                            };
                        else
                            spad_wdata <= {
                                result_matrix[write_idx[2:1]][3][15:0],
                                result_matrix[write_idx[2:1]][2][15:0]
                            };
                    end
                    spad_we <= 1'b1;

                    if (write_idx >= write_max)
                        state <= S_DONE;
                    else
                        write_idx <= write_idx + 3'd1;
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
