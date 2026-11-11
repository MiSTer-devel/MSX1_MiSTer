// mapper_neo (NEO-8, NEO-16) against a model of openMSX RomNeo8 / RomNeo16 / RomBlocks::setRom.
// Random writes over the whole address space, two cartridges, several ROM sizes.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_neo.sh [alt_neo.sv]
module neo_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_neo dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out));

logic [15:0] addr;
logic  [7:0] data;
logic        mreq, rd, wr, req;
assign cpu_bus.addr = addr;
assign cpu_bus.data = data;
assign cpu_bus.mreq = mreq;
assign cpu_bus.rd   = rd;
assign cpu_bus.wr   = wr;
assign cpu_bus.req  = req;

int unsigned model[2][6];                       // [cartridge][register], as openMSX blockReg
int errors = 0, checked = 0;

function automatic void model_reset();
    for (int c = 0; c < 2; c++) for (int r = 0; r < 6; r++) model[c][r] = 0;
endfunction

// RomNeo8::writeMem / RomNeo16::writeMem
function automatic void model_write(input bit is16, input bit id, input int unsigned a, input int unsigned v);
    int unsigned bbb, region;
    bbb = (a >> 11) & 7;
    if (bbb < 2) return;
    if (is16 && (bbb & 1)) return;
    region = is16 ? (bbb >> 1) - 1 : bbb - 2;
    if ((a & 1) == 0) model[id][region] = (model[id][region] & 'hFF00) | v;
    else              model[id][region] = (model[id][region] & 'h00FF) | ((v & 'hF) << 8);
endfunction

// Read: expected memory offset, or -1 = unmapped (FF)
function automatic longint model_read(input bit is16, input bit id, input int unsigned a, input int unsigned rom);
    int unsigned bsize, page, nr, blk;
    bsize = is16 ? 'h4000 : 'h2000;
    page  = a / bsize;
    if (page >= (is16 ? 3 : 6)) return -1;
    nr  = rom / bsize;
    blk = model[id][page];
    blk = (blk < nr) ? blk : blk & (nr - 1);    // RomBlocks::setRom
    if (blk >= nr) return -1;
    return longint'(blk) * bsize + (a % bsize);
endfunction

task automatic do_write(input bit is16, input bit id, input logic [15:0] a, input logic [7:0] v);
    block_info.id = id;
    addr = a; data = v; mreq = 1; wr = 1; rd = 0; req = 1;
    @(posedge clk); #1;
    req = 0; wr = 0; mreq = 0;
    model_write(is16, id, a, v);
endtask

task automatic check_read(input bit is16, input bit id, input logic [15:0] a, input int unsigned rom);
    longint exp;
    block_info.id = id;
    addr = a; mreq = 1; rd = 1; wr = 0; req = 1;
    #1;
    exp = model_read(is16, id, a, rom);
    checked++;
    if (exp < 0 ? (out.ram_cs !== 1'b0 || out.addr !== '1)
                : (out.ram_cs !== 1'b1 || out.addr !== 27'(exp))) begin
        errors++;
        if (errors <= 20)
            $display("FAIL %s id=%0d rom=%0d kB addr=%04h: cs=%b addr=%07h, exp %0d",
                     is16 ? "NEO-16" : "NEO-8", id, rom / 1024, a, out.ram_cs, out.addr, exp);
    end
    if (out.rnw !== 1'b1 || out.sram_cs !== 1'b0 || out.main_cs !== 1'b0 || out.data !== 8'hFF) begin
        errors++;
        if (errors <= 20) $display("FAIL unused outputs at %04h", a);
    end
    @(posedge clk); #1;
    rd = 0; req = 0; mreq = 0;
endtask

// Sizes: power of two, not a power of two, the largest in the database, 16 MB
int unsigned sizes[6] = '{'h8000, 'h20000, 'h60000, 'h180000, 15032 * 1024, 'h1000000};

initial begin
    block_info = '0;
    mreq = 0; rd = 0; wr = 0; req = 0; addr = 0; data = 0;
    repeat (2) @(posedge clk);
    #1 rst = 0;

    for (int t = 0; t < 2; t++) begin
        bit is16 = t[0];
        block_info.typ = is16 ? MAPPER_NEO16 : MAPPER_NEO8;
        foreach (sizes[s]) begin
            if (is16 && sizes[s] % 'h4000) continue;
            block_info.rom_size = 25'(sizes[s]);
            rst = 1; @(posedge clk); #1 rst = 0;
            model_reset();

            // After reset all banks are 0
            for (int a = 0; a < 'h10000; a += 'h0800) check_read(is16, 0, 16'(a + 'h123), sizes[s]);

            for (int i = 0; i < 4000; i++) begin
                bit id = 1'($urandom);
                logic [15:0] a = 16'($urandom);
                logic [7:0]  v = 8'($urandom);
                if ($urandom % 3 == 0) begin
                    // Bank register area (with mirrors), even and odd address
                    a[13:11] = 3'(2 + $urandom % 6);
                end
                if ($urandom % 2) do_write(is16, id, a, v);
                else              check_read(is16, id, a, sizes[s]);
            end
            // Sweep every page of both cartridges
            for (int id = 0; id < 2; id++)
                for (int a = 0; a < 'h10000; a += 'h1000) check_read(is16, 1'(id), 16'(a + 'h0FFF), sizes[s]);
        end
    end

    // Not active: other mapper type, no mreq
    block_info.typ = MAPPER_ASCII8; block_info.rom_size = 25'h20000;
    addr = 16'h4000; mreq = 1; rd = 1; #1;
    if (out.ram_cs !== 1'b0 || out.addr !== '1) begin errors++; $display("FAIL active for another type"); end
    block_info.typ = MAPPER_NEO8; mreq = 0; #1;
    if (out.ram_cs !== 1'b0) begin errors++; $display("FAIL active without mreq"); end
    // A write of another type must not change the banks
    rst = 1; @(posedge clk); #1 rst = 0;
    model_reset();
    do_write(0, 0, 16'h5000, 8'h03);
    block_info.typ = MAPPER_ASCII8; addr = 16'h5000; data = 8'h07; mreq = 1; wr = 1; req = 1;
    @(posedge clk); #1 wr = 0; req = 0; mreq = 0;
    block_info.typ = MAPPER_NEO8;
    check_read(0, 0, 16'h0000, 'h20000);
    if (out.addr !== 27'h6000 && errors == 0) begin errors++; $display("FAIL bank changed by another mapper type"); end

    if (errors == 0) $display("PASS neo_tb (%0d reads)", checked);
    else             $display("FAILED neo_tb: %0d errors of %0d", errors, checked);
    $finish;
end

endmodule
