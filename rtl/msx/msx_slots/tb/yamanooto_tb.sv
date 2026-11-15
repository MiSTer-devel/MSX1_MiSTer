// mapper_yamanooto with the real flash.sv and a memory model. Expected behaviour from openMSX
// Yamanooto.cc: mirrors, registers 7FFC-7FFF (readable with REGEN), offset added when a bank is
// written, SUBOFF, Konami SCC and Konami4 modes, MDIS, ROMDIS, WREN (all writes to the flash),
// FPGA ID sequence, SCC / SCC+ areas (raw bank registers), ECHO output, two cartridges.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_yamanooto.sh
module yamanooto_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

localparam int BASE_A = 32'h0800000, BASE_B = 32'h1000000;     // memory of the cartridges
localparam int SIZE   = 32'h0800000;                           // 8 MB flash each

cpu_bus_if        cpu_bus(clk, rst);
flash_bus_if      flash_bus();
MSX::block_info_t block_info;
MSX::mapper_out_t out;
MSX::device_bus_t dev;
wire              psg_echo;

mapper_yamanooto dut (.cpu_bus(cpu_bus), .flash_bus(flash_bus), .block_info(block_info), .out(out),
                      .device_out(dev), .psg_echo(psg_echo));

wire  [26:0] m_addr;
wire   [7:0] m_din;
wire         m_req, erasing;
logic        m_ready = 1, m_done = 0;
flash u_flash (.clk, .clk_sdram(clk), .reset(rst), .flash_bus(flash_bus), .sdram_ready(m_ready),
               .sdram_done(m_done), .sdram_addr(m_addr), .sdram_din(m_din), .sdram_req(m_req),
               .debug_erase(erasing));

// ------------------------------------------------------------------ memory model
logic [7:0] mem [int];
int         writes = 0;
logic       req_q = 0;
int         wait_n = 0;
always @(posedge clk) begin
    req_q <= m_req;
    if (!m_req) m_done <= 0;
    if (m_req && !req_q) begin wait_n <= 1 + $urandom_range(0, 3); m_ready <= 0; end
    else if (wait_n == 1) begin mem[int'(m_addr)] = m_din; writes++; m_done <= 1; m_ready <= 1; wait_n <= 0; end
    else if (wait_n > 1) wait_n <= wait_n - 1;
end

// ------------------------------------------------------------------ CPU
logic [15:0] addr = '0;
logic  [7:0] data = '0;
logic        mreq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = data;
assign cpu_bus.mreq = mreq;  assign cpu_bus.rd = rd;  assign cpu_bus.wr = wr;
assign cpu_bus.req  = req;   assign cpu_bus.iorq = 1'b0;  assign cpu_bus.m1 = 1'b0;

int   errors = 0;
logic cart = 0;

task automatic select(input mapper_typ_t typ);
    block_info.typ        = typ;
    block_info.id         = cart;
    block_info.base_ram   = 27'(cart ? BASE_B : BASE_A);
    block_info.rom_size   = 25'(SIZE);
    block_info.device_ref = 3'd1;
endtask

task automatic fail(input string s); errors++; $display("FAIL %s", s); endtask

logic w_en, w_fwe;
task automatic write(input logic [15:0] a, input logic [7:0] d, input mapper_typ_t typ = MAPPER_YAMANOOTO);
    select(typ); addr = a; data = d; mreq = 1; wr = 1; req = 1;
    #1 w_en = dev.en; w_fwe = flash_bus.we;
    @(posedge clk); #1 req = 0;
    @(posedge clk); #1 mreq = 0; wr = 0;
    @(posedge clk); #1;
endtask

// exp_cs 1 = memory at offset exp; 0 = data exp from the mapper (-1 any, -2 not FF); exp_scc
logic r_mode;
task automatic read(input string what, input logic [15:0] a, input logic exp_cs, input int exp,
                    input logic exp_scc = 0, input mapper_typ_t typ = MAPPER_YAMANOOTO);
    select(typ); addr = a; mreq = 1; rd = 1; req = 1;
    @(posedge clk); #1 req = 0;
    r_mode = dev.mode;
    if (out.ram_cs !== exp_cs)
        fail($sformatf("%s: read %04h ram_cs %b (expected %b)", what, a, out.ram_cs, exp_cs));
    else if (exp_cs ? out.addr !== 27'(exp) : (exp >= 0 && out.data !== 8'(exp)))
        fail($sformatf("%s: read %04h addr %07h data %02h (expected %0h)", what, a, out.addr, out.data, exp));
    if (!exp_cs && exp == -2 && out.data === 8'hFF) fail($sformatf("%s: read %04h data FF", what, a));
    if (dev.en !== exp_scc) fail($sformatf("%s: read %04h SCC enable %b (expected %b)", what, a, dev.en, exp_scc));
    if (exp_scc && flash_bus.ce) fail($sformatf("%s: read %04h of the SCC also reads the flash", what, a));
    @(posedge clk); #1 mreq = 0; rd = 0;
    @(posedge clk); #1;
endtask

task automatic idle();
    int quiet = 0;
    while (quiet < 12) begin @(posedge clk); quiet = (m_req || erasing) ? 0 : quiet + 1; end
    #1;
endtask

task automatic chk_mem(input string what, input int a, input logic [7:0] e);
    if (!mem.exists(a) || mem[a] !== e)
        fail($sformatf("%s: memory %07h = %s (expected %02h)", what, a, mem.exists(a) ? $sformatf("%02h", mem[a]) : "not written", e));
endtask

task automatic flash_prog(input logic [15:0] a, input logic [7:0] d);
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h4AAA, 8'hA0);
    write(a, d);
endtask

function automatic int at(input int bank, input int off); return bank * 8192 + off; endfunction

initial begin
    select(MAPPER_YAMANOOTO);
    repeat (3) @(posedge clk); #1 rst = 0;

    // ---- reset: banks 0-3; 0000-3FFF mirrors 8000-BFFF, C000-FFFF mirrors 4000-7FFF
    read("reset, 4000",        16'h4000, 1, at(0, 0));
    read("reset, 6000",        16'h6123, 1, at(1, 16'h123));
    read("reset, 8000",        16'h8000, 1, at(2, 0));
    read("reset, A000",        16'hBFFF, 1, at(3, 16'h1FFF));
    read("mirror 0000 = 8000", 16'h0010, 1, at(2, 16'h10));
    read("mirror 2000 = A000", 16'h2000, 1, at(3, 0));
    read("mirror C000 = 4000", 16'hC000, 1, at(0, 0));
    read("mirror E000 = 6000", 16'hE000, 1, at(1, 0));
    if (psg_echo !== 1'b0) fail("ECHO after reset");

    // ---- registers hidden without REGEN
    read("7FFF without REGEN: flash", 16'h7FFF, 1, at(1, 16'h1FFF));
    write(16'h7FFE, 8'h05);                             // offset: ignored
    write(16'h5000, 8'h01);
    read("offset ignored without REGEN", 16'h4000, 1, at(1, 0));

    // ---- REGEN: registers readable
    write(16'h7FFF, 8'h01);
    read("ENAR",           16'h7FFF, 0, 8'h01);
    read("CFGR | 80h",     16'h7FFD, 0, 8'h80);
    read("OFFR",           16'h7FFE, 0, 8'h00);
    read("FPGA reg off",   16'h7FFC, 0, 8'hFF);
    read("FFFF: no register (mirror, flash)", 16'hFFFF, 1, at(1, 16'h1FFF));

    // ---- Konami SCC banks, also through the mirrors
    write(16'h5000, 8'h05);  read("5000 <- 05", 16'h4000, 1, at(5, 0));
    write(16'hD000, 8'h06);  read("D000 (mirror 5000) <- 06", 16'h4000, 1, at(6, 0));
    write(16'h7000, 8'h07);  read("7000 <- 07", 16'h6000, 1, at(7, 0));
    write(16'h1000, 8'h09);  read("1000 (mirror 9000) <- 09", 16'h8000, 1, at(9, 0));
    write(16'hB7FF, 8'h0B);  read("B7FF <- 0B", 16'hA000, 1, at(16'h0B, 0));
    write(16'h5800, 8'h33);  read("5800 not a register", 16'h4000, 1, at(6, 0));

    // ---- offset: added when the bank is written, 10 bit
    write(16'h7FFE, 8'h02);                             // offset 2 << 2 = 8
    read("offset does not switch at once", 16'h4000, 1, at(6, 0));
    read("OFFR reads back", 16'h7FFE, 0, 8'h02);
    write(16'h5000, 8'h01);  read("5000 <- 01 + 8", 16'h4000, 1, at(9, 0));
    write(16'h7FFD, 8'h30);                             // SUBOFF 3: offset 11
    write(16'h7000, 8'h01);  read("7000 <- 01 + 11", 16'h6000, 1, at(12, 0));
    write(16'h7FFE, 8'hFF);                             // offset 3FCh + 3 = 3FFh
    write(16'h9000, 8'h02);  read("9000 <- 02 + 3FF wraps", 16'h8000, 1, at(1, 0));
    write(16'h7FFD, 8'h00);                             // offset 3FCh
    write(16'hB000, 8'h03);  read("bank 3FF: top of the 8 MB", 16'hA000, 1, at(16'h3FF, 0));
    write(16'h7FFE, 8'h00);

    // ---- MDIS
    write(16'h7FFD, 8'h01);
    write(16'h5000, 8'h22);  read("MDIS: 5000 ignored", 16'h4000, 1, at(9, 0));
    write(16'h7FFD, 8'h00);

    // ---- SCC: raw bank 2 & 3F = 3F, all of 9800-9FFF
    write(16'h7FFE, 8'h01);                             // offset 4: the SCC still looks at the raw value
    write(16'h9000, 8'h3F);
    read("bank 2 = 3F + 4", 16'h8000, 1, at(16'h43, 0));
    read("SCC 9800",           16'h9800, 0, -1, 1);
    if (r_mode !== 1'b0) fail("SCC mode: mode 0");
    read("SCC 9900 (no bit 8 rule)", 16'h9900, 0, -1, 1);
    read("SCC 9FFF",           16'h9FFF, 0, -1, 1);
    read("SCC 1800 (mirror)",  16'h1800, 0, -1, 1);
    write(16'h9800, 8'h55);    if (w_en !== 1'b1) fail("SCC write enable");
    write(16'h7FFE, 8'h00);

    // SCC+: BFFE bit 5, raw bank 3 bit 7, B800-BFFD
    write(16'hBFFE, 8'h20);
    read("SCC+ mode: 9800 flash", 16'h9800, 1, at(16'h43, 16'h1800), 0);
    write(16'hB000, 8'h80);
    read("SCC+ B800", 16'hB800, 0, -1, 1);
    if (r_mode !== 1'b1) fail("SCC+ mode: mode 1");
    read("SCC+ BFFD", 16'hBFFD, 0, -1, 1);
    read("BFFE not SCC", 16'hBFFE, 1, at(16'h80, 16'h1FFE), 0);
    write(16'hBFFF, 8'h00);
    read("BFFF is the mode register too", 16'h9800, 0, -1, 1);

    // ---- Konami4: 6000-BFFF switch, 4000-5FFF keeps its bank, no SCC
    write(16'h7FFD, 8'h08);
    read("K4: no SCC", 16'h9800, 1, at(16'h43, 16'h1800), 0);
    write(16'h5000, 8'h44);  read("K4: 5000 not switched", 16'h4000, 1, at(9, 0));
    write(16'h6000, 8'h0A);  read("K4: 6000 <- 0A", 16'h6000, 1, at(16'h0A, 0));
    write(16'h8800, 8'h0C);  read("K4: 8800 <- 0C", 16'h8000, 1, at(16'h0C, 0));
    write(16'hA000, 8'h0D);  read("K4: A000 <- 0D", 16'hA000, 1, at(16'h0D, 0));
    write(16'h7FFD, 8'h09);                             // K4 + MDIS
    write(16'h6000, 8'h0F);  read("K4 + MDIS: 6000 ignored", 16'h6000, 1, at(16'h0A, 0));
    write(16'h7FFD, 8'h00);

    // ---- ROMDIS
    write(16'h7FFD, 8'h04);
    read("ROMDIS: FF", 16'h4000, 0, 8'hFF);
    if (flash_bus.ce) fail("ROMDIS: flash selected");
    write(16'h7FFD, 8'h00);

    // ---- ECHO
    write(16'h7FFD, 8'h02);
    if (psg_echo !== 1'b1) fail("ECHO set");
    write(16'h7FFD, 8'h00);
    if (psg_echo !== 1'b0) fail("ECHO cleared");

    // ---- FPGA ID: 9F, then 1F 23 00 00
    write(16'h7FFD, 8'h40);
    read("FPGA idle", 16'h7FFC, 0, 8'hFF);
    write(16'h7FFC, 8'h9F);  read("FPGA ID 1", 16'h7FFC, 0, 8'h1F);
    write(16'h7FFC, 8'h00);  read("FPGA ID 2", 16'h7FFC, 0, 8'h23);
    write(16'h7FFC, 8'h00);  read("FPGA ID 3", 16'h7FFC, 0, 8'h00);
    write(16'h7FFC, 8'h00);  read("FPGA ID 4", 16'h7FFC, 0, 8'h00);
    write(16'h7FFC, 8'h00);  read("FPGA idle again", 16'h7FFC, 0, 8'hFF);
    read("CFGR with FPGA_EN", 16'h7FFD, 0, 8'hC0);
    write(16'h7FFD, 8'h00);

    // ---- REGEN off: registers locked except ENAR
    write(16'h7FFF, 8'h00);
    write(16'h7FFD, 8'h04);
    read("REGEN off: CFGR not written", 16'h4000, 1, at(9, 0));

    // ---- WREN: every write goes to the flash, no bank switching
    write(16'h5000, 8'h00);                             // bank 0 = 0 for the commands
    write(16'h7FFF, 8'h11);
    write(16'h5000, 8'h05);
    read("WREN: 5000 not switched", 16'h4000, 1, at(0, 0));
    writes = 0;
    write(16'h8000, 8'h00); idle();                     // stray write: no command
    flash_prog(16'h8123, 8'hC3);
    idle();
    chk_mem("WREN program", BASE_A + at(16'h0C, 16'h123), 8'hC3);
    write(16'h7FFD, 8'h04);                             // ROMDIS: no flash write
    if (w_fwe) fail("write of CFGR itself went to the flash with ROMDIS set");
    flash_prog(16'h8124, 8'h3C);
    if (w_fwe) fail("ROMDIS: flash write");
    idle();
    if (mem.exists(BASE_A + at(16'h0C, 16'h124))) fail("ROMDIS: programmed");
    write(16'h7FFD, 8'h00);
    write(16'h4000, 8'hF0);

    // ---- autoselect (S29GL064)
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h4AAA, 8'h90);
    read("manufacturer", 16'h4000, 0, 8'h01);
    read("device",       16'h4002, 0, 8'h7E);
    write(16'h4000, 8'hF0);
    read("after the reset command", 16'h4000, 1, at(0, 0));
    write(16'h7FFF, 8'h01);

    // ---- another mapper in the slot
    write(16'h5000, 8'h33, MAPPER_KONAMI_SCC);
    read("other mapper", 16'h4000, 0, 8'hFF, 0, MAPPER_KONAMI_SCC);
    if (out.addr !== '1 || flash_bus.ce !== 1'b0) fail("other mapper drives the bus");

    // ---- cartridge B: own registers and memory
    cart = 1;
    read("cartridge B after reset", 16'h8000, 1, at(2, 0));
    read("cartridge B: registers hidden", 16'h7FFF, 1, at(1, 16'h1FFF));
    write(16'h9000, 8'h0B);
    read("cartridge B bank", 16'h8000, 1, at(16'h0B, 0));
    write(16'h7FFF, 8'h10);
    flash_prog(16'h8010, 8'hA5);
    idle();
    chk_mem("program, cartridge B", BASE_B + at(16'h0B, 16'h10), 8'hA5);
    cart = 0;
    read("cartridge A keeps its bank", 16'h8000, 1, at(16'h0C, 0));

    $display("end at %0t, %0d flash writes", $time, writes);
    if (errors == 0) $display("PASS yamanooto_tb");
    else             $display("FAILED yamanooto_tb: %0d errors", errors);
    $finish;
end

endmodule
