// Tiling Engine with Overlapped Load/Compute
// Dual-FSM architecture: DMA and Compute run concurrently via double-buffering.
// While computing current tile, DMA prefetches next tile into the other bank.
// Supports macro-tile sub-tiling, int8/int16, non-aligned dimensions.
module tiling_engine #(
    parameter TILE_SIZE       = 4,
    parameter MACRO_TILE_SIZE = 4,
    parameter ARRAY_SIZE      = 4,
    parameter ADDR_WIDTH      = 32
) (
    input wire clk,
    input wire rst,

    input wire        start,
    input wire        mode,
    input wire [15:0] dim_m,
    input wire [15:0] dim_k,
    input wire [15:0] dim_n,
    input wire [ADDR_WIDTH-1:0] src_a,
    input wire [ADDR_WIDTH-1:0] src_b,
    input wire [ADDR_WIDTH-1:0] dst_c,
    input wire [15:0] stride_a,
    input wire [15:0] stride_b,
    input wire [15:0] stride_c,

    output reg        done,
    output reg        busy,

    output reg        dma_start,
    output reg        dma_direction,
    output reg [ADDR_WIDTH-1:0] dma_src_addr,
    output reg [ADDR_WIDTH-1:0] dma_dst_addr,
    output reg [15:0] dma_x_count,
    output reg [15:0] dma_y_count,
    output reg [15:0] dma_src_stride,
    output reg [15:0] dma_dst_stride,
    output reg [3:0]  dma_burst_len,
    input wire        dma_done,

    output reg        matmul_start,
    output reg        matmul_mode,
    output reg [9:0]  matmul_a_base,
    output reg [9:0]  matmul_b_base,
    output reg [9:0]  matmul_c_base,
    output reg        matmul_accumulate,
    output reg [2:0]  matmul_eff_rows,
    output reg [2:0]  matmul_eff_k,
    output reg [9:0]  matmul_spad_stride,
    input wire        matmul_done,

    output reg        swap_banks
);

    localparam MTS = MACRO_TILE_SIZE;
    localparam AS  = ARRAY_SIZE;

    localparam [9:0] SPAD_A_BASE = 10'h000;

    // ======================== Main Orchestrator FSM ========================
    localparam M_IDLE         = 4'd0;
    localparam M_INIT         = 4'd1;
    localparam M_FIRST_LOAD   = 4'd2;  // load first tile (no overlap)
    localparam M_OVERLAP      = 4'd3;  // compute + prefetch concurrently
    localparam M_STORE_C      = 4'd4;  // store C from completed compute
    localparam M_WAIT_STORE   = 4'd5;
    localparam M_DONE         = 4'd6;

    // DMA sub-FSM (runs during M_FIRST_LOAD and M_OVERLAP)
    localparam D_IDLE     = 3'd0;
    localparam D_LOAD_A   = 3'd1;
    localparam D_WAIT_A   = 3'd2;
    localparam D_LOAD_B   = 3'd3;
    localparam D_WAIT_B   = 3'd4;
    localparam D_DONE     = 3'd5;

    // Compute sub-FSM (runs during M_OVERLAP)
    localparam C_IDLE     = 3'd0;
    localparam C_COMPUTE  = 3'd1;
    localparam C_WAIT     = 3'd2;
    localparam C_NEXT_SUB = 3'd3;
    localparam C_DONE     = 3'd4;

    reg [3:0] m_state;
    reg [2:0] d_state;
    reg [2:0] c_state;

    // Tile iteration
    reg [15:0] cur_m, cur_n, cur_k;    // current tile being COMPUTED
    reg [15:0] nxt_m, nxt_n, nxt_k;    // next tile to LOAD (prefetch)
    reg [15:0] num_macro_m, num_macro_n, num_macro_k;
    reg        has_next_tile;           // whether there's a tile to prefetch
    reg        first_tile;              // is this the very first tile

    // Sub-tile iteration (for compute)
    reg [3:0] sub_m, sub_n, sub_k;
    reg [3:0] num_sub_m, num_sub_n, num_sub_k;

    // Handshake flags
    reg dma_load_done;
    reg compute_done_flag;

    // Mode-dependent scratchpad geometry
    wire [15:0] elem_bytes    = mode ? 16'd2 : 16'd1;
    wire [15:0] macro_words   = mode ? (MTS[15:0] >> 1) : (MTS[15:0] >> 2);
    wire [15:0] spad_row_byt  = {macro_words[13:0], 2'b00};
    wire [15:0] region_bytes  = MTS[15:0] * spad_row_byt;
    wire [9:0]  spad_b_base_w = region_bytes[9:0];
    wire [9:0]  spad_c_base_w = region_bytes[9:0] + region_bytes[9:0];

    // Effective dimensions for PREFETCH tile (nxt_*)
    wire [15:0] nxt_rem_m = dim_m - nxt_m * MTS[15:0];
    wire [15:0] nxt_rem_k = dim_k - nxt_k * MTS[15:0];
    wire [15:0] nxt_rem_n = dim_n - nxt_n * MTS[15:0];
    wire [15:0] nxt_eff_m = (nxt_rem_m >= MTS[15:0]) ? MTS[15:0] : nxt_rem_m;
    wire [15:0] nxt_eff_k = (nxt_rem_k >= MTS[15:0]) ? MTS[15:0] : nxt_rem_k;
    wire [15:0] nxt_eff_n = (nxt_rem_n >= MTS[15:0]) ? MTS[15:0] : nxt_rem_n;

    // Effective dimensions for COMPUTE tile (cur_*)
    wire [15:0] cur_rem_m = dim_m - cur_m * MTS[15:0];
    wire [15:0] cur_rem_k = dim_k - cur_k * MTS[15:0];
    wire [15:0] cur_rem_n = dim_n - cur_n * MTS[15:0];
    wire [15:0] cur_eff_m = (cur_rem_m >= MTS[15:0]) ? MTS[15:0] : cur_rem_m;
    wire [15:0] cur_eff_k = (cur_rem_k >= MTS[15:0]) ? MTS[15:0] : cur_rem_k;
    wire [15:0] cur_eff_n = (cur_rem_n >= MTS[15:0]) ? MTS[15:0] : cur_rem_n;

    // DMA addresses for nxt tile
    wire [ADDR_WIDTH-1:0] nxt_a_addr = src_a
        + ({16'd0, nxt_m} * MTS[15:0]) * {16'd0, stride_a}
        + ({16'd0, nxt_k} * MTS[15:0]) * {16'd0, elem_bytes};
    wire [ADDR_WIDTH-1:0] nxt_b_addr = src_b
        + ({16'd0, nxt_k} * MTS[15:0]) * {16'd0, stride_b}
        + ({16'd0, nxt_n} * MTS[15:0]) * {16'd0, elem_bytes};

    // DMA store address for cur tile
    wire [ADDR_WIDTH-1:0] cur_c_addr = dst_c
        + ({16'd0, cur_m} * MTS[15:0]) * {16'd0, stride_c}
        + ({16'd0, cur_n} * MTS[15:0]) * {16'd0, elem_bytes};

    // Effective store width: only write the words that contain valid columns.
    // Prevents partial-N tiles from overwriting adjacent output memory.
    wire [15:0] cur_store_words = mode
        ? ((cur_eff_n + 16'd1) >> 1)    // int16: 2 elements per word
        : ((cur_eff_n + 16'd3) >> 2);   // int8:  4 elements per word

    // Sub-tile addresses (for compute on compute-side bank)
    wire [9:0] sub_m_x_as = {6'd0, sub_m[1:0], 2'b00};
    wire [9:0] sub_k_x_as = {6'd0, sub_k[1:0], 2'b00};
    wire [9:0] sub_n_x_as = {6'd0, sub_n[1:0], 2'b00};

    wire [9:0] sm_row_off = sub_m_x_as * spad_row_byt[9:0];
    wire [9:0] sk_row_off = sub_k_x_as * spad_row_byt[9:0];
    wire [9:0] sk_col_off = sub_k_x_as * elem_bytes[9:0];
    wire [9:0] sn_col_off = sub_n_x_as * elem_bytes[9:0];

    wire [9:0] a_sub_base = SPAD_A_BASE   + sm_row_off + sk_col_off;
    wire [9:0] b_sub_base = spad_b_base_w + sk_row_off + sn_col_off;
    wire [9:0] c_sub_base = spad_c_base_w + sm_row_off + sn_col_off;

    // Effective sub-tile dimensions
    wire [15:0] eff_m_sub_full = cur_eff_m - {12'd0, sub_m} * AS[15:0];
    wire [15:0] eff_k_sub_full = cur_eff_k - {12'd0, sub_k} * AS[15:0];
    wire [2:0]  eff_m_sub = (eff_m_sub_full >= AS[15:0]) ? AS[2:0] : eff_m_sub_full[2:0];
    wire [2:0]  eff_k_sub = (eff_k_sub_full >= AS[15:0]) ? AS[2:0] : eff_k_sub_full[2:0];

    function [15:0] ceil_div_mts;
        input [15:0] x;
        begin
            ceil_div_mts = (x + MTS - 1) / MTS;
        end
    endfunction

    function [3:0] ceil_div_as;
        input [15:0] x;
        begin
            ceil_div_as = (x + AS - 1) / AS;
        end
    endfunction

    // Advance nxt tile to next position in the tile grid
    // Order: K -> N -> M. Returns has_next=1 if there's a valid next tile.
    // For K-accumulation: increment K first; when K wraps, store C then advance N/M.
    task advance_nxt_tile;
        begin
            if (nxt_k < num_macro_k - 16'd1) begin
                nxt_k <= nxt_k + 16'd1;
                has_next_tile <= 1'b1;
            end else if (nxt_n < num_macro_n - 16'd1) begin
                nxt_k <= 16'd0;
                nxt_n <= nxt_n + 16'd1;
                has_next_tile <= 1'b1;
            end else if (nxt_m < num_macro_m - 16'd1) begin
                nxt_k <= 16'd0;
                nxt_n <= 16'd0;
                nxt_m <= nxt_m + 16'd1;
                has_next_tile <= 1'b1;
            end else begin
                has_next_tile <= 1'b0;
            end
        end
    endtask

    // ======================== Main FSM ========================
    always @(posedge clk) begin
        if (rst) begin
            m_state    <= M_IDLE;
            d_state    <= D_IDLE;
            c_state    <= C_IDLE;
            done       <= 1'b0;
            busy       <= 1'b0;
            swap_banks <= 1'b0;
            dma_start  <= 1'b0;
            dma_direction  <= 1'b0;
            dma_src_addr   <= {ADDR_WIDTH{1'b0}};
            dma_dst_addr   <= {ADDR_WIDTH{1'b0}};
            dma_x_count    <= 16'd0;
            dma_y_count    <= 16'd0;
            dma_src_stride <= 16'd0;
            dma_dst_stride <= 16'd0;
            dma_burst_len  <= 4'd0;
            matmul_start   <= 1'b0;
            matmul_mode    <= 1'b0;
            matmul_a_base  <= 10'd0;
            matmul_b_base  <= 10'd0;
            matmul_c_base  <= 10'd0;
            matmul_accumulate <= 1'b0;
            matmul_eff_rows   <= 3'd4;
            matmul_eff_k      <= 3'd4;
            matmul_spad_stride<= 10'd4;
            cur_m <= 16'd0; cur_n <= 16'd0; cur_k <= 16'd0;
            nxt_m <= 16'd0; nxt_n <= 16'd0; nxt_k <= 16'd0;
            num_macro_m <= 16'd0; num_macro_n <= 16'd0; num_macro_k <= 16'd0;
            sub_m <= 4'd0; sub_n <= 4'd0; sub_k <= 4'd0;
            num_sub_m <= 4'd0; num_sub_n <= 4'd0; num_sub_k <= 4'd0;
            has_next_tile   <= 1'b0;
            first_tile      <= 1'b1;
            dma_load_done   <= 1'b0;
            compute_done_flag <= 1'b0;
        end else begin
            dma_start    <= 1'b0;
            matmul_start <= 1'b0;
            swap_banks   <= 1'b0;

            case (m_state)
                M_IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    if (start) begin
                        busy        <= 1'b1;
                        cur_m       <= 16'd0;
                        cur_n       <= 16'd0;
                        cur_k       <= 16'd0;
                        nxt_m       <= 16'd0;
                        nxt_n       <= 16'd0;
                        nxt_k       <= 16'd0;
                        num_macro_m <= ceil_div_mts(dim_m);
                        num_macro_n <= ceil_div_mts(dim_n);
                        num_macro_k <= ceil_div_mts(dim_k);
                        first_tile  <= 1'b1;
                        has_next_tile <= 1'b1;
                        m_state     <= M_INIT;
                    end
                end

                M_INIT: begin
                    d_state <= D_LOAD_A;
                    m_state <= M_FIRST_LOAD;
                end

                // ===== FIRST LOAD: sequential, no overlap =====
                M_FIRST_LOAD: begin
                    case (d_state)
                        D_LOAD_A: begin
                            dma_start     <= 1'b1;
                            dma_direction <= 1'b0;
                            dma_src_addr  <= nxt_a_addr;
                            dma_dst_addr  <= {22'd0, SPAD_A_BASE};
                            dma_x_count   <= macro_words;
                            dma_y_count   <= nxt_eff_m;
                            dma_src_stride<= stride_a;
                            dma_dst_stride<= spad_row_byt;
                            dma_burst_len <= macro_words[3:0] - 4'd1;
                            d_state       <= D_WAIT_A;
                        end
                        D_WAIT_A: begin
                            if (dma_done) d_state <= D_LOAD_B;
                        end
                        D_LOAD_B: begin
                            dma_start     <= 1'b1;
                            dma_direction <= 1'b0;
                            dma_src_addr  <= nxt_b_addr;
                            dma_dst_addr  <= {22'd0, spad_b_base_w};
                            dma_x_count   <= macro_words;
                            dma_y_count   <= nxt_eff_k;
                            dma_src_stride<= stride_b;
                            dma_dst_stride<= spad_row_byt;
                            dma_burst_len <= macro_words[3:0] - 4'd1;
                            d_state       <= D_WAIT_B;
                        end
                        D_WAIT_B: begin
                            if (dma_done) begin
                                d_state <= D_IDLE;
                                // First tile loaded: swap, set up compute, maybe prefetch
                                swap_banks <= 1'b1;
                                cur_m <= nxt_m;
                                cur_n <= nxt_n;
                                cur_k <= nxt_k;
                                first_tile <= 1'b0;

                                // Set up compute
                                c_state <= C_COMPUTE;
                                sub_m   <= 4'd0;
                                sub_n   <= 4'd0;
                                sub_k   <= 4'd0;
                                compute_done_flag <= 1'b0;

                                // Advance nxt and start prefetch if available
                                advance_nxt_tile;
                                dma_load_done <= 1'b0;

                                m_state <= M_OVERLAP;
                            end
                        end
                        default: d_state <= D_IDLE;
                    endcase
                end

                // ===== OVERLAP: concurrent DMA + Compute =====
                M_OVERLAP: begin
                    // ---------- DMA sub-FSM ----------
                    case (d_state)
                        D_IDLE: begin
                            if (has_next_tile && !dma_load_done) begin
                                d_state <= D_LOAD_A;
                            end else begin
                                dma_load_done <= 1'b1;
                            end
                        end
                        D_LOAD_A: begin
                            dma_start     <= 1'b1;
                            dma_direction <= 1'b0;
                            dma_src_addr  <= nxt_a_addr;
                            dma_dst_addr  <= {22'd0, SPAD_A_BASE};
                            dma_x_count   <= macro_words;
                            dma_y_count   <= nxt_eff_m;
                            dma_src_stride<= stride_a;
                            dma_dst_stride<= spad_row_byt;
                            dma_burst_len <= macro_words[3:0] - 4'd1;
                            d_state       <= D_WAIT_A;
                        end
                        D_WAIT_A: begin
                            if (dma_done) d_state <= D_LOAD_B;
                        end
                        D_LOAD_B: begin
                            dma_start     <= 1'b1;
                            dma_direction <= 1'b0;
                            dma_src_addr  <= nxt_b_addr;
                            dma_dst_addr  <= {22'd0, spad_b_base_w};
                            dma_x_count   <= macro_words;
                            dma_y_count   <= nxt_eff_k;
                            dma_src_stride<= stride_b;
                            dma_dst_stride<= spad_row_byt;
                            dma_burst_len <= macro_words[3:0] - 4'd1;
                            d_state       <= D_WAIT_B;
                        end
                        D_WAIT_B: begin
                            if (dma_done) begin
                                dma_load_done <= 1'b1;
                                d_state       <= D_DONE;
                            end
                        end
                        D_DONE: ; // stay here until main FSM resets
                        default: d_state <= D_IDLE;
                    endcase

                    // ---------- Compute sub-FSM ----------
                    case (c_state)
                        C_COMPUTE: begin
                            matmul_start       <= 1'b1;
                            matmul_mode        <= mode;
                            matmul_a_base      <= a_sub_base;
                            matmul_b_base      <= b_sub_base;
                            matmul_c_base      <= c_sub_base;
                            matmul_accumulate  <= (cur_k > 16'd0) | (sub_k > 4'd0);
                            matmul_eff_rows    <= (eff_m_sub == 3'd0) ? 3'd4 : eff_m_sub;
                            matmul_eff_k       <= (eff_k_sub == 3'd0) ? 3'd4 : eff_k_sub;
                            matmul_spad_stride <= spad_row_byt[9:0];
                            num_sub_m          <= ceil_div_as(cur_eff_m);
                            num_sub_n          <= ceil_div_as(cur_eff_n);
                            num_sub_k          <= ceil_div_as(cur_eff_k);
                            c_state            <= C_WAIT;
                        end
                        C_WAIT: begin
                            if (matmul_done) c_state <= C_NEXT_SUB;
                        end
                        C_NEXT_SUB: begin
                            if (sub_k < num_sub_k - 4'd1) begin
                                sub_k   <= sub_k + 4'd1;
                                c_state <= C_COMPUTE;
                            end else if (sub_n < num_sub_n - 4'd1) begin
                                sub_k   <= 4'd0;
                                sub_n   <= sub_n + 4'd1;
                                c_state <= C_COMPUTE;
                            end else if (sub_m < num_sub_m - 4'd1) begin
                                sub_k   <= 4'd0;
                                sub_n   <= 4'd0;
                                sub_m   <= sub_m + 4'd1;
                                c_state <= C_COMPUTE;
                            end else begin
                                compute_done_flag <= 1'b1;
                                c_state           <= C_DONE;
                            end
                        end
                        C_DONE: ;
                        default: c_state <= C_IDLE;
                    endcase

                    // ---------- Coordination ----------
                    if (compute_done_flag && dma_load_done) begin
                        // Check if current tile needs a K-continuation
                        if (cur_k < num_macro_k - 16'd1) begin
                            // More K tiles: swap, load next K-tile (already prefetched)
                            // Move to compute the next K-pass on the prefetched data
                            swap_banks <= 1'b1;
                            cur_m <= nxt_m;
                            cur_n <= nxt_n;
                            cur_k <= nxt_k;
                            c_state <= C_COMPUTE;
                            sub_m   <= 4'd0;
                            sub_n   <= 4'd0;
                            sub_k   <= 4'd0;
                            compute_done_flag <= 1'b0;
                            advance_nxt_tile;
                            dma_load_done <= 1'b0;
                            d_state       <= D_IDLE;
                        end else begin
                            // K-tiles done for this output tile: store C, then next output tile
                            swap_banks <= 1'b1;
                            m_state    <= M_STORE_C;
                        end
                    end
                end

                // ===== STORE C =====
                M_STORE_C: begin
                    dma_start     <= 1'b1;
                    dma_direction <= 1'b1;
                    dma_src_addr  <= {22'd0, spad_c_base_w};
                    dma_dst_addr  <= cur_c_addr;
                    dma_x_count   <= cur_store_words;
                    dma_y_count   <= cur_eff_m;
                    dma_src_stride<= spad_row_byt;
                    dma_dst_stride<= stride_c;
                    dma_burst_len <= cur_store_words[3:0] - 4'd1;
                    m_state       <= M_WAIT_STORE;
                end

                M_WAIT_STORE: begin
                    if (dma_done) begin
                        if (!has_next_tile) begin
                            m_state <= M_DONE;
                        end else begin
                            // Prefetched data is already on compute-side bank; no swap needed
                            cur_m <= nxt_m;
                            cur_n <= nxt_n;
                            cur_k <= nxt_k;
                            c_state <= C_COMPUTE;
                            sub_m   <= 4'd0;
                            sub_n   <= 4'd0;
                            sub_k   <= 4'd0;
                            compute_done_flag <= 1'b0;
                            advance_nxt_tile;
                            dma_load_done <= 1'b0;
                            d_state       <= D_IDLE;
                            m_state       <= M_OVERLAP;
                        end
                    end
                end

                M_DONE: begin
                    done    <= 1'b1;
                    busy    <= 1'b0;
                    m_state <= M_IDLE;
                end
            endcase
        end
    end

endmodule
