// Burst DMA Engine with 2D Strided Transfer Support
// LOAD: burst reads from memory, pipelined writes to scratchpad
// STORE: sequential spad reads (1-cycle latency), writes to memory
// 2D strided: x_count words per row, y_count rows, configurable strides
module dma_engine #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input wire clk,
    input wire rst,

    input wire        start,
    input wire        direction,       // 0 = LOAD (mem->spad), 1 = STORE (spad->mem)
    input wire [ADDR_WIDTH-1:0] src_addr,
    input wire [ADDR_WIDTH-1:0] dst_addr,
    input wire [15:0] x_count,
    input wire [15:0] y_count,
    input wire [15:0] src_stride,
    input wire [15:0] dst_stride,
    input wire [3:0]  burst_len,       // 0=1 beat, up to 15=16 beats
    output reg        done,
    output reg        busy,
    output reg        irq,

    output reg [ADDR_WIDTH-1:0] mem_addr,
    output reg                  mem_read,
    output reg                  mem_write,
    output reg [DATA_WIDTH-1:0] mem_wdata,
    input wire [DATA_WIDTH-1:0] mem_rdata,
    input wire                  mem_ready,
    output reg [3:0]            mem_burst_len,

    output reg [9:0]            spad_addr,
    output reg [DATA_WIDTH-1:0] spad_wdata,
    output reg                  spad_we,
    output reg                  spad_re,
    input wire [DATA_WIDTH-1:0] spad_rdata
);

    localparam S_IDLE        = 4'd0;
    localparam S_LOAD_ADDR   = 4'd1;
    localparam S_LOAD_RECV   = 4'd2;
    localparam S_LOAD_NEXT   = 4'd3;
    localparam S_STORE_READ  = 4'd4;
    localparam S_STORE_WAIT  = 4'd5;
    localparam S_STORE_WR    = 4'd6;
    localparam S_DONE        = 4'd7;

    reg [3:0]  state;

    reg [ADDR_WIDTH-1:0] cur_src, cur_dst;
    reg [ADDR_WIDTH-1:0] row_src_base, row_dst_base;
    reg [15:0] x_idx, y_idx;
    reg [15:0] x_cnt_reg, y_cnt_reg;
    reg [15:0] src_stride_reg, dst_stride_reg;
    reg        dir_reg;
    reg [3:0]  burst_reg;
    reg [3:0]  beat_cnt;

    wire [15:0] remaining = x_cnt_reg - x_idx;
    wire [4:0]  burst_plus1 = {1'b0, burst_reg} + 5'd1;
    wire [4:0]  cur_burst_beats = (remaining[15:0] < {11'd0, burst_plus1}) ? remaining[4:0] : burst_plus1;
    wire        last_row = (y_idx >= y_cnt_reg - 16'd1);

    always @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            done           <= 1'b0;
            busy           <= 1'b0;
            irq            <= 1'b0;
            mem_addr       <= {ADDR_WIDTH{1'b0}};
            mem_read       <= 1'b0;
            mem_write      <= 1'b0;
            mem_wdata      <= {DATA_WIDTH{1'b0}};
            mem_burst_len  <= 4'd0;
            spad_addr      <= 10'd0;
            spad_wdata     <= {DATA_WIDTH{1'b0}};
            spad_we        <= 1'b0;
            spad_re        <= 1'b0;
            cur_src        <= {ADDR_WIDTH{1'b0}};
            cur_dst        <= {ADDR_WIDTH{1'b0}};
            row_src_base   <= {ADDR_WIDTH{1'b0}};
            row_dst_base   <= {ADDR_WIDTH{1'b0}};
            x_idx          <= 16'd0;
            y_idx          <= 16'd0;
            x_cnt_reg      <= 16'd0;
            y_cnt_reg      <= 16'd0;
            src_stride_reg <= 16'd0;
            dst_stride_reg <= 16'd0;
            dir_reg        <= 1'b0;
            burst_reg      <= 4'd0;
            beat_cnt       <= 4'd0;
        end else begin
            irq     <= 1'b0;
            spad_we <= 1'b0;
            spad_re <= 1'b0;

            case (state)
                S_IDLE: begin
                    done      <= 1'b0;
                    mem_read  <= 1'b0;
                    mem_write <= 1'b0;
                    if (start) begin
                        busy           <= 1'b1;
                        dir_reg        <= direction;
                        x_cnt_reg      <= x_count;
                        y_cnt_reg      <= y_count;
                        src_stride_reg <= src_stride;
                        dst_stride_reg <= dst_stride;
                        burst_reg      <= burst_len;
                        x_idx          <= 16'd0;
                        y_idx          <= 16'd0;
                        beat_cnt       <= 4'd0;
                        if (x_count == 16'd0 || y_count == 16'd0)
                            state <= S_DONE;
                        else if (direction == 1'b0) begin
                            cur_src       <= src_addr;
                            cur_dst       <= dst_addr;
                            row_src_base  <= src_addr;
                            row_dst_base  <= dst_addr;
                            state         <= S_LOAD_ADDR;
                        end else begin
                            cur_src       <= src_addr;
                            cur_dst       <= dst_addr;
                            row_src_base  <= src_addr;
                            row_dst_base  <= dst_addr;
                            state         <= S_STORE_READ;
                        end
                    end
                end

                // ===== LOAD: mem -> spad (burst) =====
                S_LOAD_ADDR: begin
                    mem_addr      <= cur_src;
                    mem_read      <= 1'b1;
                    mem_burst_len <= cur_burst_beats[3:0] - 4'd1;
                    beat_cnt      <= 4'd0;
                    state         <= S_LOAD_RECV;
                end

                S_LOAD_RECV: begin
                    mem_read <= 1'b0;
                    if (mem_ready) begin
                        spad_addr  <= cur_dst[9:0];
                        spad_wdata <= mem_rdata;
                        spad_we    <= 1'b1;
                        cur_dst <= cur_dst + 32'd4;
                        cur_src <= cur_src + 32'd4;

                        if (beat_cnt >= cur_burst_beats[3:0] - 4'd1)
                            state <= S_LOAD_NEXT;
                        else
                            beat_cnt <= beat_cnt + 4'd1;
                    end
                end

                S_LOAD_NEXT: begin
                    x_idx <= x_idx + {12'd0, cur_burst_beats[3:0]};
                    if (x_idx + {12'd0, cur_burst_beats[3:0]} >= x_cnt_reg) begin
                        if (last_row)
                            state <= S_DONE;
                        else begin
                            y_idx         <= y_idx + 16'd1;
                            row_src_base  <= row_src_base + {16'd0, src_stride_reg};
                            row_dst_base  <= row_dst_base + {16'd0, dst_stride_reg};
                            cur_src       <= row_src_base + {16'd0, src_stride_reg};
                            cur_dst       <= row_dst_base + {16'd0, dst_stride_reg};
                            x_idx         <= 16'd0;
                            state         <= S_LOAD_ADDR;
                        end
                    end else begin
                        state <= S_LOAD_ADDR;
                    end
                end

                // ===== STORE: spad -> mem (sequential, respects spad read latency) =====
                S_STORE_READ: begin
                    spad_addr <= cur_src[9:0];
                    spad_re   <= 1'b1;
                    mem_write <= 1'b0;
                    state     <= S_STORE_WAIT;
                end

                S_STORE_WAIT: begin
                    spad_re <= 1'b0;
                    state   <= S_STORE_WR;
                end

                S_STORE_WR: begin
                    mem_addr  <= cur_dst;
                    mem_wdata <= spad_rdata;
                    mem_write <= 1'b1;
                    mem_burst_len <= 4'd0;
                    if (mem_ready) begin
                        mem_write <= 1'b0;
                        if (x_idx >= x_cnt_reg - 16'd1) begin
                            if (last_row)
                                state <= S_DONE;
                            else begin
                                x_idx        <= 16'd0;
                                y_idx        <= y_idx + 16'd1;
                                row_src_base <= row_src_base + {16'd0, src_stride_reg};
                                row_dst_base <= row_dst_base + {16'd0, dst_stride_reg};
                                cur_src      <= row_src_base + {16'd0, src_stride_reg};
                                cur_dst      <= row_dst_base + {16'd0, dst_stride_reg};
                                state        <= S_STORE_READ;
                            end
                        end else begin
                            x_idx   <= x_idx + 16'd1;
                            cur_src <= cur_src + 32'd4;
                            cur_dst <= cur_dst + 32'd4;
                            state   <= S_STORE_READ;
                        end
                    end
                end

                S_DONE: begin
                    done      <= 1'b1;
                    busy      <= 1'b0;
                    irq       <= 1'b1;
                    spad_we   <= 1'b0;
                    spad_re   <= 1'b0;
                    mem_read  <= 1'b0;
                    mem_write <= 1'b0;
                    state     <= S_IDLE;
                end
            endcase
        end
    end

endmodule
