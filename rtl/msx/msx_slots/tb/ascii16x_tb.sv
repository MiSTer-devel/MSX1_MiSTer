// mapper_ascii16x with the real flash.sv and a memory model: bank registers and their
// mirrors (https://www.grauw.nl/projects/ascii-x/ascii16-x/), reads of the ROM image,
// flash commands through the mapper (program, erase, autoselect), the ROM size as the limit.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_ascii16x.sh
module ascii16x_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

localparam int BASE_A = 32'h0300000, BASE_B = 32'h0C00000;     // memory of the cartridges
localparam int SIZE   = 32'h0100000;                           // 1 MB each

cpu_bus_if        cpu_bus(clk, rst);
flash_bus_if      flash_bus();
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_ascii16x dut (.cpu_bus(cpu_bus), .flash_bus(flash_bus), .block_info(block_info), .out(out));

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
    block_info.typ      = typ;
    block_info.id       = cart;
    block_info.base_ram = 27'(cart ? BASE_B : BASE_A);
    block_info.rom_size = 25'(SIZE);
endtask

task automatic write(input logic [15:0] a, input logic [7:0] d, input mapper_typ_t typ = MAPPER_ASCII16X);
    select(typ); addr = a; data = d; mreq = 1; wr = 1; req = 1;
    @(posedge clk); #1 req = 0;
    @(posedge clk); #1 mreq = 0; wr = 0;
    @(posedge clk); #1;
endtask

// Read: exp_cs 1 = from the memory at the offset exp of the cartridge; 0 = data exp from the
// mapper (-1: any, -2: anything but FF)
task automatic read(input string what, input logic [15:0] a, input logic exp_cs, input int exp,
                    input mapper_typ_t typ = MAPPER_ASCII16X);
    select(typ); addr = a; mreq = 1; rd = 1; req = 1;
    @(posedge clk); #1 req = 0;
    if (out.ram_cs !== exp_cs) begin
        errors++; $display("FAIL %s: read %04h ram_cs %b (expected %b)", what, a, out.ram_cs, exp_cs);
    end else if (exp_cs ? out.addr !== 27'(exp) : (exp >= 0 && out.data !== 8'(exp))) begin
        errors++; $display("FAIL %s: read %04h addr %07h data %02h (expected %0h)", what, a, out.addr, out.data, exp);
    end
    if (!exp_cs && exp == -2 && out.data === 8'hFF) begin errors++; $display("FAIL %s: read %04h data FF", what, a); end
    @(posedge clk); #1 mreq = 0; rd = 0;
    @(posedge clk); #1;
endtask

task automatic idle();
    int quiet = 0;
    while (quiet < 12) begin @(posedge clk); quiet = (m_req || erasing) ? 0 : quiet + 1; end
    #1;
endtask

task automatic chk_mem(input string what, input int a, input logic [7:0] e);
    if (!mem.exists(a) || mem[a] !== e) begin
        errors++; $display("FAIL %s: memory %07h = %s (expected %02h)", what, a, mem.exists(a) ? $sformatf("%02h", mem[a]) : "not written", e);
    end
endtask

function automatic int at(input int bank, input int off); return bank * 16384 + off; endfunction

initial begin
    select(MAPPER_ASCII16X);
    repeat (3) @(posedge clk); #1 rst = 0;

    // ---- reset: bank 0 in both pages
    read("reset, page 1",        16'h4000, 1, at(0, 0));
    read("reset, page 2",        16'h8123, 1, at(0, 16'h123));
    read("reset, page 1 mirror", 16'hC000, 1, at(0, 0));
    read("reset, page 2 mirror", 16'h3FFF, 1, at(0, 16'h3FFF));

    // ---- bank registers: number = {A11..A8, data}, 9 bits used
    write(16'h6000, 8'h27);
    read("6000 <- 27",        16'h4123, 1, at(16'h027, 16'h123));
    read("6000 <- 27 mirror", 16'hC123, 1, at(16'h027, 16'h123));
    read("page 2 untouched",  16'h8000, 1, at(0, 0));
    write(16'h6100, 8'h47);                                 // bank 147h: above the 1 MB image
    read("6100 <- 47",        16'h4000, 0, 8'hFF);
    write(16'h6E00, 8'h31);                                 // A9..A11 ignored
    read("6E00 <- 31",        16'h7FFF, 1, at(16'h031, 16'h3FFF));
    write(16'h7000, 8'h05);
    read("7000 <- 05",        16'h8000, 1, at(5, 0));
    read("7000 <- 05 mirror", 16'h0010, 1, at(5, 16'h10));
    read("page 1 untouched",  16'h4000, 1, at(16'h031, 0));
    write(16'hA000, 8'h03);   read("A000 <- 03", 16'h4000, 1, at(3, 0));
    write(16'hE000, 8'h04);   read("E000 <- 04", 16'h4000, 1, at(4, 0));
    write(16'h2000, 8'h06);   read("2000 <- 06", 16'h4000, 1, at(6, 0));
    write(16'hB000, 8'h07);   read("B000 <- 07", 16'h8000, 1, at(7, 0));
    write(16'hF000, 8'h08);   read("F000 <- 08", 16'h8000, 1, at(8, 0));
    write(16'h3000, 8'h09);   read("3000 <- 09", 16'h8000, 1, at(9, 0));
    write(16'h3FFF, 8'h0A);   read("3FFF <- 0A: bank 10A, above the image", 16'h8000, 0, 8'hFF);
    write(16'h7000, 8'h02);
    write(16'h4000, 8'h55);   write(16'h5FFF, 8'h55);       // not registers
    write(16'h8000, 8'h55);   write(16'h1FFF, 8'h55);
    read("lower half is not a register, page 1", 16'h4000, 1, at(6, 0));
    read("lower half is not a register, page 2", 16'h8000, 1, at(2, 0));
    write(16'h6000, 8'h3F);   read("bank 3F", 16'h7FFF, 1, at(16'h3F, 16'h3FFF));
    write(16'h6000, 8'h40);   read("bank 40: above the image", 16'h4000, 0, 8'hFF);

    // ---- another mapper in the slot: nothing of ours
    write(16'h6000, 8'h01);
    write(16'h6000, 8'h33, MAPPER_ASCII16);
    read("other mapper", 16'h4000, 0, 8'hFF, MAPPER_ASCII16);
    if (out.addr !== '1 || flash_bus.ce !== 1'b0) begin errors++; $display("FAIL other mapper: addr %07h flash ce %b", out.addr, flash_bus.ce); end
    read("write of another mapper", 16'h4000, 1, at(1, 0));

    // ---- two cartridges
    cart = 1;
    read("cartridge B after reset", 16'h4000, 1, at(0, 0));
    write(16'h6000, 8'h0B);
    read("cartridge B bank", 16'h4000, 1, at(16'h0B, 0));
    cart = 0;
    read("cartridge A keeps its bank", 16'h4000, 1, at(1, 0));

    // ---- program a byte: page 1 = bank 0 for the commands, the target in page 2
    write(16'h6000, 8'h00);
    write(16'h7000, 8'h05);
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h4AAA, 8'hA0);
    write(16'h9234, 8'hC3);
    idle();
    chk_mem("program", BASE_A + at(5, 16'h1234), 8'hC3);
    read("read after the program", 16'h9234, 1, at(5, 16'h1234));

    // data written into the register area: the flash sees the bank before the write
    write(16'h7000, 8'h02);
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h4AAA, 8'hA0);
    write(16'hB400, 8'h19);
    idle();
    chk_mem("program through the register area", BASE_A + at(2, 16'h3400), 8'h19);
    read("bank after it", 16'h8000, 1, at(16'h019, 0));

    // above the image: not programmed
    writes = 0;
    write(16'h7000, 8'h40);
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h4AAA, 8'hA0);
    write(16'h8000, 8'h00);
    idle();
    if (writes) begin errors++; $display("FAIL program above the image wrote %0d bytes", writes); end

    // ---- autoselect
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h4AAA, 8'h90);
    read("manufacturer", 16'h4000, 0, 8'h01);
    read("device",       16'h4002, 0, 8'h7E);
    read("device 2",     16'h401C, 0, 8'h10);
    read("device 3",     16'h401E, 0, 8'h00);
    cart = 1;
    read("cartridge B reads its ROM", 16'h4000, 1, at(16'h0B, 0));
    cart = 0;
    write(16'h4000, 8'hF0);
    read("after the reset command", 16'h4000, 1, at(0, 0));

    // ---- CFI
    write(16'h40AA, 8'h98);
    read("CFI Q", 16'h4020, 0, 8'h51);
    read("CFI size", 16'h404E, 0, 8'h17);
    write(16'h4000, 8'hF0);

    // ---- sector erase: bank 4 = flash 10000-13FFF, sector 10000-1FFFF
    writes = 0;
    write(16'h7000, 8'h04);
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h4AAA, 8'h80);
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h8000, 8'h30);
    read("status while erasing", 16'h8000, 0, -2);
    read("status in the other page", 16'h4000, 0, -2);
    idle();
    read("after the erase", 16'h8000, 1, at(4, 0));
    if (writes != 65536) begin errors++; $display("FAIL sector erase: %0d writes", writes); end
    chk_mem("erase, first byte", BASE_A + 32'h10000, 8'hFF);
    chk_mem("erase, last byte",  BASE_A + 32'h1FFFF, 8'hFF);
    if (mem.exists(BASE_A + 32'h0FFFF) || mem.exists(BASE_A + 32'h20000)) begin errors++; $display("FAIL erase outside the sector"); end

    // ---- cartridge B: its own memory
    cart = 1;
    write(16'h6000, 8'h00); write(16'h7000, 8'h01);
    write(16'h4AAA, 8'hAA); write(16'h4555, 8'h55); write(16'h4AAA, 8'hA0);
    write(16'h8010, 8'h5A);
    idle();
    chk_mem("program, cartridge B", BASE_B + at(1, 16'h10), 8'h5A);

    if (errors == 0) $display("PASS ascii16x_tb");
    else             $display("FAILED ascii16x_tb: %0d errors", errors);
    $finish;
end

endmodule
