// MegaSD data window of the ESE-RAM mapper (4000h-57FFh, bank 0 = 01xxxxxx) with the real
// spi_divmmc (16 clk per byte) and an SD model sending 00, 01, 02, ...:
// - exactly one SPI transfer per CPU access, also when the access is long (wait states);
// - back-to-back accesses (closer than one transfer) wait (mmc_wait) and lose no byte;
// - a read returns the byte of the previous transfer (divmmc protocol), so the sequence of
//   read values is consecutive.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_ese_mmc.sh   (OLD=1: code without mmc_wait)
module ese_mmc_tb;

logic clk = 0, reset = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, reset);
MSX::block_info_t block_info;
MSX::mapper_out_t out;
ext_sd_card_if    sd();
wire              mmc_on;
`ifdef OLD
wire              mmc_wait = 1'b0;
mapper_eseRam dut (.cpu_bus(cpu_bus), .out(out), .block_info(block_info), .ext_SD_card_bus(sd),
                   .megaSD_enable(1'b1), .mmc_on(mmc_on));
`else
wire              mmc_wait;
mapper_eseRam dut (.cpu_bus(cpu_bus), .out(out), .block_info(block_info), .ext_SD_card_bus(sd),
                   .megaSD_enable(1'b1), .mmc_on(mmc_on), .mmc_wait(mmc_wait));
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

// Memory access of len clk; extended while mmc_wait (as the CPU WAIT input); value read at the end,
// at least 2 clk after the last wait (T3 at 10.7 MHz)
task automatic access(input logic [15:0] a, input logic write, input int len, output logic [7:0] q,
                      input logic [7:0] d = 8'hA5);
    int n = 0, w = 0;
    @(negedge clk); addr = a; dbo = d; mreq = 1; rd = !write; wr = write; req = 1;
    @(negedge clk); req = 0;
    while (n < len || mmc_wait) begin
        if (mmc_wait) w = 2;            // after WAIT the CPU passes T3: data sampled >= 2 clk later
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
    block_info = '0;
    block_info.typ = MAPPER_ESE_RAM;
    repeat (3) @(negedge clk); reset = 0;
    access(16'h6000, 1, 3, q, 8'h40);             // bank 0 = 40h: MegaSD window at 4000h
    if (!mmc_on) begin errors++; $display("FAIL window not mapped"); end
    repeat (20) @(negedge clk);

    // Long accesses (40 clk, e.g. turbo with many wait states): one transfer each
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

    if (errors == 0) $display("PASS ese_mmc_tb");
    else             $display("FAILED ese_mmc_tb: %0d errors", errors);
    $finish;
end

endmodule
