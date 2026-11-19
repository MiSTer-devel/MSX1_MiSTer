module vdp18_clk_gen (
    input  logic clk_i,
    input  logic reset_i,
    input  logic clk_en_10m7_i,
    output logic clk_en_5m37_o,
    output logic clk_en_3m58_o,
    output logic clk_en_2m68_o
);


  logic [3:0] cnt_q;

  // Process seq
  // Purpose: Wraps the 10.7 MHz input clock.
  always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin
      cnt_q <= 4'b0000;
    end else if (clk_en_10m7_i) begin
      if (cnt_q == 4'd11) begin
        // wrap after counting 12 clocks
        cnt_q <= 4'b0000;
      end else begin
        cnt_q <= cnt_q + 1'd1;
      end
    end
  end

  // Process clk_en
  // Purpose: Generates the derived clock enable signals.
  always_comb begin
    // 5.37 MHz clock enable
    if (clk_en_10m7_i) begin
      case (cnt_q)
        1, 3, 5, 7, 9, 11: clk_en_5m37_o = 1;
        default:           clk_en_5m37_o = 0;
      endcase
    end else begin
      clk_en_5m37_o = 0;
    end

    // 3.58 MHz clock enable
    if (clk_en_10m7_i) begin
      case (cnt_q)
        2, 5, 8, 11: clk_en_3m58_o = 1;
        default:     clk_en_3m58_o = 0;
      endcase
    end else begin
      clk_en_3m58_o = 0;
    end

    // 2.68 MHz clock enable
    if (clk_en_10m7_i) begin
      case (cnt_q)
        3, 7, 11: clk_en_2m68_o = 1;
        default:  clk_en_2m68_o = 0;
      endcase
    end else begin
      clk_en_2m68_o = 0;
    end
  end

endmodule
