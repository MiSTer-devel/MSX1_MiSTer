// flash.sv: command decoding, programming, erasing, bounds of the backed area, status,
// autoselect and CFI. The memory is a model with the handshake of system_memory / sdram ch2.
// Run: wsl.exe -- bash rtl/peripheral/tb/run_flash.sh [old_dir]
//   old_dir: flash.sv and package.sv before the rewrite (+define+OLD_FLASH): only the
//            checks both versions can run (data bytes as commands, write during an erase,
//            boot sectors, area bounds).
module flash_tb;

logic clk = 0;
always #5 clk = ~clk;

localparam int BASE = 32'h0200000;      // system address of the chip address AREA_LO
localparam int AREA = 32'h002C000;      // backed part: 8 x 8 kB + 64 kB + 48 kB of the next sector
localparam int GUARD = 32'h0040000;     // watched memory above the area

flash_bus_if bus();
logic        reset = 0;
wire  [26:0] m_addr;
wire   [7:0] m_din;
wire         m_req, erasing;
logic        m_ready = 1, m_done = 0;

`ifdef OLD_FLASH
flash dut (.clk, .clk_sdram(clk), .flash_bus(bus), .sdram_ready(m_ready), .sdram_done(m_done),
           .sdram_addr(m_addr), .sdram_din(m_din), .sdram_req(m_req), .debug_erase(erasing));
`else
flash dut (.clk, .clk_sdram(clk), .reset, .flash_bus(bus), .sdram_ready(m_ready), .sdram_done(m_done),
           .sdram_addr(m_addr), .sdram_din(m_din), .sdram_req(m_req), .debug_erase(erasing));
`endif

// ------------------------------------------------------------------ memory model
logic [7:0] mem [int];
int         writes = 0, oob = 0;
logic       req_q = 0;
int         wait_n = 0;

function automatic logic [7:0] pat(input int a); return 8'(a * 5 + (a >> 8) + 8'h11) & 8'h7F; endfunction
function automatic logic [7:0] rdm(input int a); return mem.exists(a) ? mem[a] : pat(a); endfunction

always @(posedge clk) begin
    req_q <= m_req;
    if (!m_req) m_done <= 0;
    if (m_req && !req_q) begin wait_n <= 1 + $urandom_range(0, 4); m_ready <= 0; end
    else if (wait_n == 1) begin
        mem[int'(m_addr)] = m_din;
        writes++;
        if (int'(m_addr) < BASE || int'(m_addr) >= BASE + AREA) oob++;
        m_done <= 1; m_ready <= 1; wait_n <= 0;
    end else if (wait_n > 1) wait_n <= wait_n - 1;
end

// ------------------------------------------------------------------ bus
int   errors = 0;
logic chip = 0, id = 0;

task automatic cyc(input int n = 1); repeat (n) @(posedge clk); #1; endtask

task automatic drive(input int fa);
    bus.addr      = 23'(fa);
    bus.base_addr = 27'(0) - 27'(BASE);
`ifndef OLD_FLASH
    bus.area_lo   = '0;
    bus.area_size = 24'(AREA);
    bus.chip      = chip;
    bus.id        = id;
`endif
endtask

task automatic wr(input int fa, input logic [7:0] d, input int gap = 3);
    drive(fa); bus.data_to_flash = d; bus.ce = 1; bus.we = 1;
    cyc(2); bus.ce = 0; bus.we = 0; cyc(gap);
endtask

task automatic rd(input int fa, output logic valid, output logic [7:0] d);
    drive(fa); bus.ce = 1; bus.we = 0;
    cyc(2); valid = bus.data_valid; d = bus.data_from_flash; bus.ce = 0; cyc(2);
endtask

task automatic idle();          // operation finished: nothing requested for a while
    int quiet = 0, n = 0;
    while (quiet < 12) begin
        cyc();
        quiet = (m_req || erasing) ? 0 : quiet + 1;
        if (++n > 5_000_000) begin errors++; $display("FAIL operation does not finish"); return; end
    end
endtask

task automatic unlock();
    wr(32'hAAA, 8'hAA); wr(32'h555, 8'h55);
endtask

task automatic prog_byte(input int fa, input logic [7:0] d);
    unlock(); wr(32'hAAA, 8'hA0); wr(fa, d); idle();
endtask

task automatic erase_start(input int fa);
    unlock(); wr(32'hAAA, 8'h80); unlock(); wr(fa, 8'h30);
endtask

task automatic sector_erase(input int fa);
    erase_start(fa); idle();
endtask

task automatic restore();       // memory back to the pattern, counters cleared
    mem.delete(); writes = 0; oob = 0;
endtask

task automatic chk(input string what, input int fa, input logic [7:0] e);
    logic [7:0] v = rdm(BASE + fa);
    if (v !== e) begin errors++; if (errors < 40) $display("FAIL %s: %06h = %02h (expected %02h)", what, fa, v, e); end
endtask

// chip addresses lo .. hi-1 all erased (1) or all untouched (0)
task automatic chk_range(input string what, input int lo, input int hi, input bit erased);
    int bad = 0;
    for (int a = lo; a < hi; a++)
        if (rdm(BASE + a) !== (erased ? 8'hFF : pat(BASE + a))) bad++;
    if (bad) begin errors++; $display("FAIL %s: %06h-%06h %0d bytes %s", what, lo, hi - 1, bad, erased ? "not erased" : "changed"); end
endtask

task automatic chk_oob(input string what);
    if (oob) begin errors++; $display("FAIL %s: %0d writes outside the area", what, oob); end
endtask

`ifndef OLD_FLASH
task automatic chk_rd(input string what, input int fa, input logic ev, input logic [7:0] e);
    logic v; logic [7:0] d;
    rd(fa, v, d);
    if (v !== ev || (ev && d !== e)) begin
        errors++; $display("FAIL %s: read %06h valid %b data %02h (expected %b %02h)", what, fa, v, d, ev, e);
    end
endtask
`endif

initial begin
    logic v, v2; logic [7:0] d, d2;
    bus.ce = 0; bus.we = 0; bus.data_to_flash = '0; drive(0);
    cyc(5);

    // ---- data bytes are data, wherever they are written and whatever they are
    prog_byte(32'h0AAA, 8'hAA);                 // unlock address, unlock value
    prog_byte(32'h0100, 8'h12);
    chk("program AA at the unlock address", 32'h0AAA, 8'hAA);
    chk("program after it", 32'h0100, 8'h12);
    prog_byte(32'h0AAA, 8'h50);
    prog_byte(32'h0102, 8'h34);
    chk("program 50 at the unlock address", 32'h0AAA, 8'h50);
    chk("program after it", 32'h0102, 8'h34);

    // double byte program (M29W640GB) with 56 as the last byte at the unlock address
    restore();
    wr(32'hAAA, 8'h50); wr(32'h0200, 8'h11); wr(32'h0AAA, 8'h56); idle();
    wr(32'hAAA, 8'h50); wr(32'h0300, 8'h22); wr(32'h0301, 8'h33); idle();
    chk("double program", 32'h0200, 8'h11);
    chk("double program, 56 at the unlock address", 32'h0AAA, 8'h56);
    chk("double program after it", 32'h0300, 8'h22);
    chk("double program after it", 32'h0301, 8'h33);

    // ---- 8 kB boot sector
    restore();
    sector_erase(32'h2000);
    chk_range("erase of the boot sector 2000", 32'h0000, 32'h2000, 0);
    chk_range("erase of the boot sector 2000", 32'h2000, 32'h4000, 1);
    chk_range("erase of the boot sector 2000", 32'h4000, AREA, 0);

    // ---- 64 kB sector, a write of the CPU while it runs
    restore();
    erase_start(32'h10000);
    wait (erasing); cyc(1500);              // past the window for more sectors
    wr(32'h20100, 8'h77);
    wr(32'h0AAA, 8'hAA);
    idle();
    chk_range("erase 10000 with a write", 32'h00000, 32'h10000, 0);
    chk_range("erase 10000 with a write", 32'h10000, 32'h20000, 1);
    chk_range("erase 10000 with a write", 32'h20000, AREA, 0);

    // ---- area bounds
    restore();
    prog_byte(AREA + 32'h10, 8'h00);
    chk_oob("program above the area");
    sector_erase(32'h20000);                // the sector ends above the area
    chk_range("erase of the last sector", 32'h20000, AREA, 1);
    chk_oob("erase of the last sector");
    sector_erase(32'h30000);                // whole sector above the area
    chk_oob("erase above the area");
    if (rdm(BASE + AREA) !== pat(BASE + AREA)) begin errors++; $display("FAIL memory above the area changed"); end

`ifndef OLD_FLASH
    // ---- status while erasing, array reads go to the memory otherwise
    restore();
    chk_rd("idle read", 32'h0000, 0, 8'hFF);
    erase_start(32'h10000);
    rd(32'h10000, v, d);
    rd(32'h10000, v2, d2);
    if (!v || !v2 || d[7] || d[3] || d == 8'hFF || d[6] == d2[6] || d[2] == d2[2]) begin
        errors++; $display("FAIL status in the erase window: %b %02h, %b %02h", v, d, v2, d2);
    end
    cyc(1200);
    rd(32'h00000, v, d);                    // another sector: DQ2 does not toggle
    rd(32'h00000, v2, d2);
    if (!v || !v2 || d[7] || !d[3] || d[6] == d2[6] || d[2] != d2[2]) begin
        errors++; $display("FAIL status while erasing: %b %02h, %b %02h", v, d, v2, d2);
    end
    idle();
    chk_rd("read after the erase", 32'h10000, 0, 8'hFF);
    chk_range("erase 10000", 32'h10000, 32'h20000, 1);

    // ---- more sectors in one erase
    restore();
    erase_start(32'h10000);
    wr(32'h4000, 8'h30);
    cyc(1500);
    wr(32'h6000, 8'h30);                    // too late
    idle();
    chk_range("erase 4000 + 10000", 32'h0000, 32'h4000, 0);
    chk_range("erase 4000 + 10000", 32'h4000, 32'h6000, 1);
    chk_range("erase 4000 + 10000", 32'h6000, 32'h10000, 0);
    chk_range("erase 4000 + 10000", 32'h10000, 32'h20000, 1);
    chk_range("erase 4000 + 10000", 32'h20000, AREA, 0);

    // ---- chip erase
    restore();
    unlock(); wr(32'hAAA, 8'h80); unlock(); wr(32'hAAA, 8'h10);
    idle();
    chk_range("chip erase", 32'h0000, AREA, 1);
    chk_oob("chip erase");
    if (writes != AREA) begin errors++; $display("FAIL chip erase: %0d writes (expected %0d)", writes, AREA); end

    // ---- a broken sequence programs nothing
    restore();
    unlock(); wr(32'h0123, 8'hA0); wr(32'h0400, 8'h00); idle();
    wr(32'hAAA, 8'hAA); wr(32'hAAA, 8'hAA); wr(32'h555, 8'h55); wr(32'hAAA, 8'hA0); wr(32'h0401, 8'h00); idle();
    if (writes) begin errors++; $display("FAIL broken sequence wrote %0d bytes", writes); end
    prog_byte(32'h0402, 8'h5A);
    chk("program after broken sequences", 32'h0402, 8'h5A);

    // ---- quadruple byte program, bytes close together
    restore();
    wr(32'hAAA, 8'h56, 1); wr(32'h0500, 8'h01, 1); wr(32'h0501, 8'h02, 1); wr(32'h0502, 8'h03, 1); wr(32'h0503, 8'h04, 1);
    rd(32'h0500, v, d);                     // still writing: status, DQ7 = /data
    if (!v || d[7] !== 1'b1) begin errors++; $display("FAIL status while programming: %b %02h", v, d); end
    idle();
    for (int i = 0; i < 4; i++) chk("quadruple program", 32'h0500 + i, 8'(i + 1));
    if (writes != 4) begin errors++; $display("FAIL quadruple program: %0d writes", writes); end

    // ---- autoselect and CFI, M29W640GB
    unlock(); wr(32'hAAA, 8'h90);
    chk_rd("M29W640GB manufacturer", 32'h00, 1, 8'h20);
    chk_rd("M29W640GB device",       32'h02, 1, 8'h7E);
    chk_rd("M29W640GB device 2",     32'h1C, 1, 8'h10);
    chk_rd("M29W640GB device 3",     32'h1E, 1, 8'h00);
    chk_rd("M29W640GB odd byte",     32'h03, 1, 8'h00);
    chk_rd("M29W640GB extended",     32'h06, 1, 8'h08);
    chk_rd("M29W640GB protection",   32'h04, 1, 8'h00);
    prog_byte(32'h0600, 8'h00);               // not accepted in autoselect
    if (rdm(BASE + 32'h0600) !== pat(BASE + 32'h0600)) begin errors++; $display("FAIL program in autoselect"); end
    wr(32'h0000, 8'hF0);
    chk_rd("M29W640GB after reset", 32'h00, 0, 8'hFF);
    wr(32'h0AA, 8'h98);
    chk_rd("M29W640GB CFI Q",       32'h20, 1, 8'h51);
    chk_rd("M29W640GB CFI device",  32'h04, 1, 8'h10);
    chk_rd("M29W640GB CFI device hi", 32'h05, 1, 8'h22);
    chk_rd("M29W640GB CFI buffer",  32'h54, 1, 8'h05);
    wr(32'h0000, 8'hFF);                    // not an exit on this chip
    chk_rd("M29W640GB CFI R",       32'h22, 1, 8'h52);
    unlock(); wr(32'hAAA, 8'hF0);
    chk_rd("M29W640GB after long reset", 32'h20, 0, 8'hFF);

    // ---- S29GL064S
    chip = 1;
    unlock(); wr(32'hAAA, 8'h90);
    chk_rd("S29GL064S manufacturer", 32'h00, 1, 8'h01);
    chk_rd("S29GL064S device",       32'h02, 1, 8'h7E);
    chk_rd("S29GL064S device, odd",  32'h03, 1, 8'h7E);
    chk_rd("S29GL064S device 2",     32'h1C, 1, 8'h10);
    chk_rd("S29GL064S device 3",     32'h1E, 1, 8'h00);
    chk_rd("S29GL064S mirror",       32'h22, 1, 8'h7E);
    chk_rd("S29GL064S protection",   32'h04, 1, 8'h00);
    chk_rd("S29GL064S undefined",    32'h08, 1, 8'hFF);
    wr(32'h0AA, 8'h98);                     // CFI straight from autoselect
    chk_rd("S29GL064S CFI Q",        32'h20, 1, 8'h51);
    chk_rd("S29GL064S CFI R",        32'h22, 1, 8'h52);
    chk_rd("S29GL064S CFI Y",        32'h24, 1, 8'h59);
    chk_rd("S29GL064S CFI size",     32'h4E, 1, 8'h17);
    chk_rd("S29GL064S CFI regions",  32'h58, 1, 8'h02);
    chk_rd("S29GL064S CFI 8 sectors", 32'h5A, 1, 8'h07);
    chk_rd("S29GL064S CFI of 8 kB",  32'h5E, 1, 8'h20);
    chk_rd("S29GL064S CFI 127 sectors", 32'h62, 1, 8'h7E);
    chk_rd("S29GL064S CFI of 64 kB", 32'h68, 1, 8'h01);
    chk_rd("S29GL064S CFI id",       32'h02, 1, 8'h7E);
    chk_rd("S29GL064S CFI id hi",    32'h03, 1, 8'h22);
    chk_rd("S29GL064S CFI unused",   32'hA2, 1, 8'hFF);
    wr(32'h0000, 8'hFF);
    chk_rd("S29GL064S after CFI exit", 32'h20, 0, 8'hFF);

    restore();
    wr(32'hAAA, 8'h50); wr(32'h0700, 8'h00); wr(32'h0701, 8'h00); idle();
    if (writes) begin errors++; $display("FAIL S29GL064S took a double byte program"); end
    prog_byte(32'h0702, 8'hC3);
    chk("S29GL064S program", 32'h0702, 8'hC3);

    // ---- the state belongs to one cartridge
    unlock(); wr(32'hAAA, 8'h90);
    id = 1;
    chk_rd("other cartridge in autoselect", 32'h00, 0, 8'hFF);
    prog_byte(32'h0800, 8'h3C);
    chk("program of the other cartridge", 32'h0800, 8'h3C);
    id = 0;
    chk_rd("first cartridge after the other wrote", 32'h00, 0, 8'hFF);
    erase_start(32'h10000);
    id = 1;
    chk_rd("other cartridge while erasing", 32'h10000, 0, 8'hFF);
    wr(32'h0000, 8'hF0);
    id = 0;
    rd(32'h10000, v, d);
    if (!v) begin errors++; $display("FAIL erase ended by the other cartridge"); end
    idle();

    // ---- machine reset stops an erase
    restore();
    erase_start(32'h10000);
    wait (erasing); cyc(2000);
    reset = 1; cyc(4); reset = 0; cyc(20);
    begin
        int w = writes;
        cyc(2000);
        if (writes != w || erasing || w == 0 || w >= 32'h10000) begin
            errors++; $display("FAIL reset in an erase: %0d writes, %0d after it, erasing %b", w, writes - w, erasing);
        end
    end
    chk_rd("read after the reset", 32'h10000, 0, 8'hFF);
    chk_oob("at the end");
`endif

    if (errors == 0) $display("PASS flash_tb");
    else             $display("FAILED flash_tb: %0d errors", errors);
    $finish;
end

endmodule
