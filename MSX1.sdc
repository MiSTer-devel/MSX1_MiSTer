derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

set clk_core  [get_clocks {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
set clk_sdram [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]

# SDRAM ch1 request (CPU address decode, clk_core combinational logic) is sampled by
# sdram.sv only on the 2nd clk_sdram edge after a clk_core edge (ch1_sample).
set sdram_ch1_capture [get_registers {emu:emu|sdram:sdram|ch1_*}]
set_multicycle_path -setup -end 2 -from $clk_core -to $sdram_ch1_capture
set_multicycle_path -hold  -end 1 -from $clk_core -to $sdram_ch1_capture
