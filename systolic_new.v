module systolic_new#(
    parameter ARRAY_ROWS = 4,
    parameter ARRAY_COLUMNS = 8,
    parameter DATA_WIDTH = 14,
    parameter INPUT_LENGTH = 4,
    parameter MUL_DELAY = 12,
    parameter N1 = 16,  // total rows, adjust as needed
    parameter N2 = 32   // total cols, adjust as needed
)(
    input clk,
    input srstn,
    input alu_start_0,
    input alu_start_1,
    input alu_start_2,
    input [11:0] K0,
    input [11:0] K1,
    input [11:0] K2,
    input w_scale,
    input [ARRAY_ROWS*DATA_WIDTH-1:0] A_vec,
    input [ARRAY_COLUMNS*DATA_WIDTH-1:0] B_vec,
    input [31:0] A_write_addr,
    input [31:0] A_read_addr,
    input [31:0] B_write_addr,
    input [31:0] addr_out,
    input [31:0] addr_ram_out,
    input [31:0] addr_ram_outy,
    input [31:0] B_read_addr,
    input A_write_enable,
    input use_alt_rom,
    input A_vec_write_enable,
    input [31:0] A_vec_write_addr,
    input A_pingpong_sel,
    input pingpong_out_sel,
    input write_to_out_ram,
    input [31:0] out_write_addr,
    output reg [DATA_WIDTH*ARRAY_COLUMNS-1:0] out_array,
    output mode0_active
);

localparam TILE_ROWS = N1 / ARRAY_ROWS;
localparam TILE_COLS_B_SHIFT = N1 / ARRAY_COLUMNS;
localparam TILE_COLS_OUT = N2 / ARRAY_COLUMNS;
localparam IDLE = 0, RUN = 1;

reg [DATA_WIDTH-1:0] A_shift [0:ARRAY_ROWS-1][0:ARRAY_ROWS-1];
(* keep = "true" *) reg [DATA_WIDTH-1:0] B_shift [0:ARRAY_COLUMNS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] a_pipe [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] b_pipe [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] a_in [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] b_in [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] add_term [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
wire [DATA_WIDTH-1:0] pe_result [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] mac [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] w_curr [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] w_col [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] w_og [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] w_row [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] w_col_scale [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
reg [DATA_WIDTH-1:0] out_buffer [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];

// ROMs for B
(* keep = "true" *) (* ram_decomp = "area" *) (* rom_style = "distributed" *) reg [DATA_WIDTH-1:0] B_shift_rom [0:N2*N2-1];
(* keep = "true" *) (* ram_decomp = "area" *) (* rom_style = "distributed" *) reg [DATA_WIDTH-1:0] B_shift_rom_alt [0:N1*N1-1];

// Ping-pong buffers for A
(* keep = "true" *) (* ram_decomp = "area" *) (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] A_pingpong_0 [0:ARRAY_ROWS-1][0:N1-1];
(* keep = "true" *) (* ram_decomp = "area" *) (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] A_pingpong_1 [0:ARRAY_ROWS-1][0:N1-1];

// Ping-pong output buffers and RAM output buffer
(* keep = "true" *) (* ram_decomp = "area" *) (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] out_pingpong_0 [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
(* keep = "true" *) (* ram_decomp = "area" *) (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] out_pingpong_1 [0:ARRAY_ROWS-1][0:ARRAY_COLUMNS-1];
(* keep = "true" *) (* ram_decomp = "area" *) (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] out_ram [0:ARRAY_COLUMNS-1][0:N2-1];

integer ii, jj, l;

// Initialize ROMs and RAMs randomly (or zero)
initial begin
    // Random 12-bit values for the ROM
    B_shift_rom[0] = 12'h3A2;    B_shift_rom[1] = 12'h8F1;    B_shift_rom[2] = 12'h7D4;    B_shift_rom[3] = 12'h2B9;
    B_shift_rom[4] = 12'h6C8;    B_shift_rom[5] = 12'h1E5;    B_shift_rom[6] = 12'h9A3;    B_shift_rom[7] = 12'h4F7;
    B_shift_rom[8] = 12'hB2D;    B_shift_rom[9] = 12'h5E8;    B_shift_rom[10] = 12'hC71;   B_shift_rom[11] = 12'h3F4;
    B_shift_rom[12] = 12'h8B6;   B_shift_rom[13] = 12'h729;   B_shift_rom[14] = 12'hD1C;   B_shift_rom[15] = 12'h465;
    B_shift_rom[16] = 12'hA93;   B_shift_rom[17] = 12'h2E7;   B_shift_rom[18] = 12'hF5A;   B_shift_rom[19] = 12'h6D2;
    B_shift_rom[20] = 12'h4B8;   B_shift_rom[21] = 12'h81F;   B_shift_rom[22] = 12'h3C6;   B_shift_rom[23] = 12'h9E4;
    B_shift_rom[24] = 12'h572;   B_shift_rom[25] = 12'hCB9;   B_shift_rom[26] = 12'h7F3;   B_shift_rom[27] = 12'h24E;
    B_shift_rom[28] = 12'hE61;   B_shift_rom[29] = 12'h8A5;   B_shift_rom[30] = 12'h1D7;   B_shift_rom[31] = 12'h639;
    B_shift_rom[32] = 12'hF82;   B_shift_rom[33] = 12'h4A6;   B_shift_rom[34] = 12'h7E1;   B_shift_rom[35] = 12'h293;
    B_shift_rom[36] = 12'hB5C;   B_shift_rom[37] = 12'h6F8;   B_shift_rom[38] = 12'h134;   B_shift_rom[39] = 12'hDE7;
    B_shift_rom[40] = 12'h8C2;   B_shift_rom[41] = 12'h375;   B_shift_rom[42] = 12'hA9E;   B_shift_rom[43] = 12'h541;
    B_shift_rom[44] = 12'h7B6;   B_shift_rom[45] = 12'h2F3;   B_shift_rom[46] = 12'hE8A;   B_shift_rom[47] = 12'h6D4;
    B_shift_rom[48] = 12'h195;   B_shift_rom[49] = 12'hC47;   B_shift_rom[50] = 12'h8E2;   B_shift_rom[51] = 12'h3B9;
    B_shift_rom[52] = 12'hF76;   B_shift_rom[53] = 12'h528;   B_shift_rom[54] = 12'hAD1;   B_shift_rom[55] = 12'h643;
    B_shift_rom[56] = 12'h2F8;   B_shift_rom[57] = 12'hE5C;   B_shift_rom[58] = 12'h793;   B_shift_rom[59] = 12'h1A6;
    B_shift_rom[60] = 12'hB84;   B_shift_rom[61] = 12'h4E7;   B_shift_rom[62] = 12'hC23;   B_shift_rom[63] = 12'h951;
    B_shift_rom[64] = 12'h3D8;   B_shift_rom[65] = 12'h7F2;   B_shift_rom[66] = 12'h265;   B_shift_rom[67] = 12'hE94;
    B_shift_rom[68] = 12'h5A7;   B_shift_rom[69] = 12'h8C3;   B_shift_rom[70] = 12'h1F6;   B_shift_rom[71] = 12'hB58;
    B_shift_rom[72] = 12'h72A;   B_shift_rom[73] = 12'h4E1;   B_shift_rom[74] = 12'hD39;   B_shift_rom[75] = 12'h685;
    B_shift_rom[76] = 12'hA2C;   B_shift_rom[77] = 12'h3F7;   B_shift_rom[78] = 12'h9B4;   B_shift_rom[79] = 12'h571;
    B_shift_rom[80] = 12'hE86;   B_shift_rom[81] = 12'h2D3;   B_shift_rom[82] = 12'hC9F;   B_shift_rom[83] = 12'h748;
    B_shift_rom[84] = 12'h1A2;   B_shift_rom[85] = 12'hF65;   B_shift_rom[86] = 12'h4E9;   B_shift_rom[87] = 12'h832;
    B_shift_rom[88] = 12'h6B7;   B_shift_rom[89] = 12'h294;   B_shift_rom[90] = 12'hD58;   B_shift_rom[91] = 12'h7F1;
    B_shift_rom[92] = 12'h3C6;   B_shift_rom[93] = 12'hAE3;   B_shift_rom[94] = 12'h529;   B_shift_rom[95] = 12'h8F4;
    B_shift_rom[96] = 12'h175;   B_shift_rom[97] = 12'hB6A;   B_shift_rom[98] = 12'h4D2;   B_shift_rom[99] = 12'hC91;
    B_shift_rom[100] = 12'h783;  B_shift_rom[101] = 12'h2E6;  B_shift_rom[102] = 12'hF54;  B_shift_rom[103] = 12'h6A8;
    B_shift_rom[104] = 12'h397;  B_shift_rom[105] = 12'hE12;  B_shift_rom[106] = 12'h5C4;  B_shift_rom[107] = 12'h8F9;
    B_shift_rom[108] = 12'h261;  B_shift_rom[109] = 12'hD7B;  B_shift_rom[110] = 12'h453;  B_shift_rom[111] = 12'h9C8;
    B_shift_rom[112] = 12'h7E2;  B_shift_rom[113] = 12'h315;  B_shift_rom[114] = 12'hB6A;  B_shift_rom[115] = 12'h584;
    B_shift_rom[116] = 12'hF93;  B_shift_rom[117] = 12'h427;  B_shift_rom[118] = 12'hCE1;  B_shift_rom[119] = 12'h765;
    B_shift_rom[120] = 12'h1D8;  B_shift_rom[121] = 12'hA49;  B_shift_rom[122] = 12'h372;  B_shift_rom[123] = 12'hE8F;
    B_shift_rom[124] = 12'h5B6;  B_shift_rom[125] = 12'h294;  B_shift_rom[126] = 12'hD7C;  B_shift_rom[127] = 12'h6A1;
    B_shift_rom[128] = 12'h8E5;  B_shift_rom[129] = 12'h432;  B_shift_rom[130] = 12'hF97;  B_shift_rom[131] = 12'h264;
    B_shift_rom[132] = 12'hB58;  B_shift_rom[133] = 12'h7C1;  B_shift_rom[134] = 12'h3A9;  B_shift_rom[135] = 12'hE76;
    B_shift_rom[136] = 12'h592;  B_shift_rom[137] = 12'h1D4;  B_shift_rom[138] = 12'hC8B;  B_shift_rom[139] = 12'h647;
    B_shift_rom[140] = 12'h3F8;  B_shift_rom[141] = 12'h925;  B_shift_rom[142] = 12'h7E2;  B_shift_rom[143] = 12'h4A6;
    B_shift_rom[144] = 12'hD19;  B_shift_rom[145] = 12'h683;  B_shift_rom[146] = 12'h2F7;  B_shift_rom[147] = 12'hB54;
    B_shift_rom[148] = 12'h8C1;  B_shift_rom[149] = 12'h3E9;  B_shift_rom[150] = 12'hA72;  B_shift_rom[151] = 12'h546;
    B_shift_rom[152] = 12'h1D3;  B_shift_rom[153] = 12'hF87;  B_shift_rom[154] = 12'h625;  B_shift_rom[155] = 12'h4B8;
    B_shift_rom[156] = 12'hC94;  B_shift_rom[157] = 12'h761;  B_shift_rom[158] = 12'h2E5;  B_shift_rom[159] = 12'h9A3;
    B_shift_rom[160] = 12'h5F7;  B_shift_rom[161] = 12'h148;  B_shift_rom[162] = 12'hE62;  B_shift_rom[163] = 12'h839;
    B_shift_rom[164] = 12'h4C5;  B_shift_rom[165] = 12'hB71;  B_shift_rom[166] = 12'h29F;  B_shift_rom[167] = 12'h6D4;
    B_shift_rom[168] = 12'hF86;  B_shift_rom[169] = 12'h3A2;  B_shift_rom[170] = 12'h958;  B_shift_rom[171] = 12'h7E1;
    B_shift_rom[172] = 12'h243;  B_shift_rom[173] = 12'hC67;  B_shift_rom[174] = 12'h594;  B_shift_rom[175] = 12'h1F8;
    B_shift_rom[176] = 12'hA85;  B_shift_rom[177] = 12'h6D2;  B_shift_rom[178] = 12'h319;  B_shift_rom[179] = 12'hE4F;
    B_shift_rom[180] = 12'h7B6;  B_shift_rom[181] = 12'h528;  B_shift_rom[182] = 12'hD94;  B_shift_rom[183] = 12'h463;
    B_shift_rom[184] = 12'h1C7;  B_shift_rom[185] = 12'hF85;  B_shift_rom[186] = 12'h6A2;  B_shift_rom[187] = 12'h394;
    B_shift_rom[188] = 12'hB58;  B_shift_rom[189] = 12'h721;  B_shift_rom[190] = 12'h4E6;  B_shift_rom[191] = 12'hCDA;
    B_shift_rom[192] = 12'h867;  B_shift_rom[193] = 12'h293;  B_shift_rom[194] = 12'hF51;  B_shift_rom[195] = 12'h6C4;
    B_shift_rom[196] = 12'h1A8;  B_shift_rom[197] = 12'hE75;  B_shift_rom[198] = 12'h539;  B_shift_rom[199] = 12'h926;
    B_shift_rom[200] = 12'h7D2;  B_shift_rom[201] = 12'h4FB;  B_shift_rom[202] = 12'hB64;  B_shift_rom[203] = 12'h381;
    B_shift_rom[204] = 12'hC95;  B_shift_rom[205] = 12'h657;  B_shift_rom[206] = 12'h2E3;  B_shift_rom[207] = 12'hA79;
    B_shift_rom[208] = 12'h514;  B_shift_rom[209] = 12'h8C6;  B_shift_rom[210] = 12'h1F2;  B_shift_rom[211] = 12'hD4B;
    B_shift_rom[212] = 12'h738;  B_shift_rom[213] = 12'h965;  B_shift_rom[214] = 12'h2A1;  B_shift_rom[215] = 12'hE87;
    B_shift_rom[216] = 12'h643;  B_shift_rom[217] = 12'h1F9;  B_shift_rom[218] = 12'hBC5;  B_shift_rom[219] = 12'h472;
    B_shift_rom[220] = 12'h8D6;  B_shift_rom[221] = 12'h3A4;  B_shift_rom[222] = 12'hF71;  B_shift_rom[223] = 12'h528;
    B_shift_rom[224] = 12'h1E6;  B_shift_rom[225] = 12'hC93;  B_shift_rom[226] = 12'h657;  B_shift_rom[227] = 12'h2A4;
    B_shift_rom[228] = 12'h981;  B_shift_rom[229] = 12'h7F5;  B_shift_rom[230] = 12'h342;  B_shift_rom[231] = 12'hBE8;
    B_shift_rom[232] = 12'h596;  B_shift_rom[233] = 12'h1D3;  B_shift_rom[234] = 12'hC47;  B_shift_rom[235] = 12'h8F2;
    B_shift_rom[236] = 12'h264;  B_shift_rom[237] = 12'hE91;  B_shift_rom[238] = 12'h3A5;  B_shift_rom[239] = 12'h678;
    B_shift_rom[240] = 12'hF4C;  B_shift_rom[241] = 12'h5B7;  B_shift_rom[242] = 12'h123;  B_shift_rom[243] = 12'hD89;
    B_shift_rom[244] = 12'h4E6;  B_shift_rom[245] = 12'hA32;  B_shift_rom[246] = 12'h795;  B_shift_rom[247] = 12'h1F4;
    B_shift_rom[248] = 12'hC68;  B_shift_rom[249] = 12'h6B1;  B_shift_rom[250] = 12'h357;  B_shift_rom[251] = 12'hE23;
    B_shift_rom[252] = 12'h896;  B_shift_rom[253] = 12'h4D2;  B_shift_rom[254] = 12'hB7F;  B_shift_rom[255] = 12'h541;

    for (ii = 256; ii < 1024; ii = ii + 1) begin
        B_shift_rom_alt[ii] = $random % 4096; // 12-bit value range: 0 to 4095
    end

    for (ii = 0; ii < ARRAY_ROWS; ii = ii + 1) begin
        for (jj = 0; jj < N1; jj = jj + 1) begin
            A_pingpong_0[ii][jj] = 0;
            A_pingpong_1[ii][jj] = 0;
        end
        for (jj = 0; jj < ARRAY_COLUMNS; jj = jj + 1) begin
            out_pingpong_0[ii][jj] = 0;
            out_pingpong_1[ii][jj] = 0;
        end
    end
    for (ii = 0; ii < ARRAY_COLUMNS; ii = ii + 1) begin
        for (jj = 0; jj < N2; jj = jj + 1) begin
            out_ram[ii][jj] = 0;
        end
    end
end

// Write to A ping-pong buffer from A_vec when enabled
always @(posedge clk) begin
    if (A_vec_write_enable) begin
        for (ii = 0; ii < ARRAY_ROWS; ii = ii + 1) begin
            if ((A_vec_write_addr + ii) < N1) begin
                if (A_pingpong_sel)
                    A_pingpong_1[ii][A_vec_write_addr] <= A_vec[ii*DATA_WIDTH +: DATA_WIDTH];
                else
                    A_pingpong_0[ii][A_vec_write_addr] <= A_vec[ii*DATA_WIDTH +: DATA_WIDTH];
            end
        end
    end
end

// Read from A ping-pong buffer to A_shift[ii][ii]
always @(*) begin
    for (ii = 0; ii < ARRAY_ROWS; ii = ii + 1) begin
        if ((A_read_addr + ii) < N1) begin
            if (A_pingpong_sel)
                A_shift[ii][ii] <= A_pingpong_0[ii][A_read_addr];
            else
                A_shift[ii][ii] <= A_pingpong_1[ii][A_read_addr];
        end else begin
            A_shift[ii][ii] <= out_ram[addr_ram_out][addr_ram_outy];
        end
    end
end

// B read from ROMs depending on use_alt_rom
always @(*) begin
    for (ii = 0; ii < ARRAY_COLUMNS; ii = ii + 1) begin
        if ((B_read_addr + ii) < N1*N1) begin
            B_shift[ii][ii] = use_alt_rom ? B_shift_rom_alt[B_read_addr + ii] : B_shift_rom[B_read_addr + ii];
        end else begin
            B_shift[ii][ii] = 12'h000;
        end
    end
end

// Write to output buffers (ping-pong or RAM)
always @(posedge clk) begin
    for (ii = 0; ii < ARRAY_ROWS; ii = ii + 1) begin
        for (jj = 0; jj < ARRAY_COLUMNS; jj = jj + 1) begin
            if (write_to_out_ram && (out_write_addr < N2)) begin
                out_ram[jj][out_write_addr] <= out_buffer[ii][jj];
            end else if (pingpong_out_sel) begin
                out_pingpong_1[ii][jj] <= out_buffer[ii][jj];
            end else begin
                out_pingpong_0[ii][jj] <= out_buffer[ii][jj];
            end
        end
    end
end

// The rest of your original logic, untouched, including modular multipliers and mode control:

reg [4:0] mode_control [0:ARRAY_ROWS+ARRAY_COLUMNS-2];
reg [4:0] mode_in [0:ARRAY_ROWS-1][0:ARRAY_ROWS-1];
reg [4:0] mode_pipeline [0:MUL_DELAY-2][0:ARRAY_ROWS-1][0:ARRAY_ROWS-1];
reg [4:0] mode_out [0:ARRAY_ROWS-1][0:ARRAY_ROWS-1];
reg [7:0] cycle_count;
reg [11:0] modulus, modulus_inv, K;
reg tile_mode, tile_end;

genvar gr, gc;
generate
    for (gr = 0; gr < ARRAY_ROWS; gr = gr + 1) begin : gen_row
        for (gc = 0; gc < ARRAY_COLUMNS; gc = gc + 1) begin : gen_col
            mod_mult_m_14 u_mod_mult_m_14 (
                .clk(clk),
                .rst(srstn),
                .modulus(modulus),
                .modulus_inv(modulus_inv),
                .input_data0(a_in[gr][gc]),
                .input_data1(b_in[gr][gc]),
                .output_data(pe_result[gr][gc])
            );
        end
    end
endgenerate

always @(posedge clk) begin
    if (!srstn) begin
        for (ii = 0; ii < ARRAY_ROWS; ii = ii + 1) begin
            for (jj = 0; jj < ARRAY_COLUMNS; jj = jj + 1) begin
                // Preserve your original reset init
                a_pipe[ii][jj] <= 0;
                b_pipe[ii][jj] <= 0;
                a_in[ii][jj] <= 0;
                b_in[ii][jj] <= 0;
                add_term[ii][jj] <= 0;
                mac[ii][jj] <= 0;
                w_curr[ii][jj] <= 0;
                w_col[ii][jj] <= 0;
                w_og[ii][jj] <= 0;
                w_row[ii][jj] <= 0;
                out_buffer[ii][jj] <= 0;
            end
        end
        for (ii = 0; ii < ARRAY_ROWS + ARRAY_COLUMNS - 1; ii = ii + 1)
            mode_control[ii] <= 0;
        for (ii = 0; ii < ARRAY_ROWS; ii = ii + 1) begin
            for (jj = 0; jj < ARRAY_ROWS; jj = jj + 1) begin
                mode_in[ii][jj] <= 0;
                mode_out[ii][jj] <= 0;
                for (l = 0; l < MUL_DELAY-1; l = l + 1)
                    mode_pipeline[l][ii][jj] <= 0;
            end
        end
        modulus <= 0;
        modulus_inv <= 0;
        K <= 4;
        tile_mode <= 2;
        tile_end <= 0;
        cycle_count <= K + MUL_DELAY;
    end else begin

        // The original shifting logic for A_shift (except [ii][ii] is overridden above)
        for (ii = 0; ii < ARRAY_ROWS; ii = ii + 1) begin
            if (ii != 0) begin
                for (jj = ii-1; jj >= 0; jj = jj - 1)
                    A_shift[ii][jj] <= A_shift[ii][jj+1];
            end
        end

        // Shifting logic for B_shift
        for (ii = 0; ii < ARRAY_COLUMNS; ii = ii + 1) begin
            if (ii != 0) begin
                for (jj = ii-1; jj >= 0; jj = jj - 1) begin
                    B_shift[jj][ii] <= B_shift[jj+1][ii];
                end
            end
        end

        // Pipeline input setup
        for (ii = 0; ii < ARRAY_ROWS; ii = ii + 1)
            for (jj = 0; jj < ARRAY_COLUMNS; jj = jj + 1) begin
                a_pipe[ii][0] <= A_shift[ii][0];
                b_pipe[0][jj] <= B_shift[0][jj];
            end

        // Mode control pipeline and PE input/output management
        for (ii = 0; ii < ARRAY_ROWS; ii = ii + 1)
            for (jj = 0; jj < ARRAY_COLUMNS; jj = jj + 1) begin
                mode_in[ii][jj] <= mode_control[ii+jj];
                mode_pipeline[0][ii][jj] <= mode_in[ii][jj];
                for (l = 1; l < MUL_DELAY-1; l = l + 1)
                    mode_pipeline[l][ii][jj] <= mode_pipeline[l-1][ii][jj];
                mode_out[ii][jj] <= mode_pipeline[MUL_DELAY-2][ii][jj];

                if (mode_in[ii][jj] == 0) begin
                    a_in[ii][jj] <= a_pipe[ii][jj];
                    b_in[ii][jj] <= b_pipe[ii][jj];
                    if (ii != ARRAY_ROWS-1) b_pipe[ii+1][jj] <= b_pipe[ii][jj];
                    if (jj != ARRAY_COLUMNS-1) a_pipe[ii][jj+1] <= a_pipe[ii][jj];
                end else begin
                    a_pipe[ii][jj] <= a_pipe[ii][jj];
                    b_pipe[ii][jj] <= b_pipe[ii][jj];
                    case (mode_in[ii][jj])
                        1: begin a_in[ii][jj] <= w_curr[ii][jj]; b_in[ii][jj] <= b_pipe[ii][jj]; end
                        2: begin a_in[ii][jj] <= a_pipe[ii][jj]; b_in[ii][jj] <= w_col[ii][jj]; end
                        3: begin a_in[ii][jj] <= w_og[ii][jj]; b_in[ii][jj] <= b_pipe[ii][jj]; end
                        4: begin a_in[ii][jj] <= a_pipe[ii][jj]; b_in[ii][jj] <= w_row[ii][jj]; end
                        default: begin a_in[ii][jj] <= a_pipe[ii][jj]; b_in[ii][jj] <= b_pipe[ii][jj]; end
                    endcase
                end

                if (mode_out[ii][jj] == 0)
                    mac[ii][jj] <= mac[ii][jj] + pe_result[ii][jj];
                else if (mode_out[ii][jj] == 1)
                    mac[ii][jj] <= add_term[ii][jj];
                else
                    mac[ii][jj] <= 0;

                // Output buffer
                out_buffer[ii][jj] <= mac[ii][jj];
            end

        if (mode_control[0] == 0) begin
            cycle_count <= cycle_count - 1;
            if (cycle_count == 0) begin
                mode_control[0] <= 5;
                cycle_count <= K;
            end
        end else if (mode_control[0] == 5) begin
            if (tile_mode == 0) begin
                if (tile_end == 1) mode_control[0] <= 2;
                else mode_control[0] <= 1;
            end else mode_control[0] <= 4;
        end else if (mode_control[0] == 1)
            mode_control[0] <= 0;
        else if (mode_control[0] == 2)
            mode_control[0] <= 3;
        else if (mode_control[0] == 3)
            mode_control[0] <= 0;

        for (l = 0; l < ARRAY_ROWS + ARRAY_COLUMNS - 2; l = l + 1)
            mode_control[l + 1] <= mode_control[l];

    end    
end

// Output assembly
always @(posedge clk) begin
    // Assign mul_outcome from PE results
    
    // Assign out_array from output buffer or ping-pong buffer
    for (jj = 0; jj < ARRAY_COLUMNS; jj = jj + 1) begin
        if (pingpong_out_sel) begin
            out_array[jj*DATA_WIDTH +: DATA_WIDTH] <= out_pingpong_1[addr_out][jj]; // Use row 0 as example
        end else begin
            out_array[jj*DATA_WIDTH +: DATA_WIDTH] <= out_pingpong_0[addr_out][jj]; // Use row 0 as example
        end
    end
end

assign mode0_active = (mode_control[0] == 0);

endmodule
