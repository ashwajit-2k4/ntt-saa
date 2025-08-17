module systolic_wrapper #(
    // Dimensions of 2D NTT (N = N1 * N2)
    parameter N1 = 16,          
    parameter N2 = 16,
    parameter ARRAY_ROWS = 4,                     // Number of rows in the systolic array
    parameter ARRAY_COLUMNS = 4,                  // Number of columns in the systolic array
    parameter DATA_WIDTH = 32,                     // Bit-width of the data
    parameter INPUT_LENGTH = 6                     // Maximum length of the input vectors
) (
    // Replace large input/output matrices with memory interfaces
    input clk,       // Clock signal
    input srstn,     // Synchronous reset signal
    input start,     // Start signal
    // Memory interfaces
    output reg [31:0] w_addr,      // Address bus for W_mat/W_mat2 buffer (read)
    output reg [31:0] x_addr,      // Address bus for X_mat/X_mat2 buffer (read)
    output reg [31:0] mem_write_addr, // Separate address bus for output writes
    output reg mem_read_w,         // Read enable for W buffer
    output reg mem_read_x,         // Read enable for X buffer
    output reg mem_write,          // Write enable
    output reg [DATA_WIDTH*ARRAY_ROWS-1:0] mem_wdata,   // Data to write (wider)
    input [DATA_WIDTH*ARRAY_ROWS-1:0] w_rdata,          // Data read from W buffer (wider)
    input [DATA_WIDTH*ARRAY_ROWS-1:0] x_rdata,          // Data read from X buffer (wider)
    output reg done,
    // Debugging outputs
    output reg [ARRAY_ROWS*DATA_WIDTH-1:0] debug_A_tile,        
    output reg [ARRAY_COLUMNS*DATA_WIDTH-1:0] debug_B_tile,
    output reg [3:0] debug_state,
    output reg [N1*N2*DATA_WIDTH-1:0] debug_X2_mat
);

// State machine states
localparam IDLE = 0, LOAD_ONE = 1, RUN_ONE = 2, STORE_ONE = 3, LOAD_TWO = 4, RUN_TWO = 5, STORE_TWO = 6, DONE = 7;
reg [3:0] state;

integer tile_row, tile_col; // Current tile row and column
reg [15:0] K;               // Size of matrices in systolic array    

reg[N1*N2*DATA_WIDTH-1:0] X2_mat; // Intermediate matrix after first multiplication

// Internal registers for A and B tiles
reg [ARRAY_ROWS*DATA_WIDTH-1:0] A_tile; // Only one row at a time
reg [ARRAY_COLUMNS*DATA_WIDTH-1:0] B_tile; // Only one column at a time

// Internal signals for multiplication outcome and debug outputs
wire [ARRAY_COLUMNS*ARRAY_ROWS*DATA_WIDTH-1:0] mul_outcome;
wire [(ARRAY_ROWS*ARRAY_COLUMNS*DATA_WIDTH)-1:0] debug_acc;

// === Added for compatibility with systolic_new ===
wire mode0_active; // New output from systolic_new
wire [DATA_WIDTH*ARRAY_COLUMNS-1:0] out_array; // Output array from systolic_new
// =============================================

// Internal signals for shifting and running state
wire running, shifting;

// Register to hold the start signal for ALU operation
reg alu_start;

// Instantiate the systolic array module
systolic_new #(
    .ARRAY_ROWS(ARRAY_ROWS),
    .ARRAY_COLUMNS(ARRAY_COLUMNS),
    .DATA_WIDTH(DATA_WIDTH),
    .INPUT_LENGTH(INPUT_LENGTH)
) dut (
    .clk(clk),
    .srstn(srstn),
    .alu_start_0(alu_start),
    .alu_start_1(1'b0),
    .alu_start_2(1'b0),
    .K0(K[11:0]),
    .K1(12'b0),
    .K2(12'b0),
    .w_scale(1'b0),
    .A_vec(A_tile),
    .B_vec(B_tile),
    .mul_outcome(mul_outcome),
    .out_array(out_array),
    .mode0_active(mode0_active),
    // Debug outputs
    .debug_a0(debug_a0),
    .debug_b0(debug_b0),
    .debug_pe0(debug_pe0),
    .debug_A_shift(),
    .debug_B_shift(),
    .debug_mac(),
    .debug_out_buffer()
);



// Loop variables
integer i, j;
reg [31:0] cycle_count;
reg [31:0] output_count;
reg removing_results;

// Declaration for mem_addr
reg [31:0] mem_addr; 
// Declaration for w_scale
reg w_scale;         

// Main always block: controls the systolic wrapper pipeline and memory interface
always @(posedge clk) begin
    // Synchronous reset logic
    if (~srstn) begin

        // Reset all state and control variables
        state <= IDLE;
        tile_row <= 0;
        tile_col <= 0;
        alu_start <= 0;
        done <= 0;
        X2_mat <= 0;
        mem_wdata <= 0;
        mem_write <= 0;
        mem_read_w <= 0;
        mem_read_x <= 0;
        mem_addr <= 0;
        mem_write_addr <= 0;
        cycle_count <= 0;
        output_count <= 0;
        removing_results <= 0;

    end else begin
        
        // --- State machine for pipelined systolic operation ---
        case (state)
            IDLE: begin
                // Wait for start signal, reset counters and flags
                done <= 0;
                removing_results <= 0;
                output_count <= 0;
                cycle_count <= 0;
                if (start) begin
                    tile_row <= 0;
                    tile_col <= 0;
                    state <= RUN_ONE;
                    K <= N1;
                    alu_start <= 1; // Start computation
                end
            end
            
            RUN_ONE: begin
                // --- Constantly load A_tile and B_tile from separate buffers ---
                // For each row in the tile, load from W buffer if in bounds
                if (mode0_active) begin
                    if (tile_row*ARRAY_ROWS < N1) begin
                        // Byte addressing: each entry is DATA_WIDTH*ARRAY_ROWS bits = 4*ARRAY_ROWS bytes
                        w_addr <= ((tile_row*ARRAY_ROWS + cycle_count)*N1 + tile_col*ARRAY_COLUMNS) * (DATA_WIDTH*ARRAY_ROWS/8);
                        mem_read_w <= 1;
                        A_tile <= w_rdata;
                    end else begin
                            A_tile <= 0;
                        end

                    // For each column in the tile, load from X buffer if in bounds
                    if (tile_col*ARRAY_COLUMNS < N2) begin
                        x_addr <= ((tile_row*ARRAY_ROWS)*N2 + (tile_col*ARRAY_COLUMNS + cycle_count)) * (DATA_WIDTH*ARRAY_ROWS/8);
                        mem_read_x <= 1;
                        B_tile <= x_rdata;
                    end else begin
                        B_tile <= 0;
                    end
                end
                
                // Computation running, count cycles
                alu_start <= 0;
                
                // After K cycles, start removing results
                if (cycle_count == K + 10) begin
                    output_count <= 0;
                    cycle_count <= 10; // Reset cycle count for output
                    removing_results <= 1; // Start removing results
                end else begin
                    cycle_count <= cycle_count + 1; // Increment cycle count
                end

                // Output results for ARRAY_COLUMNS cycles
                if (removing_results) begin
                    mem_write <= 1; // Enable memory write
                    for (i = 0; i < ARRAY_ROWS; i = i + 1) begin
                        for (j = 0; j < ARRAY_COLUMNS; j = j + 1) begin
                            mem_write_addr <= ((tile_row*ARRAY_ROWS + cycle_count)*N2 + (tile_col*ARRAY_COLUMNS)) * (DATA_WIDTH*ARRAY_ROWS/8); // Byte addressing
                            mem_wdata[i*DATA_WIDTH +: DATA_WIDTH] <= out_array[i*DATA_WIDTH +: DATA_WIDTH]; // Output data
                        end
                    end
                    output_count <= output_count + 1;
                    // After ARRAY_COLUMNS cycles, move to next tile
                    if (output_count == ARRAY_COLUMNS-1) begin
                        removing_results <= 0;
                        cycle_count <= 0;
                        // Move to next tile in row or column
                        if (tile_col < (N2/ARRAY_COLUMNS)-1) begin
                            tile_col <= tile_col + 1;
                            w_scale <= 0;
                        end else if (tile_row < (N1/ARRAY_ROWS)-1) begin
                            tile_col <= 0;
                            tile_row <= tile_row + 1;
                            w_scale <= 1;
                        end else begin
                            state <= DONE; // All tiles processed
                        end
                    end
                end else begin
                    mem_write <= 0; // Disable memory write
                end
            end
            DONE: begin
                // Signal completion and return to IDLE
                done <= 1;
                state <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end
end

assign debug_mul_outcome = mul_outcome;
assign debug_pe_result = mul_outcome;

// Debugging outputs
always @(*) begin
    debug_A_tile <= A_tile;
    debug_B_tile <= B_tile;
    debug_state <= state;
    debug_X2_mat <= X2_mat;
end

endmodule
