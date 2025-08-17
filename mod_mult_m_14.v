// mod_mult_14: Modular multiplier using shift-add for 14-bit operands
// Modulus = 2^13 + 2^12 + 1
// Modulus_inv = 2^14 + 2^12 + 2^10 + 2^8 + 2^6 + 2^4 + 2^1 + 1

module mod_mult_m_14 (
  input  wire        clk,
  input  wire        rst,
  input  wire [13:0] modulus,
  input  wire [14:0] modulus_inv,
  input  wire [13:0] input_data0,
  input  wire [13:0] input_data1,
  output reg  [13:0] output_data
);

  // Pipeline registers
  reg [27:0] product;               // Stage 1
  reg [13:0] q_est;                // Stage 2
  reg [29:0] r_partial0, r_partial1, r_partial2, r_partial3, r_partial4, r_partial5, r_est; // Stages 3–9
  reg [24:0] y_partial0, y_partial1, y_term; // Stages 10–12
  reg [14:0] diff;                // Stage 13
  reg [13:0] result;              // Stage 14

  // Stage 1: Full multiply
  always @(posedge clk or negedge rst) begin
    if (!rst)
      product <= 0;
    else
      product <= input_data0 * input_data1;
  end

  // Stage 2: Estimate q = product >> 22 (high bits)
  always @(posedge clk or negedge rst) begin
    if (!rst)
      q_est <= 0;
    else
      q_est <= product[27:14];
  end

  // Stages 3–9: q_est * modulus_inv = sum of shifted q_est terms
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      r_partial0 <= 0;
      r_partial1 <= 0;
      r_partial2 <= 0;
      r_partial3 <= 0;
      r_partial4 <= 0;
      r_partial5 <= 0;
      r_est      <= 0;
    end else begin
      r_partial0 <= (q_est << 14);               // 2^14 * q
      r_partial1 <= r_partial0 + (q_est << 12);  // + 2^12 * q
      r_partial2 <= r_partial1 + (q_est << 10);  // + 2^10 * q
      r_partial3 <= r_partial2 + (q_est << 8);   // + 2^8  * q
      r_partial4 <= r_partial3 + (q_est << 6);   // + 2^6  * q
      r_partial5 <= r_partial4 + (q_est << 4);   // + 2^4  * q
      r_est      <= r_partial5 + (q_est << 1) + q_est; // + 2^1 * q + q
    end
  end

  // Stages 10–12: Multiply r_est * modulus = (r << 13) + (r << 12) + r
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      y_partial0 <= 0;
      y_partial1 <= 0;
      y_term     <= 0;
    end else begin
      y_partial0 <= (r_est[13:0] << 13);
      y_partial1 <= y_partial0 + (r_est[13:0] << 12);
      y_term     <= y_partial1 + r_est[13:0];
    end
  end

  // Stage 13: Subtract
  always @(posedge clk or negedge rst) begin
    if (!rst)
      diff <= 0;
    else
      diff <= product[13:0] - y_term[14:0];
  end

  // Stage 14: Final modular correction
  always @(posedge clk or negedge rst) begin
    if (!rst)
      output_data <= 0;
    else if (diff >= (modulus << 1))
      output_data <= diff - (modulus << 1);
    else if (diff >= modulus)
      output_data <= diff - modulus;
    else
      output_data <= diff;
  end

endmodule
