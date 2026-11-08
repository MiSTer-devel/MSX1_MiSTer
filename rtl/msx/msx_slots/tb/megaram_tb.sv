// mapper_megaram (ESE MegaSCC+ / MegaRAM, OCM internal slots) against megaram.vhd of
// MSX_MiSTer: SCC-I banks and RAM write modes (BFFE bit 4), ASCII-16K banks with write
// enable (bit 7) and A20 (bit 6), SCC sound in SCC / SCC+ mode, RAM address limited to the
// block (1 MB MegaSCC+ 1MB) and to 1 MB for the OCM slot 1.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_megaram.sh      (OLD=<git rev>: old megaram.sv)
module megaram_tb;

logic clk = 0, reset = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, reset);
MSX::block_info_t block_info;
MSX::mapper_out_t out;
MSX::device_bus_t device_out;
logic             slot1_mode = 1'b1;          // internal SCC-I
logic       [1:0] slot2_mode = 2'b10;         // SCC-I

mapper_megaram dut (.cpu_bus(cpu_bus), .out(out), .block_info(block_info), .device_out(device_out),
                    .ocm_slot1_mode(slot1_mode), .ocm_slot2_mode(slot2_mode));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        mreq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = 1'b0;  assign cpu_bus.mreq = mreq;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

int errors = 0;

task automatic write(input logic [15:0] a, input logic [7:0] d);
    @(negedge clk); addr = a; dbo = d; mreq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    @(negedge clk); mreq = 0; wr = 0;
endtask

// Sample the mapper outputs during a read or write (no register change for a read)
task automatic access(input logic [15:0] a, input logic w, output MSX::mapper_out_t o,
                      output MSX::device_bus_t dv);
    @(negedge clk); addr = a; dbo = 8'h5A; mreq = 1; rd = !w; wr = w; req = 0;   // no req: no register write
    #1; o = out; dv = device_out;
    @(negedge clk); mreq = 0; rd = 0; wr = 0;
endtask

task automatic expect_ram(input string what, input logic [15:0] a, input logic w, input logic [26:0] exp);
    MSX::mapper_out_t o;
    MSX::device_bus_t dv;
    access(a, w, o, dv);
    if (!o.ram_cs || o.addr !== exp || o.rnw !== !w)
        begin errors++; $display("FAIL %s: ram_cs=%b addr=%07h rnw=%b (expected addr %07h rnw %b)", what, o.ram_cs, o.addr, o.rnw, exp, !w); end
endtask

task automatic expect_no_write(input string what, input logic [15:0] a);
    MSX::mapper_out_t o;
    MSX::device_bus_t dv;
    access(a, 1'b1, o, dv);
    if (o.ram_cs && !o.rnw) begin errors++; $display("FAIL %s: RAM written at %07h", what, o.addr); end
endtask

task automatic expect_scc(input string what, input logic [15:0] a, input logic mode);
    MSX::mapper_out_t o;
    MSX::device_bus_t dv;
    access(a, 1'b1, o, dv);
    if (!dv.en || dv.mode !== mode)
        begin errors++; $display("FAIL %s: scc en=%b mode=%b (expected en 1 mode %b)", what, dv.en, dv.mode, mode); end
endtask

task automatic set_block(input mapper_typ_t t, input logic id, input int size);
    block_info = '0;
    block_info.typ      = t;
    block_info.id       = id;
    block_info.rom_size = 25'(size);
endtask

initial begin
    set_block(MAPPER_MEGARAM, 1'b1, 2 * 1024 * 1024);
    repeat (3) @(negedge clk); reset = 0;

    // ---- slot 2, SCC-I: banks 5000/7000/9000/B000, read-only until a RAM mode is set
    write(16'h5000, 8'h05); write(16'h7000, 8'h06); write(16'h9000, 8'h07); write(16'hB000, 8'hFF);
    expect_ram("SCC-I bank 4000", 16'h4123, 1'b0, 27'h05 * 27'h2000 + 27'h0123);
    expect_ram("SCC-I bank 8000", 16'h8123, 1'b0, 27'h07 * 27'h2000 + 27'h0123);
    expect_ram("SCC-I bank FF (2 MB)", 16'hA123, 1'b0, 27'hFF * 27'h2000 + 27'h0123);
    expect_no_write("SCC-I read-only", 16'h8123);
    write(16'hBFFE, 8'h10);                              // BFFE bit 4: 4000-BFFD R/W
    expect_ram("RAM mode write 8000", 16'h8123, 1'b1, 27'h07 * 27'h2000 + 27'h0123);
    expect_ram("RAM mode write 4000", 16'h4001, 1'b1, 27'h05 * 27'h2000 + 27'h0001);
    write(16'hBFFE, 8'h00);

    // ---- capacity probe of SofaROM (SROM.COM 36E4): per bank N: 7FFE <- 0, 5000 <- N,
    //      7FFE <- 10h (ESCC-RAM: 4000-7FFD R/W), then write / read 4100h
    for (int n = 0; n < 256; n += 51) begin
        write(16'h7FFE, 8'h00);
        write(16'h5000, 8'(n));
        write(16'h7FFE, 8'h10);
        expect_ram($sformatf("SofaROM probe bank %0d write", n), 16'h4100, 1'b1, 27'(n) * 27'h2000 + 27'h0100);
        expect_ram($sformatf("SofaROM probe bank %0d read", n), 16'h4100, 1'b0, 27'(n) * 27'h2000 + 27'h0100);
    end
    write(16'h5000, 8'h11);                              // ignored while 7FFE bit 4 is set
    expect_ram("bank register locked in ESCC-RAM mode", 16'h4100, 1'b0, 27'd255 * 27'h2000 + 27'h0100);
    write(16'h7FFE, 8'h00);
    write(16'h5000, 8'h05);

    // ---- SCC sound: SCC mode (9800, BFFE bit 5 = 0) and SCC+ mode (B800)
    write(16'h9000, 8'h3F);
    expect_scc("SCC mode 9800", 16'h9800, 1'b0);
    write(16'hBFFE, 8'h20);
    write(16'hB000, 8'h80);
    expect_scc("SCC+ mode B800", 16'hB800, 1'b1);
    write(16'hBFFE, 8'h00);

    // ---- OCM slot 1 has 1 MB (emsx_top Scc1Adr)
    set_block(MAPPER_MEGARAM, 1'b0, 2 * 1024 * 1024);
    write(16'h5000, 8'h85);
    expect_ram("slot 1 bank 85 -> 05 (1 MB)", 16'h4010, 1'b0, 27'h05 * 27'h2000 + 27'h0010);

    // ---- MegaSCC+ 1MB cartridge: bank 81 wraps inside the 1 MB block
    set_block(MAPPER_MEGASCC, 1'b0, 1024 * 1024);
    write(16'h7000, 8'h81);
    expect_ram("MegaSCC+ 1MB bank 81 -> 01", 16'h6010, 1'b0, 27'h01 * 27'h2000 + 27'h0010);

    // ---- slot 2 switched to ASCII-16K (port 42h): 6000 / 7000, bit 7 write enable, bit 6 A20
    set_block(MAPPER_MEGARAM, 1'b1, 2 * 1024 * 1024);
    slot2_mode = 2'b11;
    write(16'h6000, 8'h83);                              // write enabled, 16 kB bank 3
    write(16'h7000, 8'h45);                              // read-only, bank 5 + A20
    expect_ram("ASCII16 bank 3 read", 16'h5000, 1'b0, 27'h3 * 27'h4000 + 27'h1000);
    expect_ram("ASCII16 bank 3 write", 16'h4004, 1'b1, 27'h3 * 27'h4000 + 27'h0004);
    expect_ram("ASCII16 bank 5 + A20", 16'h9000, 1'b0, 27'h100000 + 27'h5 * 27'h4000 + 27'h1000);
    expect_no_write("ASCII16 read-only bank", 16'h9000);

    if (errors == 0) $display("PASS megaram_tb");
    else             $display("FAILED megaram_tb: %0d errors", errors);
    $finish;
end

endmodule
