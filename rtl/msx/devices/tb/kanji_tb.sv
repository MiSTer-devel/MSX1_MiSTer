// dev_kanji against openMSX MSXKanji: one address for both levels, JIS2 (level 2) 128 kB above
// JIS1, auto increment of the 32-byte character, level 2 only inside the font and with jis2_en;
// level 2 access by param[3:2] (read / write / interlocked_write_read / only_level_1), hangul
// (param[0]) takes 7 bits of the row.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_kanji.sh [alt_kanji.sv]
module kanji_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if cpu_bus(clk, rst);
MSX::io_device_t         io_device[3];
MSX::io_device_mem_ref_t io_memory[8];
logic        jis2_en = 1;
wire         ram_cs;
wire  [26:0] ram_addr;

dev_kanji dut (.cpu_bus(cpu_bus), .io_device(io_device), .io_memory(io_memory),
               .jis2_en(jis2_en), .ram_cs(ram_cs), .ram_addr(ram_addr));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        iorq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

localparam logic [26:0] BASE = 27'h0444000;
int errors = 0;

task automatic io_write(input logic [7:0] port, input logic [7:0] d);
    @(negedge clk); addr = {8'h00, port}; dbo = d; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    @(negedge clk); iorq = 0; wr = 0;
endtask

// I/O read held for 3 clk (as a CPU cycle); the memory request appears during it
task automatic io_read(input string what, input logic [7:0] port, input logic exp_cs, input logic [26:0] exp_addr);
    logic seen = 0;
    logic [26:0] got = '1;
    @(negedge clk); addr = {8'h00, port}; iorq = 1; rd = 1; req = 1;
    @(negedge clk); req = 0;
    for (int i = 0; i < 2; i++) begin
        if (ram_cs) begin seen = 1; got = ram_addr; end
        @(negedge clk);
    end
    iorq = 0; rd = 0;
    if (seen !== exp_cs || (exp_cs && got !== exp_addr)) begin
        errors++;
        $display("FAIL %s: ram_cs=%b addr=%07h (expected cs=%b addr=%07h)", what, seen, got, exp_cs, exp_addr);
    end
endtask

task automatic set_param(input logic [7:0] p);
    io_device[0].param = p;
endtask
task automatic do_reset();
    @(negedge clk); rst = 1; @(negedge clk); rst = 0;
endtask

initial begin
    for (int i = 0; i < 3; i++)
        io_device[i] = '{mask: 8'hFC, port: 8'hD8, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: i == 0};
    for (int i = 0; i < 8; i++) io_memory[i] = '{memory: BASE, memory_size: 8'd16};   // 256 kB
    repeat (3) @(negedge clk); rst = 0;

    // JIS1: row 21h, column 12h -> {row[5:0], col[5:0], 5'b0}
    io_write(8'hD8, 8'h12);
    io_write(8'hD9, 8'h21);
    io_read("JIS1 byte 0", 8'hD9, 1, BASE + {10'd0, 6'h21, 6'h12, 5'd0});
    io_read("JIS1 byte 1", 8'hD9, 1, BASE + {10'd0, 6'h21, 6'h12, 5'd1});
    io_read("D8 read: no memory", 8'hD8, 0, '1);

    // JIS2: 128 kB above JIS1
    io_write(8'hDA, 8'h05);
    io_write(8'hDB, 8'h30);
    io_read("JIS2 byte 0", 8'hDB, 1, BASE + 27'h20000 + {10'd0, 6'h30, 6'h05, 5'd0});

    // JIS2 disabled (OCM 384 kB BIOS)
    jis2_en = 0;
    io_read("JIS2 disabled", 8'hDB, 0, '1);
    io_read("JIS1 still on (shared address)", 8'hD9, 1, BASE + {10'd0, 6'h30, 6'h05, 5'd2});
    jis2_en = 1;

    // 128 kB font: no JIS2
    for (int i = 0; i < 8; i++) io_memory[i].memory_size = 8'd8;
    io_read("JIS2 with 128 kB", 8'hDB, 0, '1);

    for (int i = 0; i < 8; i++) io_memory[i].memory_size = 8'd16;

    // read (default): the address written at D8/D9 is read as level 2 at DBh
    do_reset();
    io_write(8'hD8, 8'h12); io_write(8'hD9, 8'h21);
    io_read("read: DBh after D8/D9 = level 2 of the same character", 8'hDB, 1, BASE + 27'h20000 + {10'd0, 6'h21, 6'h12, 5'd0});
    io_read("read: D9h continues the counter at level 1", 8'hD9, 1, BASE + {10'd0, 6'h21, 6'h12, 5'd1});

    // write (FS-A1ST / GT): the level of the last write, any read port
    set_param(8'h04); do_reset();
    io_write(8'hDA, 8'h05); io_write(8'hDB, 8'h30);
    io_read("write: D9h after DA/DB = level 2", 8'hD9, 1, BASE + 27'h20000 + {10'd0, 6'h30, 6'h05, 5'd0});
    io_write(8'hD8, 8'h05);
    io_read("write: DBh after D8 = level 1, counter reset", 8'hDB, 1, BASE + {10'd0, 6'h30, 6'h05, 5'd0});

    // interlocked_write_read (FS-A1WX / WSX): a read of the other level: FFh, no increment
    set_param(8'h08); do_reset();
    io_write(8'hD8, 8'h12); io_write(8'hD9, 8'h21);
    io_read("interlocked: DBh after D8/D9 = nothing", 8'hDB, 0, '1);
    io_read("interlocked: D9h byte 0 (no increment)", 8'hD9, 1, BASE + {10'd0, 6'h21, 6'h12, 5'd0});
    io_write(8'hDA, 8'h12);
    io_read("interlocked: D9h after DA = nothing", 8'hD9, 0, '1);
    io_read("interlocked: DBh after DA = level 2, counter reset", 8'hDB, 1, BASE + 27'h20000 + {10'd0, 6'h21, 6'h12, 5'd0});

    // only_level_1 (FS-A1F / FX): DAh / DBh act as D8h / D9h
    set_param(8'h0C); do_reset();
    io_write(8'hDA, 8'h12); io_write(8'hDB, 8'h21);
    io_read("only_level_1: DBh = level 1", 8'hDB, 1, BASE + {10'd0, 6'h21, 6'h12, 5'd0});

    // hangul: 7 bits of the row, 6 of the column
    set_param(8'h01); do_reset();
    io_write(8'hD8, 8'h7F); io_write(8'hD9, 8'h41);
    io_read("hangul: row 41h, column 3Fh", 8'hD9, 1, BASE + {9'd0, 7'h41, 6'h3F, 5'd0});

    // outside the font (128 kB): level 2 reads nothing
    set_param(8'h00); do_reset();
    for (int i = 0; i < 8; i++) io_memory[i].memory_size = 8'd8;
    io_read("128 kB: DBh nothing", 8'hDB, 0, '1);
    io_read("128 kB: D9h byte 1", 8'hD9, 1, BASE + 27'd1);

    if (errors == 0) $display("PASS kanji_tb");
    else             $display("FAILED kanji_tb: %0d errors", errors);
    $finish;
end

endmodule
