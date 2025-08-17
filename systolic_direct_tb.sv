// Testbench for testing systolic array module directly
`timescale 1ns/1ps

module systolic_direct_tb;
    // Parameters - using smaller dimensions for easier debugging
    parameter ARRAY_ROWS = 10;
    parameter ARRAY_COLUMNS = 10;
    parameter K = 10;
    parameter DATA_WIDTH = 32;
    parameter EXTRA_BITS = 8;
    parameter OUTCOME_WIDTH = DATA_WIDTH + EXTRA_BITS;

    // Clock and control signals
    reg clk;
    reg srstn;
    reg alu_start;

    // Input matrices (as flattened vectors)
    reg [ARRAY_ROWS*K*DATA_WIDTH-1:0] A_vec;
    reg [K*ARRAY_COLUMNS*DATA_WIDTH-1:0] B_vec;

    // Output signals
    wire [(ARRAY_COLUMNS*ARRAY_ROWS*DATA_WIDTH)-1:0] mul_outcome;
    wire [DATA_WIDTH-1:0] debug_a0;
    wire [DATA_WIDTH-1:0] debug_b0;
    wire [DATA_WIDTH-1:0] debug_pe0;
    wire [ARRAY_ROWS*DATA_WIDTH-1:0] debug_A_shift;
    wire [ARRAY_COLUMNS*DATA_WIDTH-1:0] debug_B_shift;
    wire [(ARRAY_ROWS*ARRAY_COLUMNS*DATA_WIDTH)-1:0] debug_pe_result;
    wire [(ARRAY_ROWS*ARRAY_COLUMNS*DATA_WIDTH)-1:0] debug_mac;
    wire [(ARRAY_ROWS*ARRAY_COLUMNS*DATA_WIDTH)-1:0] debug_out_buffer;
    wire mode0_active;
    wire [ARRAY_COLUMNS*DATA_WIDTH-1:0] out_array;

    // For storing test matrices
    reg [DATA_WIDTH-1:0] A [0:ARRAY_ROWS-1][0:K-1];
    reg [DATA_WIDTH-1:0] B [0:K-1][0:ARRAY_COLUMNS-1];
    reg [2*DATA_WIDTH-1:0] C_expected [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
    reg [2*DATA_WIDTH-1:0] C_actual [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];

    // Instantiate systolic_new array
    systolic_new #(
        .ARRAY_ROWS(ARRAY_ROWS),
        .ARRAY_COLUMNS(ARRAY_COLUMNS),
        .DATA_WIDTH(DATA_WIDTH),
        .INPUT_LENGTH(K)
    ) dut (
        .clk(clk),
        .srstn(srstn),
        .alu_start_0(alu_start),
        .alu_start_1(1'b0),
        .alu_start_2(1'b0),
        .K0(K),
        .K1(12'b0),
        .K2(12'b0),
        .w_scale(1'b0),
        .A_vec(A_vec),
        .B_vec(B_vec),
        .mul_outcome(mul_outcome),
        .out_array(out_array),
        .mode0_active(mode0_active),
        .debug_a0(debug_a0),
        .debug_b0(debug_b0),
        .debug_pe0(debug_pe0),
        .debug_A_shift(debug_A_shift),
        .debug_B_shift(debug_B_shift),
        .debug_mac(debug_mac),
        .debug_out_buffer(debug_out_buffer)
    );

    // Clock generation
    initial begin
        clk = 0;
        for (int i = 0; i < 1000; i = i + 1) begin
            #5 clk = ~clk;
        end
    end

    // Test stimulus
    initial begin
        // Initialize test matrices with simple values
        // A = [1 2]  B = [5 6]  Expected C = [13 16]
        //     [3 4]      [7 8]              [31 36]
        
        // Initialize A matrix
        A[0][0] = 1; A[0][1] = 0;
        A[1][0] = 0; A[1][1] = 1;
        
        // Initialize B matrix
        B[0][0] = 5; B[0][1] = 6;
        B[1][0] = 7; B[1][1] = 8;

        // Calculate expected results
        for (int i = 0; i < ARRAY_ROWS; i++) begin
            for (int j = 0; j < ARRAY_COLUMNS; j++) begin
                C_expected[i][j] = 0;
                for (int k = 0; k < K; k++) begin
                    C_expected[i][j] = C_expected[i][j] + A[i][k] * B[k][j];
                end
            end
        end

        // Convert A and B to flattened vectors
        A_vec = 0;
        B_vec = 0;
        for (int i = 0; i < ARRAY_ROWS; i++)
            for (int k = 0; k < K; k++)
                A_vec[(i*K+k)*DATA_WIDTH +: DATA_WIDTH] = A[i][k];
        
        for (int k = 0; k < K; k++)
            for (int j = 0; j < ARRAY_COLUMNS; j++)
                B_vec[(k*ARRAY_COLUMNS+j)*DATA_WIDTH +: DATA_WIDTH] = B[k][j];

        // Test sequence
        srstn = 0;
        alu_start = 0;
        @(posedge clk);
        #1 srstn = 1;
        @(posedge clk);
        #1 alu_start = 1;
        @(posedge clk);
        #1 alu_start = 0;


        // Extract and check results
        for (int i = 0; i < ARRAY_ROWS; i++) begin
            for (int j = 0; j < ARRAY_COLUMNS; j++) begin
                C_actual[i][j] = mul_outcome[(i*ARRAY_COLUMNS+j)*DATA_WIDTH +: DATA_WIDTH];
                if (C_actual[i][j] !== C_expected[i][j]) begin
                    $display("Mismatch at [%0d][%0d]: Got %0d, Expected %0d",
                            i, j, C_actual[i][j], C_expected[i][j]);
                end
            end
        end

        // Print matrices
        $display("Matrix A:");
        for (int i = 0; i < ARRAY_ROWS; i++) begin
            for (int k = 0; k < K; k++) begin
                $write("%d ", A[i][k]);
            end
            $write("\n");
        end

        $display("Matrix B:");
        for (int k = 0; k < K; k++) begin
            for (int j = 0; j < ARRAY_COLUMNS; j++) begin
                $write("%d ", B[k][j]);
            end
            $write("\n");
        end

        $display("Expected Result:");
        for (int i = 0; i < ARRAY_ROWS; i++) begin
            for (int j = 0; j < ARRAY_COLUMNS; j++) begin
                $write("%d ", C_expected[i][j]);
            end
            $write("\n");
        end

        $display("Actual Result:");
        for (int i = 0; i < ARRAY_ROWS; i++) begin
            for (int j = 0; j < ARRAY_COLUMNS; j++) begin
                $write("%d ", C_actual[i][j]);
            end
            $write("\n");
        end

        // Debug: Print MAC values
        $display("MAC Values (debug_mac):");
        for (int i = 0; i < ARRAY_ROWS; i++) begin
            for (int j = 0; j < ARRAY_COLUMNS; j++) begin
                $write("%d ", debug_mac[(i*ARRAY_COLUMNS+j)*DATA_WIDTH +: DATA_WIDTH]);
            end
            $write("\n");
        end

        // Print out_array for debug
        $display("out_array:");
        for (int j = 0; j < ARRAY_COLUMNS; j++) begin
            $write("%d ", out_array[j*DATA_WIDTH +: DATA_WIDTH]);
        end
        $write("\n");

        $finish;
    end



endmodule
