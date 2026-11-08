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

# Core I/O that cannot be timed against an internal clock (asynchronous or timed by the
# protocol / board): UART RX on USER_IO (4-stage synchronizer in uart_rx), SD card SPI
# (spi_divmmc), tape ADC (ltc2308, < 500 kHz).
set_false_path -from [get_ports {USER_IO[*]}]
set_false_path -from [get_ports {SD_SPI_MISO}]
set_false_path -to   [get_ports {SD_SPI_CLK SD_SPI_MOSI SD_SPI_CS}]
set_false_path -from [get_ports {ADC_SDO}]
set_false_path -to   [get_ports {ADC_SCK ADC_SDI ADC_CONVST}]

# SDRAM pins are intentionally not constrained (MiSTer convention): all of them use I/O
# cell registers (sys.tcl FAST_*_REGISTER, verify in fit.rpt Output/Bidir Pins) and
# SDRAM_CLK is the inverted clk_sdram from altddio_out, so the pin timing is fixed by
# the I/O structure, not by placement.
