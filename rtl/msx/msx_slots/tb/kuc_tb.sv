// mapper_kuc (Konami Ultimate Collection) with the real flash.sv and a memory model. Expected
// behaviour from openMSX KonamiUltimateCollection.cc: bank registers in the Konami SCC and Konami
// modes, offset, A21-A20, the disable bits, DAC strobe, SCC / SCC+ areas (address bit 8 = 0),
// flash commands through the mapper, two cartridges.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_kuc.sh
module kuc_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

localparam int BASE_A = 32'h0800000, BASE_B = 32'h1000000;     // memory of the cartridges
localparam int SIZE   = 32'h0800000;                           // 8 MB flash each

cpu_bus_if        cpu_bus(clk, rst);
flash_bus_if      flash_bus();
MSX::block_info_t block_info;
MSX::mapper_out_t out;
MSX::device_bus_t dev;

mapper_kuc dut (.cpu_bus(cpu_bus), .flash_bus(flash_bus), .block_info(block_info), .out(out), .device_out(dev));

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
logic cart = 0;                                     // cartridge of the next accesses

task automatic select(input mapper_typ_t typ);
    block_info.typ        = typ;
    block_info.id         = cart;
    block_info.base_ram   = 27'(cart ? BASE_B : BASE_A);
    block_info.rom_size   = 25'(SIZE);
    block_info.device_ref = 3'd1;
endtask

task automatic fail(input string s); errors++; $display("FAIL %s", s); endtask

// Write; returns what the mapper drove during it: DAC strobe, SCC enable, flash write
logic w_we, w_en, w_fwe;
task automatic write(input logic [15:0] a, input logic [7:0] d, input mapper_typ_t typ = MAPPER_KUC);
    select(typ); addr = a; data = d; mreq = 1; wr = 1; req = 1;
    #1 w_we = dev.we; w_en = dev.en; w_fwe = flash_bus.we;
    @(posedge clk); #1 req = 0;
    @(posedge clk); #1 mreq = 0; wr = 0;
    @(posedge clk); #1;
endtask

// Read: exp_cs 1 = from the memory at the offset exp of the cartridge; 0 = data exp from the
// mapper (-1: any, -2: anything but FF). exp_scc: SCC enable expected.
logic r_mode;
task automatic read(input string what, input logic [15:0] a, input logic exp_cs, input int exp,
                    input logic exp_scc = 0, input mapper_typ_t typ = MAPPER_KUC);
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

task automatic flash_prog(input logic [15:0] a, input logic [7:0] d);   // page 1 = bank 0 for the commands
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h4AAA, 8'hA0);
    write(a, d);
endtask

function automatic int at(input int bank, input int off); return bank * 8192 + off; endfunction

initial begin
    select(MAPPER_KUC);
    repeat (3) @(posedge clk); #1 rst = 0;

    // ---- reset: banks 0-3, mapper Konami SCC
    read("reset, 4000",  16'h4000, 1, at(0, 0));
    read("reset, 6000",  16'h6123, 1, at(1, 16'h123));
    read("reset, 8000",  16'h8000, 1, at(2, 0));
    read("reset, A000",  16'hBFFF, 1, at(3, 16'h1FFF));
    read("0000 unmapped", 16'h0000, 0, 8'hFF);
    read("C000 unmapped", 16'hC000, 0, 8'hFF);
    if (dev.param !== 1'b1) fail("SCC+ chip (param)");

    // ---- Konami SCC: 5000-57FF, 7000-77FF, 9000-97FF, B000-B7FF
    write(16'h5000, 8'h05);  read("5000 <- 05", 16'h4000, 1, at(5, 0));
    write(16'h57FF, 8'h06);  read("57FF <- 06", 16'h4000, 1, at(6, 0));
    write(16'h5800, 8'h07);  read("5800 not a register", 16'h4000, 1, at(6, 0));
    write(16'h6000, 8'h07);  read("6000 not a register (SCC mode)", 16'h6000, 1, at(1, 0));
    write(16'h7000, 8'h17);  read("7000 <- 17", 16'h6000, 1, at(16'h17, 0));
    write(16'h9000, 8'h29);  read("9000 <- 29", 16'h8000, 1, at(16'h29, 0));
    write(16'hB7FF, 8'hFB);  read("B7FF <- FB: not masked", 16'hA000, 1, at(16'hFB, 0));

    // ---- offset 7FFE: added to every bank, 8 bit wrap
    write(16'h7FFE, 8'h03);
    read("offset 3, 4000", 16'h4000, 1, at(6 + 3, 0));
    read("offset 3, A000", 16'hA000, 1, at(16'hFE, 0));
    write(16'h7FFE, 8'h06);
    read("offset 6, A000 wraps", 16'hA000, 1, at(16'h01, 0));
    write(16'h7FFE, 8'h00);

    // ---- 7FFF bits 7-6: 2 MB bank of the flash
    write(16'h7FFF, 8'hC0);
    read("A21-A20 = 3", 16'h4010, 1, 32'h600000 + at(6, 16'h10));
    write(16'h7FFF, 8'h40);
    read("A21-A20 = 1", 16'h8000, 1, 32'h200000 + at(16'h29, 0));
    write(16'h7FFF, 8'h00);

    // ---- Konami mode: 5000-57FF and all of 6000-BFFF
    write(16'h7FFF, 8'h20);
    read("7FFF in 6000-7FFF switched bank 1 (Konami)", 16'h6000, 1, at(16'h20, 0));
    write(16'h4FFF, 8'h11);  read("4FFF not a register", 16'h4000, 1, at(6, 0));
    write(16'h5800, 8'h11);  read("5800 not a register (Konami)", 16'h4000, 1, at(6, 0));
    write(16'h5000, 8'h12);  read("5000 <- 12 (Konami)", 16'h4000, 1, at(16'h12, 0));
    write(16'h6000, 8'h13);  read("6000 <- 13", 16'h6000, 1, at(16'h13, 0));
    write(16'h8800, 8'h14);  read("8800 <- 14", 16'h8000, 1, at(16'h14, 0));
    write(16'hA800, 8'h15);  read("A800 <- 15", 16'hA000, 1, at(16'h15, 0));

    // ---- bit 3: 4000-5FFF fixed in the Konami mode, DAC on 4000-5FFF with address bit 4 = 0
    write(16'h7FFF, 8'h28);
    write(16'h5000, 8'h33);
    if (w_we !== 1'b1) fail("DAC strobe at 5000");
    read("bit 3: 5000 not switched", 16'h4000, 1, at(16'h12, 0));
    write(16'h4000, 8'h80);  if (w_we !== 1'b1) fail("DAC strobe at 4000");
    write(16'h4010, 8'h80);  if (w_we !== 1'b0) fail("no DAC at 4010 (bit 4)");
    write(16'h6000, 8'h80);  if (w_we !== 1'b0) fail("no DAC at 6000");
    write(16'h7FFF, 8'h20);
    write(16'h4000, 8'h80);  if (w_we !== 1'b0) fail("no DAC without bit 3");
    write(16'h7FFF, 8'h08);                             // Konami SCC with bit 3
    write(16'h5000, 8'h34);  if (w_we !== 1'b1) fail("DAC strobe in the Konami SCC mode");
    read("bit 3 does not fix 4000 in the Konami SCC mode", 16'h4000, 1, at(16'h34, 0));

    // ---- bit 1: no bank switching, no SCC mode register
    write(16'h7FFF, 8'h02);
    write(16'h5000, 8'h44);  read("bit 1: 5000 ignored", 16'h4000, 1, at(16'h34, 0));
    write(16'hBFFE, 8'h20);
    write(16'hB000, 8'h80);
    read("bit 1: no SCC+ mode", 16'hB800, 1, at(16'h15, 16'h1800), 0);
    write(16'h7FFF, 8'h00);

    // ---- SCC (Konami SCC mode): bank 2 & 3F = 3F, 9800-9FFD, address bit 8 = 0
    write(16'h9000, 8'h3F);
    read("SCC 9800",          16'h9800, 0, -1, 1);
    if (r_mode !== 1'b0) fail("SCC mode: mode 0");
    read("SCC 9A55",          16'h9A55, 0, -1, 1);
    read("9900: bit 8 = 1",   16'h9900, 1, at(16'h3F, 16'h1900), 0);
    read("9FFE not SCC",      16'h9FFE, 1, at(16'h3F, 16'h1FFE), 0);
    read("SCC 9EFF",          16'h9EFF, 0, -1, 1);
    read("8800 not SCC",      16'h8800, 1, at(16'h3F, 16'h0800), 0);
    write(16'h9000, 8'h7F);
    read("bank 7F: SCC",      16'h9800, 0, -1, 1);
    write(16'h9000, 8'h3E);
    read("bank 3E: no SCC",   16'h9800, 1, at(16'h3E, 16'h1800), 0);

    // SCC also in the Konami mode
    write(16'h7FFF, 8'h20);
    write(16'h8000, 8'h3F);
    read("SCC in the Konami mode", 16'h9800, 0, -1, 1);
    write(16'h9800, 8'h55);
    if (w_en !== 1'b1) fail("SCC write enable");
    read("SCC write did not switch bank 2", 16'h8000, 1, at(16'h3F, 0));
    write(16'h7FFF, 8'h00);

    // ---- SCC+: BFFE bit 5, bank 3 bit 7, B800-BFFD
    write(16'hBFFE, 8'h20);
    read("SCC+ mode: 9800 no longer SCC", 16'h9800, 1, at(16'h3F, 16'h1800), 0);
    write(16'hB000, 8'h80);
    read("SCC+ B800", 16'hB800, 0, -1, 1);
    if (r_mode !== 1'b1) fail("SCC+ mode: mode 1");
    read("SCC+ BA10", 16'hBA10, 0, -1, 1);
    read("SCC+ B900: bit 8", 16'hB900, 1, at(16'h80, 16'h1900), 0);
    read("SCC+ BFFE not SCC", 16'hBFFE, 1, at(16'h80, 16'h1FFE), 0);
    write(16'hBFFE, 8'h30);
    read("BFFE bit 4: SCC off", 16'hB800, 1, at(16'h80, 16'h1800), 0);
    write(16'hBFFF, 8'h00);
    read("BFFF also the mode register: SCC back", 16'h9800, 0, -1, 1);
    write(16'hB000, 8'h03);

    // ---- bit 2: 7FFE / 7FFF locked
    write(16'h5000, 8'h00);
    write(16'h7FFF, 8'h04);
    write(16'h7FFE, 8'h10);
    write(16'h7FFF, 8'h20);
    read("bit 2: offset not written", 16'h4000, 1, at(0, 0));
    write(16'h6000, 8'h21);
    read("bit 2: still Konami SCC (6000 no register)", 16'h6000, 1, at(16'h20, 0));

    // ---- another mapper in the slot: nothing of ours
    write(16'h5000, 8'h33, MAPPER_KONAMI_SCC);
    read("other mapper", 16'h4000, 0, 8'hFF, 0, MAPPER_KONAMI_SCC);
    if (out.addr !== '1 || flash_bus.ce !== 1'b0) fail("other mapper drives the bus");

    // ---- reset clears the lock
    rst = 1; repeat (2) @(posedge clk); #1 rst = 0;
    read("after reset", 16'h4000, 1, at(0, 0));

    // ---- flash: program only with 7FFF bit 4
    writes = 0;
    flash_prog(16'h8123, 8'h5A);
    idle();
    if (writes) fail($sformatf("program without bit 4 wrote %0d bytes", writes));
    write(16'h7FFF, 8'h10);
    flash_prog(16'h8123, 8'hC3);
    idle();
    chk_mem("program", BASE_A + at(2, 16'h123), 8'hC3);

    // write into a bank register: the flash gets the bank before the write
    flash_prog(16'h9000, 8'h19);
    idle();
    chk_mem("program through the register area", BASE_A + at(2, 16'h1000), 8'h19);
    read("bank after it", 16'h8000, 1, at(16'h19, 0));

    // offset and A21-A20 take part in the flash address
    write(16'h7FFF, 8'h50);                             // A20, write enabled
    write(16'h7FFE, 8'h01);                             // commands: only address bits 11-0 count
    flash_prog(16'hA004, 8'h66);
    idle();
    chk_mem("program with offset and A20", BASE_A + 32'h200000 + at(3 + 1, 4), 8'h66);
    write(16'h7FFE, 8'h00);
    write(16'h7FFF, 8'h10);

    // the SCC area takes no flash write
    write(16'h9000, 8'h3F);
    write(16'hBFFE, 8'h00);
    flash_prog(16'h9810, 8'h77);
    if (w_fwe) fail("write to the SCC went to the flash");
    if (!w_en) fail("write to the SCC: no SCC enable");
    idle();
    write(16'h4000, 8'hF0);

    // ---- autoselect (M29W640GB)
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h4AAA, 8'h90);
    read("manufacturer", 16'h4000, 0, 8'h20);
    read("device",       16'h4002, 0, 8'h7E);
    write(16'h4000, 8'hF0);
    read("after the reset command", 16'h4000, 1, at(0, 0));

    // ---- cartridge B: own registers and memory
    cart = 1;
    read("cartridge B after reset", 16'h8000, 1, at(2, 0));
    write(16'h9000, 8'h0B);
    read("cartridge B bank", 16'h8000, 1, at(16'h0B, 0));
    write(16'h7FFF, 8'h10);
    flash_prog(16'h8010, 8'hA5);
    idle();
    chk_mem("program, cartridge B", BASE_B + at(16'h0B, 16'h10), 8'hA5);
    cart = 0;
    read("cartridge A keeps its bank", 16'h8000, 1, at(16'h3F, 0));

    $display("end at %0t, %0d flash writes", $time, writes);
    if (errors == 0) $display("PASS kuc_tb");
    else             $display("FAILED kuc_tb: %0d errors", errors);
    $finish;
end

endmodule
