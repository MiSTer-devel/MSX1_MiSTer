// SD card window of the MegaFlashROM SCC+ SD (mapper_mfrsd3, 4000h-4FFFh with bank 0 =
// 01xxxxxx) with the real spi_divmmc (16 clk per byte) and an SD model sending 00, 01, 02, ...:
// - exactly one SPI transfer per CPU access, also when the access is long;
// - back-to-back accesses (closer than one transfer, R800 / turbo) wait (sd_wait) and lose
//   no byte (fork analysis C10);
// - a read returns the byte of the previous transfer, so the read values are consecutive.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_mfrsd_sd.sh   (OLD=<git rev>: mfrsd.sv without sd_wait)
module mfrsd_sd_tb;

logic clk = 0, reset = 1;
always #5 clk = ~clk;

cpu_bus_if          cpu_bus(clk, reset);
MSX::block_info_t   block_info;
MSX::mapper_out_t   out;
MSX::mfrsd_config_t config_reg;
ext_sd_card_if      sd();
flash_bus_if        flash();
assign flash.data_from_flash = 8'hFF;
assign flash.data_valid      = 1'b0;

`ifdef OLD
wire sd_wait = 1'b0;
mapper_mfrsd3 dut (.cpu_bus(cpu_bus), .ext_SD_card_bus(sd), .flash_bus(flash), .out(out),
                   .config_reg(config_reg), .block_info(block_info));
`else
wire sd_wait;
mapper_mfrsd3 dut (.cpu_bus(cpu_bus), .ext_SD_card_bus(sd), .flash_bus(flash), .out(out),
                   .config_reg(config_reg), .block_info(block_info), .sd_wait(sd_wait));
`endif

wire spi_clk, spi_do;
logic [7:0] sd_byte = 8'h00;        // byte the card sends in the current transfer
spi_divmmc spi (.clk_sys(clk), .ext_SD_card_bus(sd), .ready(), .spi_ce(1'b1),
                .spi_clk(spi_clk), .spi_di(sd_byte[3'd7 - spi.counter[3:1]]), .spi_do(spi_do));

// count transfers (counter restarts from idle) and advance the card byte after each
int transfers = 0;
logic busy_q = 0;
always @(posedge clk) begin
    busy_q <= ~spi.counter[4];
    if (~spi.counter[4] && !busy_q) transfers++;
    if (spi.counter[4] && busy_q) sd_byte <= sd_byte + 8'd1;
end

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        mreq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = 1'b0;  assign cpu_bus.mreq = mreq;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

int errors = 0;

// Memory access of len clk, extended while sd_wait (the CPU WAIT input); the value is read at
// the end, at least 2 clk after the last wait (T3 at 10.7 MHz)
task automatic access(input logic [15:0] a, input logic write, input int len, output logic [7:0] q,
                      input logic [7:0] d = 8'hA5);
    int n = 0, w = 0;
    @(negedge clk); addr = a; dbo = d; mreq = 1; rd = !write; wr = write; req = 1;
    @(negedge clk); req = 0;
    while (n < len || sd_wait) begin
        if (sd_wait) w = 2;
        else if (w > 0) w--;
        @(negedge clk); n++;
    end
    repeat (w) @(negedge clk);
    q = out.data;
    mreq = 0; rd = 0; wr = 0;
endtask

initial begin
    logic [7:0] q, prev;
    int t0;
    config_reg = '{isConfigRegDisabled: 1'b0, isMemoryMapperEnabled: 1'b1, isDSKmodeEnabled: 1'b0,
                   isPSGalsoMappedToNormalPorts: 1'b0, isSlotExpanderEnabled: 1'b1,
                   isFlashRomBlockProtectEnabled: 1'b1, isFlashRomWriteEnabled: 1'b0};
    block_info = '0;
    block_info.typ = MAPPER_MFRSD3;
    repeat (3) @(negedge clk); reset = 0;
    access(16'h6000, 1, 3, q, 8'h40);             // bank 0 = 40h: SD window at 4000h
    access(16'h5800, 1, 3, q, 8'h00);             // card 0
    repeat (20) @(negedge clk);

    // Long accesses (40 clk): one transfer each
    t0 = transfers;
    for (int i = 0; i < 4; i++) begin access(16'h4000, 0, 40, q); repeat (5) @(negedge clk); end
    repeat (20) @(negedge clk);
    if (transfers - t0 != 4) begin errors++; $display("FAIL long accesses: %0d transfers for 4 reads", transfers - t0); end

    // Back-to-back reads (6 clk access, 2 clk apart): consecutive bytes, one transfer each
    access(16'h4000, 0, 6, prev);
    t0 = transfers;
    for (int i = 0; i < 8; i++) begin
        repeat (2) @(negedge clk);
        access(16'h4000, 0, 6, q);
        if (q !== prev + 8'd1) begin errors++; $display("FAIL fast read %0d: %02h after %02h", i, q, prev); end
        prev = q;
    end
    repeat (40) @(negedge clk);
    if (transfers - t0 != 8) begin errors++; $display("FAIL fast reads: %0d transfers for 8 reads", transfers - t0); end

    // Back-to-back writes: every byte goes out
    t0 = transfers;
    for (int i = 0; i < 6; i++) begin repeat (2) @(negedge clk); access(16'h4000, 1, 6, q, 8'(8'h30 + i)); end
    repeat (40) @(negedge clk);
    if (transfers - t0 != 6) begin errors++; $display("FAIL fast writes: %0d transfers for 6 writes", transfers - t0); end

    if (errors == 0) $display("PASS mfrsd_sd_tb");
    else             $display("FAILED mfrsd_sd_tb: %0d errors", errors);
    $finish;
end

initial begin
    #2ms;
    $display("FAILED mfrsd_sd_tb: timeout");
    $finish;
end

endmodule
