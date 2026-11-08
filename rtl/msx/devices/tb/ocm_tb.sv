// dev_ocm against OCM-PLD swioports.vhd: ports 40h-4Fh (ID 212 / 008), virtual DIP-SW,
// lock mask, smart commands, warm / cold reset, IPL phase (until the first write to A8h),
// CPU speed (emsx_top): IPL / logo limiter, F11, ID008, custom turbo, hybrid MegaSD.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_ocm.sh [alt_ocm.sv]
module ocm_tb;

logic clk = 0;
always #5 clk = ~clk;

// Core reset as in msx.sv: registered, from the hard reset and the swio request
logic hard = 1, reset = 1;
wire  swio_reset;
always_ff @(posedge clk) reset <= hard || swio_reset;

cpu_bus_if   cpu_bus(clk, reset);
clock_bus_if clock_bus(clk, clk);
MSX::io_device_t io_device[3];
logic [7:0] dip;
wire  [7:0] data;
wire        ipl_en, jis2_en, mapper_limit, megaSD_enable, Slot1Mode, rst_key_lock;
wire  [1:0] Slot2Mode;
logic [10:0] ps2_key = '0;
logic        mmc_on = 0;
MSX::cpu_speed_t cpu_speed;

dev_ocm dut (.cpu_bus(cpu_bus), .clock_bus(clock_bus), .io_device(io_device), .ff_dip_req(dip),
             .ps2_key(ps2_key), .mmc_on(mmc_on), .cpu_speed(cpu_speed),
             .data(data), .ipl_en(ipl_en), .jis2_en(jis2_en), .mapper_limit(mapper_limit), .megaSD_enable(megaSD_enable),
             .Slot1Mode(Slot1Mode), .Slot2Mode(Slot2Mode), .rst_key_lock(rst_key_lock),
             .swio_reset(swio_reset));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        iorq = 0, rd = 0, wr = 0, req = 0, ce_10hz = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;
assign clock_bus.ce_10hz = ce_10hz;

int errors = 0;

task automatic io_write(input logic [7:0] port, input logic [7:0] d);
    @(negedge clk); addr = {8'h00, port}; dbo = d; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    @(negedge clk); iorq = 0; wr = 0;
endtask

task automatic expect_read(input string what, input logic [7:0] port, input logic [7:0] exp);
    @(negedge clk); addr = {8'h00, port}; iorq = 1; rd = 1;
    #1;
    if (data !== exp) begin errors++; $display("FAIL %s: port %02h = %02h, expected %02h", what, port, data, exp); end
    @(negedge clk); iorq = 0; rd = 0;
endtask

task automatic check_bit(input string what, input logic got, input logic exp);
    if (got !== exp) begin errors++; $display("FAIL %s: %b, expected %b", what, got, exp); end
endtask

task automatic tick_10hz();
    @(negedge clk); ce_10hz = 1;
    @(negedge clk); ce_10hz = 0;
endtask

// PS/2 event in MiSTer format: [10] toggles, [9] pressed, [8] extended, [7:0] code
task automatic key(input logic [7:0] code, input logic pressed);
    @(negedge clk); ps2_key = {~ps2_key[10], pressed, 1'b0, code};
    repeat (2) @(negedge clk);
endtask

task automatic f11();
    key(8'h78, 1); key(8'h78, 0);
endtask

// clock_sel (msx_cpu: 0 3.58, 1 10.7, 2 5.39 MHz), memory and I/O wait states
task automatic expect_speed(input string what, input logic [1:0] sel, input logic [3:0] mw, input logic [3:0] iow);
    repeat (2) @(negedge clk);
    if (cpu_speed.en !== 1'b1 || cpu_speed.clock_sel !== sel || cpu_speed.mem_wait !== mw || cpu_speed.io_wait !== iow) begin
        errors++;
        $display("FAIL %s: en=%b sel=%0d mem_wait=%0d io_wait=%0d, expected sel=%0d mem_wait=%0d io_wait=%0d",
                 what, cpu_speed.en, cpu_speed.clock_sel, cpu_speed.mem_wait, cpu_speed.io_wait, sel, mw, iow);
    end
endtask

task automatic wait_reset_done();
    int n = 0;
    while (!reset && n < 10000) begin @(negedge clk); n++; end
    if (!reset) begin errors++; $display("FAIL no reset (swio_reset)"); return; end
    wait (!reset);
    repeat (2) @(negedge clk);
endtask

initial begin
    for (int i = 0; i < 3; i++)
        io_device[i] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0};
    io_device[0].enable = 1'b1;
    // MegaSD on, mapper 4096 kB, slot 2 MegaSCC+ (Slot2Mode 10 -> bits 5:4 = 01), slot 1 SCC-I, display 11, turbo off
    dip = 8'b1_1_01_1_11_0;
    repeat (4) @(negedge clk); hard = 0;
    repeat (4) @(negedge clk);

    // ---- cold reset state
    check_bit("ipl_en after reset", ipl_en, 1'b1);
    check_bit("MegaSD from DIP", megaSD_enable, 1'b1);
    check_bit("mapper 4096 kB from DIP", mapper_limit, 1'b0);
    check_bit("reset key unlocked", rst_key_lock, 1'b0);
    tick_10hz();
    check_bit("Slot1Mode", Slot1Mode, 1'b1);
    if (Slot2Mode !== 2'b10) begin errors++; $display("FAIL Slot2Mode %b, expected 10", Slot2Mode); end

    // ---- ports, ID 212
    expect_read("port 40 before ID",  8'h40, 8'hFF);
    expect_read("ID 212 not selected", 8'h42, 8'hFF);
    io_write(8'h40, 8'hD4);
    expect_read("port 40 ID 212",     8'h40, 8'h2B);
    expect_read("virtual DIP-SW",     8'h42, dip);
    expect_read("lock mask",          8'h43, 8'h00);
    expect_read("lights mask",        8'h44, 8'h00);
    expect_read("physical DIP-SW",    8'h4C, dip);
    expect_read("PLD version",        8'h4E, 8'd38);
    expect_read("keyb/rev",           8'h4F, 8'h89);
    io_write(8'h43, 8'hFE);                       // write_n: lock turbo
    expect_read("lock mask written",  8'h43, 8'h01);
    io_write(8'h44, 8'hFD);
    expect_read("lights mask written", 8'h44, 8'h02);
    expect_read("lock mask kept",     8'h43, 8'h01);

    // ---- smart commands
    io_write(8'h41, 8'd16);                       // SCC-I slot 1 + SCC-I slot 2
    expect_read("slot modes by cmd 16", 8'h42, {dip[7:6], 3'b011, dip[2:0]});
    io_write(8'h41, 8'd57);                       // MegaSD locked
    expect_read("MegaSD lock",        8'h43, 8'h81);
    dip[7] = 1'b0;                                // OSD: MegaSD off -> ignored while locked
    repeat (4) @(negedge clk);
    expect_read("locked DIP ignored", 8'h47, 8'hCF);   // MegaSD_req, Mapper_req, tMegaSD, speed level 7
    io_write(8'h41, 8'd29);                       // MegaSD off request
    check_bit("MegaSD stays until warm reset", megaSD_enable, 1'b1);
    expect_read("RstReq_sta",         8'h48, 8'hC2);
    io_write(8'h41, 8'd253);                      // warm reset
    wait_reset_done();
    check_bit("warm: MegaSD off", megaSD_enable, 1'b0);
    check_bit("warm: ipl_en again", ipl_en, 1'b1);
    io_write(8'h40, 8'hD4);
    expect_read("warm: lock mask kept", 8'h43, 8'h81);
    expect_read("warm: slot modes kept", 8'h42, {1'b0, dip[6], 3'b011, dip[2:0]});

    // ---- JIS2 enabler: port 4Eh bit 7 (write_n), IPL phase only
    check_bit("JIS2 by default", jis2_en, 1'b1);
    io_write(8'h4E, 8'h80);
    check_bit("JIS2 off by IPL", jis2_en, 1'b0);
    io_write(8'h4E, 8'h00);
    check_bit("JIS2 on by IPL", jis2_en, 1'b1);

    // ---- IPL phase ends only with port A8h
    io_write(8'hA9, 8'h00);
    check_bit("A9 does not end IPL", ipl_en, 1'b1);
    io_write(8'hA8, 8'hF0);
    check_bit("A8 ends IPL", ipl_en, 1'b0);
    io_write(8'h4E, 8'h80);
    check_bit("JIS2 write ignored after IPL", jis2_en, 1'b1);

    // ---- cold reset: lock mask cleared, MegaSD from DIP (now off)
    hard = 1; repeat (2) @(negedge clk); hard = 0;
    wait_reset_done();
    io_write(8'h40, 8'hD4);
    expect_read("cold: lock mask cleared", 8'h43, 8'h00);
    check_bit("cold: MegaSD from DIP", megaSD_enable, 1'b0);

    // ---- ID 008
    io_write(8'h40, 8'h08);
    expect_read("ID 008", 8'h40, 8'hF7);
    expect_read("ID 008 port 43", 8'h43, 8'h00);

    // ---- CPU speed. Cold boot: IPL and logo at 10.7 MHz (custom speed 2 -> 2 memory waits)
    expect_speed("IPL", 1, 2, 3);
    io_write(8'hA8, 8'hF0);
    expect_speed("logo after cold boot", 1, 2, 3);
    repeat (13) tick_10hz();
    expect_speed("logo 3.58 MHz", 0, 0, 0);
    repeat (17) tick_10hz();
    expect_speed("logo 3.58 MHz (1 tick left)", 0, 0, 0);
    tick_10hz();
    expect_speed("selected: DIP turbo off", 0, 0, 0);

    // F11: 3.58 -> 5.37 -> custom turbo -> 3.58; ignored with SHIFT, key repeat ignored
    f11();
    expect_speed("F11 5.37 MHz", 2, 0, 6);
    io_write(8'h40, 8'hD4);
    expect_read("port 48 turbo 5.37", 8'h48, 8'h93);
    f11();
    expect_speed("F11 custom turbo", 1, 2, 3);
    key(8'h78, 1); key(8'h78, 1); key(8'h78, 0);
    expect_speed("F11 repeat = one press", 0, 0, 0);
    key(8'h12, 1); f11(); key(8'h12, 0);
    expect_speed("SHIFT+F11 ignored", 0, 0, 0);
    io_write(8'h41, 8'd41);                       // turbo locked
    f11();
    expect_speed("F11 locked", 0, 0, 0);
    io_write(8'h41, 8'd42);

    // Smart commands: custom speed level 1 (CustomSpeed 8), turbo restore
    io_write(8'h41, 8'd4);
    expect_speed("custom speed 1", 1, 8, 3);
    expect_read("port 47 speed level 1", 8'h47, 8'h49);   // MegaSD_req 0 (DIP8 off)
    io_write(8'h41, 8'd213);
    expect_speed("turbo restore", 0, 0, 0);
    expect_read("port 47 after restore", 8'h47, 8'h4F);

    // ID 008 port 41h bit 0 (write_n): 5.37 MHz
    io_write(8'h40, 8'h08);
    io_write(8'h41, 8'h00);
    expect_speed("ID008 5.37 MHz", 2, 0, 6);
    io_write(8'h41, 8'h01);
    expect_speed("ID008 3.58 MHz", 0, 0, 0);

    // extclk3m (cmd 64): F11 only toggles 3.58 <-> 5.37
    io_write(8'h40, 8'hD4);
    io_write(8'h41, 8'd64);
    f11(); expect_speed("extclk3m F11 5.37", 2, 0, 6);
    f11(); expect_speed("extclk3m F11 3.58", 0, 0, 0);
    io_write(8'h41, 8'd63);

    // DIP-SW turbo from the OSD: custom turbo
    dip[0] = 1'b1;
    expect_speed("DIP turbo", 1, 2, 3);
    dip[0] = 1'b0;
    expect_speed("DIP turbo off", 0, 0, 0);

    // Hybrid clock: 5.37 MHz while the MegaSD window stays mapped (tMegaSD on)
    // (hstart is 0 after reset, set to 7 by the first 2^17 tick with the window unmapped)
    repeat (131072) @(negedge clk);
    mmc_on = 1;
    repeat (6 * 131072) @(negedge clk);
    expect_speed("hybrid: not yet (48 ms)", 0, 0, 0);
    repeat (3 * 131072) @(negedge clk);
    expect_speed("hybrid: MegaSD mapped", 2, 0, 6);
    mmc_on = 0;
    repeat (5 * 262144) @(negedge clk);
    expect_speed("hybrid: timeout running", 2, 0, 6);
    repeat (4 * 262144) @(negedge clk);
    expect_speed("hybrid: timeout over", 0, 0, 0);
    io_write(8'h41, 8'd11);                       // turbo MegaSD off
    mmc_on = 1;
    repeat (9 * 131072) @(negedge clk);
    expect_speed("hybrid off by cmd 11", 0, 0, 0);
    mmc_on = 0;
    io_write(8'h41, 8'd12);

    // Warm reset: no logo limiter (LastRst_sta = 1), unless requested by cmd 250
    io_write(8'h41, 8'd253);
    wait_reset_done();
    expect_speed("warm: IPL", 1, 2, 3);
    io_write(8'hA8, 8'hF0);
    expect_speed("warm: no logo", 0, 0, 0);
    io_write(8'h40, 8'hD4);
    expect_read("warm: LastRst_sta", 8'h48, 8'hA2);
    io_write(8'h41, 8'd250);
    io_write(8'h41, 8'd253);
    wait_reset_done();
    io_write(8'hA8, 8'hF0);
    expect_speed("warm + cmd 250: logo", 1, 2, 3);

    // ---- not present: ports silent, no IPL
    io_device[0].enable = 1'b0;
    hard = 1; repeat (2) @(negedge clk); hard = 0;
    wait_reset_done();
    io_write(8'h40, 8'hD4);
    expect_read("absent device", 8'h40, 8'hFF);
    check_bit("absent: no IPL", ipl_en, 1'b0);
    check_bit("absent: JIS2 allowed", jis2_en, 1'b1);
    check_bit("absent: no speed override", cpu_speed.en, 1'b0);
    if (cpu_speed !== '0) begin errors++; $display("FAIL absent: cpu_speed %h", cpu_speed); end

    if (errors == 0) $display("PASS ocm_tb");
    else             $display("FAILED ocm_tb: %0d errors", errors);
    $finish;
end

endmodule
