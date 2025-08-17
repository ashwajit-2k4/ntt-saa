// mod_mult_m_12 rewritten in the same style as mod_mult_14
// Modulus = 2^12 + 2^10 - 2^6 - 2^4 - 1 = 6145
// Modulus_inv = 2^12 + 2^10 - 2^6 - 2^4 - 1 = 5039

module mod_mult_m_12 (
  input  wire        clk,
  input  wire        rst,
  input  wire [11:0] modulus,       // Expected: 6145
  input  wire [12:0] modulus_inv,   // Expected: 5039
  input  wire [11:0] input_data0,
  input  wire [11:0] input_data1,
  output reg  [11:0] output_data
);

  // Pipeline registers
  reg [23:0] product;                // Stage 1
  reg [12:0] q_est;                 // Stage 2

  reg [25:0] r_partial0, r_partial1, r_partial2, r_partial3, r_est; // Stages 3-7
  reg [24:0] y_partial0, y_partial1, y_partial2, y_term;            // Stages 8-11

  reg [12:0] diff_stage12;          // Stage 12
  reg [12:0] temp_result_stage13;   // Stage 13

  // Stage 1: Multiply inputs
  always @(posedge clk or negedge rst) begin
    if (!rst)
      product <= 0;
    else
      product <= input_data0 * input_data1;
  end

  // Stage 2: Estimate quotient (high bits)
  always @(posedge clk or negedge rst) begin
    if (!rst)
      q_est <= 0;
    else
      q_est <= product[23:11];
  end

  // Stages 3-7: Compute r_est = (q << 12) + (q << 10) - (q << 6) - (q << 4) - q
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      r_partial0 <= 0;
      r_partial1 <= 0;
      r_partial2 <= 0;
      r_partial3 <= 0;
      r_est      <= 0;
    end else begin
      r_partial0 <= (q_est << 12);
      r_partial1 <= r_partial0 + (q_est << 10);
      r_partial2 <= r_partial1 - (q_est << 6);
      r_partial3 <= r_partial2 - (q_est << 4);
      r_est      <= r_partial3 - q_est;
    end
  end

  // Stages 8-11: Compute y_term = (r << 11) + (r << 10) + (r << 8) + r
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      y_partial0 <= 0;
      y_partial1 <= 0;
      y_partial2 <= 0;
      y_term     <= 0;
    end else begin
      y_partial0 <= (r_est[11:0] << 11);
      y_partial1 <= y_partial0 + (r_est[11:0] << 10);
      y_partial2 <= y_partial1 + (r_est[11:0] << 8);
      y_term     <= y_partial2 + r_est[11:0];
    end
  end

  // Stage 12: Compute diff
  always @(posedge clk or negedge rst) begin
    if (!rst)
      diff_stage12 <= 0;
    else
      diff_stage12 <= product[11:0] - y_term[12:0];
  end

  // Stage 13: Final correction
  always @(posedge clk or negedge rst) begin
    if (!rst)
      temp_result_stage13 <= 0;
    else if (diff_stage12 >= (modulus << 1))
      temp_result_stage13 <= diff_stage12 - (modulus << 1);
    else if (diff_stage12 >= modulus)
      temp_result_stage13 <= diff_stage12 - modulus;
    else
      temp_result_stage13 <= diff_stage12;
  end

  // Stage 14: Output
  always @(posedge clk or negedge rst) begin
    if (!rst)
      output_data <= 0;
    else
      output_data <= temp_result_stage13[11:0];
  end

endmodule
