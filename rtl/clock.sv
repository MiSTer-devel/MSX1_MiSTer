module clock #(parameter sysCLK = MSX::CLK_CORE_HZ)
(
   clock_bus_if.generator_mp clock_bus
);

// Free-running dividers: no reset needed, any state converges within one period.
// Power-up values keep the phase deterministic (simulation, first frame).
logic [1:0] clkdiv4 = 2'd1;
logic [2:0] clkdiv6 = 3'd5;
int div   = sysCLK / 10;
int msdiv = sysCLK / 1000;
logic ce_3m58_n_half = 1'b0;

always_ff @(posedge clock_bus.clk) begin
   clkdiv4 <= clkdiv4 + 1'd1;
end

always_ff @(posedge clock_bus.clk) begin
   if (clkdiv6 == 3'd0)
      clkdiv6 <= 3'd5;
   else
      clkdiv6 <= clkdiv6 - 1'b1;
end

always_ff @(posedge clock_bus.clk) begin
   if (div == 0)
      div <= sysCLK / 10;
   else
      div <= div - 1;
end

always_ff @(posedge clock_bus.clk) begin
   if (msdiv == 0)
      msdiv <= sysCLK / 1000;
   else
      msdiv <= msdiv - 1;
end

always_ff @(posedge clock_bus.clk) begin
   if (clkdiv6 == 3'd2)
      ce_3m58_n_half <= ~ce_3m58_n_half;
end

assign clock_bus.ce_10m7_p = clkdiv4[0];
assign clock_bus.ce_10m7_n = ~clkdiv4[0];
assign clock_bus.ce_5m39_p = &clkdiv4;
assign clock_bus.ce_5m39_n = ~clkdiv4[1] & clkdiv4[0];
assign clock_bus.ce_3m58_p = clkdiv6 == 3'd5;
assign clock_bus.ce_3m58_n = clkdiv6 == 3'd2;
assign clock_bus.ce_1m79_n = clkdiv6 == 3'd2 & ce_3m58_n_half;
assign clock_bus.ce_1k     = msdiv == 0;                //1ms
assign clock_bus.ce_10hz   = div == 0;                  //100ms

endmodule
