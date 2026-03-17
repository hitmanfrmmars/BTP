// Simple DMA Controller
// Transfers data between main memory and scratchpad memory
module dma_controller #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    
    // Control interface
    input wire start,                      // Start transfer
    input wire [ADDR_WIDTH-1:0] src_addr,  // Source address (main memory)
    input wire [ADDR_WIDTH-1:0] dst_addr,  // Destination address (scratchpad)
    input wire [15:0] transfer_size,       // Number of words to transfer
    output reg done,                       // Transfer complete
    output reg busy,                       // Transfer in progress
    
    // Main memory interface (simplified)
    output reg [ADDR_WIDTH-1:0] mem_addr,
    output reg mem_read,
    input wire [DATA_WIDTH-1:0] mem_rdata,
    input wire mem_ready,
    
    // Scratchpad interface (Port A)
    output reg [9:0] spad_addr,            // Scratchpad address
    output reg [DATA_WIDTH-1:0] spad_wdata,
    output reg spad_we,
    output reg spad_re,
    input wire [DATA_WIDTH-1:0] spad_rdata
);

    // State machine
    localparam IDLE = 3'd0;
    localparam READ_MEM = 3'd1;
    localparam WAIT_MEM = 3'd2;
    localparam WRITE_SPAD = 3'd3;
    localparam DONE_STATE = 3'd4;
    
    reg [2:0] state, next_state;
    reg [15:0] transfer_count;
    reg [ADDR_WIDTH-1:0] current_src_addr;
    reg [9:0] current_dst_addr;
    
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
        next_state = state;
        case (state)
            IDLE: begin
                if (start) begin
                    next_state = READ_MEM;
                end
            end
            
            READ_MEM: begin
                next_state = WAIT_MEM;
            end
            
            WAIT_MEM: begin
                if (mem_ready) begin
                    next_state = WRITE_SPAD;
                end
            end
            
            WRITE_SPAD: begin
                if (transfer_count >= transfer_size) begin
                    next_state = DONE_STATE;
                end else begin
                    next_state = READ_MEM;
                end
            end
            
            DONE_STATE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Output and datapath logic
    always @(posedge clk) begin
        if (rst) begin
            done <= 1'b0;
            busy <= 1'b0;
            transfer_count <= 16'd0;
            current_src_addr <= 32'd0;
            current_dst_addr <= 10'd0;
            mem_addr <= 32'd0;
            mem_read <= 1'b0;
            spad_addr <= 10'd0;
            spad_wdata <= 32'd0;
            spad_we <= 1'b0;
            spad_re <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    mem_read <= 1'b0;
                    spad_we <= 1'b0;
                    spad_re <= 1'b0;
                    
                    if (start) begin
                        busy <= 1'b1;
                        transfer_count <= 16'd0;
                        current_src_addr <= src_addr;
                        current_dst_addr <= dst_addr[9:0];
                    end
                end
                
                READ_MEM: begin
                    mem_addr <= current_src_addr;
                    mem_read <= 1'b1;
                    spad_we <= 1'b0;
                end
                
                WAIT_MEM: begin
                    mem_read <= 1'b0;
                    // Wait for memory to respond
                end
                
                WRITE_SPAD: begin
                    spad_addr <= current_dst_addr;
                    spad_wdata <= mem_rdata;
                    spad_we <= 1'b1;
                    
                    transfer_count <= transfer_count + 1;
                    current_src_addr <= current_src_addr + 4; // Increment by 4 bytes
                    current_dst_addr <= current_dst_addr + 4;
                end
                
                DONE_STATE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    spad_we <= 1'b0;
                end
            endcase
        end
    end

endmodule


