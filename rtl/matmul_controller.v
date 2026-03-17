// Matrix Multiplication Controller - Step 7: Write-Back
// Controls 4x4 matrix multiplication using MAC array and scratchpad memory
// Now includes result write-back to scratchpad

module matmul_controller (
    input wire clk,
    input wire rst,
    
    // Control interface
    input wire start,           // Start matrix multiplication
    input wire [9:0] a_base_addr,  // Scratchpad address for A matrix
    input wire [9:0] b_base_addr,  // Scratchpad address for B matrix
    input wire [9:0] c_base_addr,  // Scratchpad address for C matrix (results)
    output reg done,            // Operation complete
    output reg busy,            // Operation in progress
    
    // Scratchpad interface (Port B)
    output reg [9:0] spad_addr,
    output reg spad_re,         // Read enable
    input wire [31:0] spad_rdata,
    output reg spad_we,         // Write enable
    output reg [31:0] spad_wdata, // Write data
    
    // MAC Array interface (4x4 = 16 MACs)
    output reg [7:0] a_matrix [0:3][0:3],
    output reg [7:0] b_matrix [0:3][0:3],
    output reg mac_enable,
    output reg mac_accumulate,
    input wire [31:0] result_matrix [0:3][0:3]
);

    // State machine states
    localparam IDLE        = 3'd0;
    localparam INIT        = 3'd1;
    localparam LOAD_DATA   = 3'd2;
    localparam COMPUTE     = 3'd3;
    localparam WAIT_MAC    = 3'd4;
    localparam WRITE_BACK  = 3'd5;
    localparam DONE_STATE  = 3'd6;
    
    reg [2:0] state, next_state;
    
    // Internal registers for data loading
    reg [31:0] a_row_data [0:3]; // Loaded A matrix rows (4 rows)
    reg [31:0] b_row_data;       // Loaded B matrix row (1 row per pass)
    reg [4:0] load_cycle;        // Cycle counter for loading (0-31) - 5 bits!
    reg [1:0] pass_k;            // Pass counter for dot product (0,1,2,3)
    reg [1:0] write_row;         // Row counter for write-back (0-3)
    reg [31:0] result_captured [0:3][0:3]; // Captured MAC results
    integer i, j;                // Loop variables for data distribution
    
    // ========================================
    // Address Calculation Functions
    // ========================================
    
    // Calculate scratchpad word address for A[row][col]
    // A matrix is stored row-wise: each row is one 32-bit word
    // A[row][0..3] stored in word (a_base_addr + row*4)
    function [9:0] calc_a_word_addr;
        input [1:0] row;
        begin
            calc_a_word_addr = a_base_addr + {6'd0, row, 2'b00}; // row * 4
        end
    endfunction
    
    // Calculate which byte in the word for A[row][col]
    function [1:0] calc_a_byte_sel;
        input [1:0] col;
        begin
            calc_a_byte_sel = col;  // Byte 0,1,2,3 for columns 0,1,2,3
        end
    endfunction
    
    // Calculate scratchpad word address for B[row][col]
    // B matrix is stored row-wise: each row is one 32-bit word
    // B[row][0..3] stored in word (b_base_addr + row*4)
    function [9:0] calc_b_word_addr;
        input [1:0] row;
        begin
            calc_b_word_addr = b_base_addr + {6'd0, row, 2'b00}; // row * 4
        end
    endfunction
    
    // Calculate which byte in the word for B[row][col]
    function [1:0] calc_b_byte_sel;
        input [1:0] col;
        begin
            calc_b_byte_sel = col;  // Byte 0,1,2,3 for columns 0,1,2,3
        end
    endfunction
    
    // Calculate scratchpad word address for C[row][col]
    // C matrix (result) is stored row-wise
    function [9:0] calc_c_word_addr;
        input [1:0] row;
        begin
            calc_c_word_addr = c_base_addr + {6'd0, row, 2'b00}; // row * 4
        end
    endfunction
    
    // Extract byte from 32-bit word based on byte select
    function [7:0] extract_byte;
        input [31:0] word;
        input [1:0] byte_sel;
        begin
            case (byte_sel)
                2'd0: extract_byte = word[7:0];
                2'd1: extract_byte = word[15:8];
                2'd2: extract_byte = word[23:16];
                2'd3: extract_byte = word[31:24];
            endcase
        end
    endfunction
    
    // Pack 4 8-bit results into 32-bit word for writing
    function [31:0] pack_results;
        input [31:0] r0, r1, r2, r3;
        begin
            pack_results = {r3[7:0], r2[7:0], r1[7:0], r0[7:0]};
        end
    endfunction
    
    // State register
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // Next state logic
    always @(*) begin
        next_state = state;  // Default: stay in current state
        
        case (state)
            IDLE: begin
                if (start) begin
                    next_state = INIT;
                end
            end
            
            INIT: begin
                // Initialize counters and addresses
                next_state = LOAD_DATA;
            end
            
            LOAD_DATA: begin
                // Load data from scratchpad for all 16 MACs
                // Takes 16 cycles (read 4 A rows + 1 B row + distribute)
                if (load_cycle > 5'd15) begin
                    next_state = COMPUTE;
                end else begin
                    next_state = LOAD_DATA;  // Stay until done
                end
            end
            
            COMPUTE: begin
                // Enable MAC for one cycle, then wait
                next_state = WAIT_MAC;
            end
            
            WAIT_MAC: begin
                // Wait for MAC to complete, then check if we need more passes
                if (pass_k < 2'd3) begin
                    // Need more passes, go back to load data
                    next_state = LOAD_DATA;
                end else begin
                    // All 4 passes done (k=3), go to write back
                    next_state = WRITE_BACK;
                end
            end
            
            WRITE_BACK: begin
                // Write results back to scratchpad (4 rows, takes 4 cycles)
                if (write_row >= 2'd3) begin
                    next_state = DONE_STATE;
                end else begin
                    next_state = WRITE_BACK;  // Stay until all rows written
                end
            end
            
            DONE_STATE: begin
                // Signal completion
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Output and datapath logic
    always @(posedge clk) begin
        if (rst) begin
            done <= 1'b0;
            busy <= 1'b0;
            spad_addr <= 10'd0;
            spad_re <= 1'b0;
            spad_we <= 1'b0;
            spad_wdata <= 32'd0;
            load_cycle <= 5'd0;
            pass_k <= 2'd0;
            write_row <= 2'd0;
            mac_enable <= 1'b0;
            mac_accumulate <= 1'b0;
            
            // Initialize matrices
            for (i = 0; i < 4; i = i + 1) begin
                a_row_data[i] <= 32'd0;
                for (j = 0; j < 4; j = j + 1) begin
                    a_matrix[i][j] <= 8'd0;
                    b_matrix[i][j] <= 8'd0;
                    result_captured[i][j] <= 32'd0;
                end
            end
            b_row_data <= 32'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    spad_re <= 1'b0;
                    spad_we <= 1'b0;
                    load_cycle <= 5'd0;
                    pass_k <= 2'd0;
                    write_row <= 2'd0;
                    mac_enable <= 1'b0;
                end
                
                INIT: begin
                    busy <= 1'b1;
                    load_cycle <= 5'd0;
                    pass_k <= 2'd0;  // Start with pass 0
                    write_row <= 2'd0;
                    mac_enable <= 1'b0;
                    spad_we <= 1'b0;
                end
                
                LOAD_DATA: begin
                    busy <= 1'b1;
                    load_cycle <= load_cycle + 1;
                    
                    // Step 6: Load data for ALL 16 MACs (parallel)
                    // For pass k, need: All A rows (A[0..3][k]) and B row k (B[k][0..3])
                    case (load_cycle)
                        // Read A row 0
                        5'd0: begin
                            spad_addr <= calc_a_word_addr(2'd0);
                            spad_re <= 1'b1;
                        end
                        5'd1: begin
                            spad_re <= 1'b0;
                        end
                        5'd2: begin
                            a_row_data[0] <= spad_rdata;
                        end
                        
                        // Read A row 1
                        5'd3: begin
                            spad_addr <= calc_a_word_addr(2'd1);
                            spad_re <= 1'b1;
                        end
                        5'd4: begin
                            spad_re <= 1'b0;
                        end
                        5'd5: begin
                            a_row_data[1] <= spad_rdata;
                        end
                        
                        // Read A row 2
                        5'd6: begin
                            spad_addr <= calc_a_word_addr(2'd2);
                            spad_re <= 1'b1;
                        end
                        5'd7: begin
                            spad_re <= 1'b0;
                        end
                        5'd8: begin
                            a_row_data[2] <= spad_rdata;
                        end
                        
                        // Read A row 3
                        5'd9: begin
                            spad_addr <= calc_a_word_addr(2'd3);
                            spad_re <= 1'b1;
                        end
                        5'd10: begin
                            spad_re <= 1'b0;
                        end
                        5'd11: begin
                            a_row_data[3] <= spad_rdata;
                        end
                        
                        // Read B row k
                        5'd12: begin
                            spad_addr <= calc_b_word_addr(pass_k);
                            spad_re <= 1'b1;
                        end
                        5'd13: begin
                            spad_re <= 1'b0;
                        end
                        5'd14: begin
                            // Capture B row data
                            b_row_data <= spad_rdata;
                        end
                        
                        5'd15: begin
                            // Distribute data to all 16 MACs (after all data loaded)
                            spad_re <= 1'b0;
                            
                            // Manually unroll to ensure proper synthesis
                            for (i = 0; i < 4; i = i + 1) begin
                                // Column 0
                                a_matrix[i][0] <= extract_byte(a_row_data[i], pass_k[1:0]);
                                b_matrix[i][0] <= b_row_data[7:0];
                                
                                // Column 1
                                a_matrix[i][1] <= extract_byte(a_row_data[i], pass_k[1:0]);
                                b_matrix[i][1] <= b_row_data[15:8];
                                
                                // Column 2
                                a_matrix[i][2] <= extract_byte(a_row_data[i], pass_k[1:0]);
                                b_matrix[i][2] <= b_row_data[23:16];
                                
                                // Column 3
                                a_matrix[i][3] <= extract_byte(a_row_data[i], pass_k[1:0]);
                                b_matrix[i][3] <= b_row_data[31:24];
                            end
                        end
                        
                        default: begin
                            // Cycle 16+: Done, wait for state transition
                            spad_re <= 1'b0;
                        end
                    endcase
                end
                
                COMPUTE: begin
                    busy <= 1'b1;
                    spad_re <= 1'b0;
                    
                    // Step 6: Enable all 16 MACs for ONE cycle
                    // Data already loaded into a_matrix and b_matrix
                    mac_enable <= 1'b1;
                    // Accumulate if not first pass (k > 0)
                    mac_accumulate <= (pass_k != 2'd0) ? 1'b1 : 1'b0;
                end
                
                WAIT_MAC: begin
                    busy <= 1'b1;
                    mac_enable <= 1'b0;  // Turn off MAC after one cycle
                    
                    // Prepare for next pass if needed
                    if (pass_k < 2'd3) begin
                        pass_k <= pass_k + 1;
                        load_cycle <= 5'd0;  // Reset for next load
                    end else begin
                        // Last pass complete (k=3), capture final results
                        // Manually unroll to avoid indexing issues
                        result_captured[0][0] <= result_matrix[0][0];
                        result_captured[0][1] <= result_matrix[0][1];
                        result_captured[0][2] <= result_matrix[0][2];
                        result_captured[0][3] <= result_matrix[0][3];
                        
                        result_captured[1][0] <= result_matrix[1][0];
                        result_captured[1][1] <= result_matrix[1][1];
                        result_captured[1][2] <= result_matrix[1][2];
                        result_captured[1][3] <= result_matrix[1][3];
                        
                        result_captured[2][0] <= result_matrix[2][0];
                        result_captured[2][1] <= result_matrix[2][1];
                        result_captured[2][2] <= result_matrix[2][2];
                        result_captured[2][3] <= result_matrix[2][3];
                        
                        result_captured[3][0] <= result_matrix[3][0];
                        result_captured[3][1] <= result_matrix[3][1];
                        result_captured[3][2] <= result_matrix[3][2];
                        result_captured[3][3] <= result_matrix[3][3];
                    end
                end
                
                WRITE_BACK: begin
                    busy <= 1'b1;
                    mac_enable <= 1'b0;
                    spad_re <= 1'b0;
                    
                    // Step 7: Write results back to scratchpad
                    // Write one row per cycle (4 results packed into 32 bits)
                    // Read directly from result_matrix (like Step 6 testbench does)
                    case (write_row)
                        2'd0: begin
                            spad_addr <= calc_c_word_addr(2'd0);
                            spad_wdata <= pack_results(
                                result_matrix[0][0],
                                result_matrix[0][1],
                                result_matrix[0][2],
                                result_matrix[0][3]
                            );
                            spad_we <= 1'b1;
                            write_row <= 2'd1;
                        end
                        2'd1: begin
                            spad_addr <= calc_c_word_addr(2'd1);
                            spad_wdata <= pack_results(
                                result_matrix[1][0],
                                result_matrix[1][1],
                                result_matrix[1][2],
                                result_matrix[1][3]
                            );
                            spad_we <= 1'b1;
                            write_row <= 2'd2;
                        end
                        2'd2: begin
                            spad_addr <= calc_c_word_addr(2'd2);
                            spad_wdata <= pack_results(
                                result_matrix[2][0],
                                result_matrix[2][1],
                                result_matrix[2][2],
                                result_matrix[2][3]
                            );
                            spad_we <= 1'b1;
                            write_row <= 2'd3;
                        end
                        2'd3: begin
                            spad_addr <= calc_c_word_addr(2'd3);
                            spad_wdata <= pack_results(
                                result_matrix[3][0],
                                result_matrix[3][1],
                                result_matrix[3][2],
                                result_matrix[3][3]
                            );
                            spad_we <= 1'b1;
                            // Stay at 3, state machine will move to DONE
                        end
                    endcase
                end
                
                DONE_STATE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    spad_re <= 1'b0;
                    spad_we <= 1'b0;
                end
                
                default: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    spad_re <= 1'b0;
                    spad_we <= 1'b0;
                end
            endcase
        end
    end

endmodule

