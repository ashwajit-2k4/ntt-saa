module systolic_tb;
    // Parameters
    parameter N1 = 4;
    parameter N2 = 4;
    parameter INPUT_LENGTH = (N1 > N2) ? N1 : N2;
    parameter ARRAY_ROWS = 4;
    parameter ARRAY_COLUMNS = 4;
    parameter DATA_WIDTH = 32;
    parameter MEM_SIZE = N1*N1 + N1*N2 + N2*N2 + N1*N2; // Enough for all matrices

    reg clk;
    reg srstn;
    reg start;
    wire done;

    // Memory model
    reg [DATA_WIDTH*ARRAY_ROWS-1:0] w_buffer [0:N1*N1+N2*N2-1]; // Buffer for W_mat and W_mat2, wide
    reg [DATA_WIDTH*ARRAY_ROWS-1:0] x_buffer [0:N1*N2-1]; // Buffer for X_mat and X_mat2 (reuse), wide
    reg [DATA_WIDTH*ARRAY_ROWS-1:0] output_buffer [0:N1*N2-1]; // Output buffer for results, wide

    // New interface wires
    wire [31:0] w_addr;
    wire [31:0] x_addr;
    wire [31:0] mem_write_addr;
    wire mem_read_w, mem_read_x, mem_write;
    wire [DATA_WIDTH*ARRAY_ROWS-1:0] mem_wdata;
    reg [DATA_WIDTH*ARRAY_ROWS-1:0] w_rdata, x_rdata;

    // Debug and output signals
    wire [ARRAY_ROWS*DATA_WIDTH-1:0] debug_A_tile;
    wire [ARRAY_COLUMNS*DATA_WIDTH-1:0] debug_B_tile;
    wire [(ARRAY_ROWS*ARRAY_COLUMNS*DATA_WIDTH)-1:0] debug_mul_outcome;
    wire [3:0] debug_state;
    wire [N1*N2*DATA_WIDTH-1:0] debug_X2_mat;
    wire [(ARRAY_ROWS*ARRAY_COLUMNS*DATA_WIDTH)-1:0] debug_pe_result;
    wire [DATA_WIDTH-1:0] debug_a0;
    wire [DATA_WIDTH-1:0] debug_b0;
    wire [DATA_WIDTH-1:0] debug_pe0;
    // Additional debug signals
    wire [ARRAY_ROWS*DATA_WIDTH-1:0] debug_A_shift;
    wire [ARRAY_COLUMNS*DATA_WIDTH-1:0] debug_B_shift;
    wire [(ARRAY_ROWS*ARRAY_COLUMNS*DATA_WIDTH)-1:0] debug_mac;
    wire [(ARRAY_ROWS*ARRAY_COLUMNS*DATA_WIDTH)-1:0] debug_out_buffer;

    // Instantiate the systolic_wrapper
    systolic_wrapper #(
        .N1(N1),
        .N2(N2),
        .INPUT_LENGTH(INPUT_LENGTH),
        .ARRAY_ROWS(ARRAY_ROWS),
        .ARRAY_COLUMNS(ARRAY_COLUMNS),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .srstn(srstn),
        .start(start),
        .w_addr(w_addr),
        .x_addr(x_addr),
        .mem_write_addr(mem_write_addr),
        .mem_read_w(mem_read_w),
        .mem_read_x(mem_read_x),
        .mem_write(mem_write),
        .mem_wdata(mem_wdata),
        .w_rdata(w_rdata),
        .x_rdata(x_rdata),
        .done(done),
        .debug_A_tile(debug_A_tile),
        .debug_B_tile(debug_B_tile),
        .debug_state(debug_state),
        .debug_X2_mat(debug_X2_mat)
    );

    // Memory read/write logic for new interface
    always @(posedge clk) begin
        // W buffer read
        if (mem_read_w) begin
            w_rdata <= w_buffer[w_addr >> $clog2(DATA_WIDTH*ARRAY_ROWS/8)];
        end
        // X buffer read
        if (mem_read_x) begin
            x_rdata <= x_buffer[x_addr >> $clog2(DATA_WIDTH*ARRAY_ROWS/8)];
        end
        // Output write
        if (mem_write) begin
            output_buffer[mem_write_addr >> $clog2(DATA_WIDTH*ARRAY_ROWS/8)] <= mem_wdata;
        end
    end

    // Clock generation
    initial begin
        clk = 0;
        for (integer i = 0; i < 1000; i = i + 1) begin
            #5 clk = ~clk;
        end
    end
    integer i, j, addr;

    // Reset and stimulus
    initial begin
        srstn = 0;
        start = 0;
        #20;
        srstn = 1;
        #20;
        // Initialize W_mat in w_buffer
        for (i = 0; i < N1; i = i + 1) begin
            for (j = 0; j < N1; j = j + 1) begin
                w_buffer[i*N1+j] = (i == j) ? 2 : 0;
            end
        end
        // Initialize W_mat2 in w_buffer (after W_mat)
        for (i = 0; i < N2; i = i + 1) begin
            for (j = 0; j < N2; j = j + 1) begin
                w_buffer[N1*N1 + i*N2+j] = (i == j) ? 1 : 0;
            end
        end
        // Initialize X_mat in x_buffer
        for (i = 0; i < N1; i = i + 1) begin
            for (j = 0; j < N2; j = j + 1) begin
                x_buffer[i*N2+j] = (i == j) ? 1 : 0;
            end
        end
        // X_mat2 can be written later as needed
        // Start operation
        #20;
        start = 1;
        #10;
        start = 0;
        // Wait for done
        $display("Waiting for done...");
        wait(done);
        $display("Done signal received! Printing output...");
        // Print output matrix Y_mat (from output_buffer)
        $display("Output matrix Y:");
        for (i = 0; i < N1; i = i + 1) begin
            $write("Y[%0d]: ", i);
            for (j = 0; j < N2; j = j + 1) begin
                $write("%0d ", output_buffer[i*N2+j]);
            end
            $write("\n");
        end
        $display("---");
        #100;
        $finish;
    end
endmodule
