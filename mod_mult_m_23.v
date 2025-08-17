// mod_mult_23: Modular multiplier using shift-add for 23-bit operands
// Modulus = 2^23 - 2^13 + 1
// Modulus_inv = 2^23 + 2^13 + 2^3 - 1

module mod_mult_m_23 (
  input  wire        clk,
  input  wire        rst,
  input  wire [22:0] modulus,       // 2^23 - 2^13 + 1
  input  wire [23:0] modulus_inv,   // 2^23 + 2^13 + 2^3 - 1
  input  wire [22:0] input_data0,
  input  wire [22:0] input_data1,
  output reg  [22:0] output_data
);

  // Intermediate signals
  reg [45:0] x_stage_00, x_stage_01, x_stage_10;
  reg [22:0] q_est;
  reg [47:0] r_partial0, r_partial1, r_partial2, r_est;
  reg [46:0] y_partial0, y_partial1, y_partial2, y_term;
  reg [22:0] diff;

  // Stage 1: Partial product generation
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      x_stage_00 <= 0;
      x_stage_01 <= 0;
    end else begin
      x_stage_00 <= input_data0 * input_data1[16:0];
      x_stage_01 <= input_data0 * input_data1[22:17];
    end
  end

  // Stage 2: Combine partial products
  always @(posedge clk or negedge rst) begin
    if (!rst)
      x_stage_10 <= 0;
    else
      x_stage_10 <= x_stage_00 + (x_stage_01 << 17);
  end

  // Stage 3: Estimate quotient
  always @(posedge clk or negedge rst) begin
    if (!rst)
      q_est <= 0;
    else
      q_est <= x_stage_10[45:23];
  end

  // Stage 4–7: r_est = q_est * modulus_inv = (q<<23) + (q<<13) + (q<<3) - q
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      r_partial0 <= 0;
      r_partial1 <= 0;
      r_partial2 <= 0;
      r_est <= 0;
    end else begin
      r_partial0 <= (q_est << 23);
      r_partial1 <= r_partial0 + (q_est << 13);
      r_partial2 <= r_partial1 + (q_est << 3);
      r_est <= r_partial2 - q_est;
    end
  end

  // Stage 8–11: y_term = r_est * modulus = (r<<23) - (r<<13) + r
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      y_partial0 <= 0;
      y_partial1 <= 0;
      y_partial2 <= 0;
      y_term <= 0;
    end else begin
      y_partial0 <= (r_est[22:0] << 23);
      y_partial1 <= y_partial0 - (r_est[22:0] << 13);
      y_partial2 <= y_partial1 + r_est[22:0];
      y_term <= y_partial2;
    end
  end

  // Stage 12–14: Final correction
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      diff <= 0;
      output_data <= 0;
    end else begin
      diff <= x_stage_10[22:0] - y_term[22:0];
      if (diff >= (modulus << 1))
        output_data <= diff - (modulus << 1);
      else if (diff >= modulus)
        output_data <= diff - modulus;
      else
        output_data <= diff;
    end
  end

endmodule
