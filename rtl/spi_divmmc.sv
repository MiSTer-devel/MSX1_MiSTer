// SPI module
module spi_divmmc
(
	input       		    clk_sys,
	ext_sd_card_if.SD_mp	ext_SD_card_bus,
	output       			ready,
	input        			spi_ce,
	output       			spi_clk,
	input        			spi_di,
	output       			spi_do
);

assign    ready                        = counter[4];
assign    spi_clk                      = counter[0];
assign    spi_do                       = io_byte[7]; // data is shifted up during transfer
assign    ext_SD_card_bus.data_from_SD = data;
assign    ext_SD_card_bus.busy         = ~counter[4];

reg [4:0] counter = 5'b10000;  // tx/rx counter is idle
reg [7:0] io_byte, data;

always @(posedge clk_sys) begin
	if(counter[4]) begin
		if(ext_SD_card_bus.rx | ext_SD_card_bus.tx) begin
			counter <= 0;
			data    <= io_byte;
			io_byte <= ext_SD_card_bus.tx ? ext_SD_card_bus.data_to_SD : 8'hff;
		end
	end
	else if (spi_ce) begin
		if(spi_clk) io_byte <= { io_byte[6:0], spi_di };
		counter <= counter + 1'd1;
	end
end

endmodule