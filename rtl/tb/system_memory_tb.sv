// system_memory test: CPU (ch1), flash (ch2, real flash.sv) and NVRAM backup (ch3) must see
// the same byte at the same system address, both in the BRAM area (< 2^18) and in SDRAM.
// SDRAM is a behavioural model at channel level (physical address = what sdram.sv gets).
// The OPL4 sample memory port (wave bus, SDRAM ch4) reads words and writes bytes of the same map.
// +define+OLD: wiring before the fix (flash / backup straight to SDRAM ch2 / ch3).
// Run: wsl.exe -- bash rtl/tb/run_system_memory.sh
module system_memory_tb;

logic clk = 0;
always #1 clk = ~clk;

memory_bus_if bus_msx(), bus_upload(), bus_flash(), bus_backup();
memory_bus_if sd_ch1(), sd_ch2(), sd_ch3();
logic upload = 0;

`ifdef OLD
system_memory #(.BRAM_WIDTH(18)) dut (.clk, .memory_bus_msx(bus_msx), .memory_bus_upload(bus_upload),
    .memory_bus_sdram_ch1(sd_ch1), .memory_bus_sdram_ch2(sd_ch2), .memory_bus_sdram_ch3(sd_ch3), .upload);
`else
`ifdef OLD_FLASH
system_memory #(.BRAM_WIDTH(18)) dut (.clk, .memory_bus_msx(bus_msx), .memory_bus_upload(bus_upload),
    .memory_bus_flash(bus_flash), .memory_bus_backup(bus_backup),
    .memory_bus_sdram_ch1(sd_ch1), .memory_bus_sdram_ch2(sd_ch2), .memory_bus_sdram_ch3(sd_ch3), .upload);
`else
`define WAVE
wave_bus_if wave(), sd_ch4();
system_memory #(.BRAM_WIDTH(18)) dut (.clk, .memory_bus_msx(bus_msx), .memory_bus_upload(bus_upload),
    .memory_bus_flash(bus_flash), .memory_bus_backup(bus_backup),
    .memory_bus_sdram_ch1(sd_ch1), .memory_bus_sdram_ch2(sd_ch2), .memory_bus_sdram_ch3(sd_ch3),
    .wave_bus(wave), .wave_bus_sdram_ch4(sd_ch4), .upload);
`endif
`endif

// ---------------- flash.sv (real) ----------------
flash_bus_if flash_bus();
wire  [26:0] flash_addr;
wire   [7:0] flash_dout;
wire         flash_req, flash_ready, flash_done, flash_erasing;
`ifdef OLD_FLASH                        // flash.sv / package.sv before the area bounds and the reset
flash u_flash (.clk, .clk_sdram(clk), .flash_bus(flash_bus), .sdram_ready(flash_ready), .sdram_done(flash_done),
               .sdram_addr(flash_addr), .sdram_din(flash_dout), .sdram_req(flash_req), .debug_erase(flash_erasing));
`else
flash u_flash (.clk, .clk_sdram(clk), .reset(1'b0), .flash_bus(flash_bus), .sdram_ready(flash_ready), .sdram_done(flash_done),
               .sdram_addr(flash_addr), .sdram_din(flash_dout), .sdram_req(flash_req), .debug_erase(flash_erasing));
assign flash_bus.area_lo   = 23'h10000;         // MFRSD subslot 1: 4 MB from 10000h
assign flash_bus.area_size = 24'h3FC000;
assign flash_bus.chip      = 1'b0;
assign flash_bus.id        = 1'b0;
`endif

// backup channel driver signals (nvram_backup style: 1-clk req pulse)
logic [26:0] bk_addr = 0;
logic  [7:0] bk_din = 0;
logic        bk_req = 0, bk_rnw = 1;
wire   [7:0] bk_dout;
wire         bk_ready;

`ifdef OLD
// before the fix: flash / backup addressed SDRAM directly with system addresses
assign sd_ch2.addr = flash_addr;  assign sd_ch2.data = flash_dout; assign sd_ch2.rnw = 1'b0;
assign sd_ch2.ram_cs = flash_req; assign flash_ready = sd_ch2.sdram_ready; assign flash_done = sd_ch2.sdram_done;
assign sd_ch3.addr = bk_addr;     assign sd_ch3.data = bk_din;     assign sd_ch3.rnw = bk_rnw;
assign sd_ch3.ram_cs = bk_req;    assign bk_dout = sd_ch3.q;       assign bk_ready = sd_ch3.sdram_ready;
`else
assign bus_flash.addr = flash_addr; assign bus_flash.data = flash_dout; assign bus_flash.rnw = 1'b0;
assign bus_flash.ram_cs = flash_req; assign bus_flash.sram_cs = 1'b0;
assign flash_ready = bus_flash.sdram_ready; assign flash_done = bus_flash.sdram_done;
assign bus_backup.addr = bk_addr; assign bus_backup.data = bk_din; assign bus_backup.rnw = bk_rnw;
assign bus_backup.ram_cs = bk_req; assign bus_backup.sram_cs = 1'b0;
assign bk_dout = bus_backup.q; assign bk_ready = bus_backup.sdram_ready;
`endif

// ---------------- SDRAM model (physical addresses) ----------------
logic [7:0] sdram [int];
function automatic logic [7:0] sd_rd(input int a); return sdram.exists(a) ? sdram[a] : 8'h00; endfunction

// ch1: write on cs rising edge, read data registered
logic ch1_q = 0; logic [7:0] ch1_data = 0;
always @(posedge clk) begin
    ch1_q <= sd_ch1.ram_cs;
    if (sd_ch1.ram_cs && !ch1_q && !sd_ch1.rnw) sdram[int'(sd_ch1.addr)] = sd_ch1.data;
    ch1_data <= sd_rd(int'(sd_ch1.addr));
end
assign sd_ch1.q = ch1_data; assign sd_ch1.sdram_ready = 1'b1; assign sd_ch1.sdram_done = 1'b0;

// ch2 / ch3: request on rising edge, done after 3 clk; ready low while busy, done (writes) until req drops
typedef struct { logic q; int busy; logic done; logic ready; logic [7:0] data; } chan_t;
chan_t c2 = '{0, 0, 0, 1, 0}, c3 = '{0, 0, 0, 1, 0};
always @(posedge clk) begin
    c2.q <= sd_ch2.ram_cs;
    if (!sd_ch2.ram_cs) c2.done <= 0;
    if (sd_ch2.ram_cs && !c2.q) begin c2.busy <= 3; c2.ready <= 0; end
    else if (c2.busy == 1) begin
        if (!sd_ch2.rnw) begin sdram[int'(sd_ch2.addr)] = sd_ch2.data; c2.done <= 1; end
        c2.data <= sd_rd(int'(sd_ch2.addr)); c2.ready <= 1; c2.busy <= 0;
    end else if (c2.busy > 1) c2.busy <= c2.busy - 1;

    c3.q <= sd_ch3.ram_cs;
    if (sd_ch3.ram_cs && !c3.q) begin c3.busy <= 3; c3.ready <= 0; end
    else if (c3.busy == 1) begin
        if (!sd_ch3.rnw) sdram[int'(sd_ch3.addr)] = sd_ch3.data;
        c3.data <= sd_rd(int'(sd_ch3.addr)); c3.ready <= 1; c3.busy <= 0;
    end else if (c3.busy > 1) c3.busy <= c3.busy - 1;
end
assign sd_ch2.q = c2.data; assign sd_ch2.sdram_ready = c2.ready; assign sd_ch2.sdram_done = c2.done;
assign sd_ch3.q = c3.data; assign sd_ch3.sdram_ready = c3.ready; assign sd_ch3.sdram_done = 1'b0;

`ifdef WAVE
// ch4: done after 2 clk, held until the request falls; word read / byte write
logic        c4_done = 0;
int          c4_cnt = 0;
logic [15:0] c4_data = 0;
always @(posedge clk) begin
    if (!sd_ch4.req) begin c4_done <= 0; c4_cnt <= 0; end
    else if (!c4_done) begin
        if (c4_cnt == 2) begin
            if (sd_ch4.we) sdram[int'(sd_ch4.addr)] = sd_ch4.wdata;
            c4_data <= {sd_rd(int'(sd_ch4.addr) | 1), sd_rd(int'(sd_ch4.addr) & ~1)};
            c4_done <= 1;
        end else c4_cnt <= c4_cnt + 1;
    end
end
assign sd_ch4.ack = c4_done; assign sd_ch4.rdata = c4_data;

logic        wv_req = 0, wv_we = 0;
logic [26:0] wv_addr = 0;
logic  [7:0] wv_wdata = 0;
assign wave.req = wv_req; assign wave.we = wv_we; assign wave.addr = wv_addr; assign wave.wdata = wv_wdata;

task automatic wave_acc(input int a, input logic we, input logic [7:0] d, output logic [15:0] q);
    int t;
    wv_addr = 27'(a); wv_we = we; wv_wdata = d; wv_req = 1; t = 0;
    @(posedge clk);
    while (!wave.ack && t < 100) begin @(posedge clk); t++; end
    q = wave.rdata;
    #0.1 wv_req = 0;
    @(posedge clk); #0.1;
endtask
`endif

// ---------------- helpers ----------------
int errors = 0;
task automatic cyc(input int n = 1); repeat (n) @(posedge clk); #0.1; endtask

assign bus_upload.sram_cs = 1'b0;
assign bus_msx.sram_cs    = 1'b0;

task automatic up_write(input int a, input logic [7:0] v);
    upload = 1; bus_upload.addr = 27'(a); bus_upload.data = v; bus_upload.rnw = 0; bus_upload.ram_cs = 1;
    cyc(); bus_upload.ram_cs = 0; cyc(); upload = 0;
endtask

task automatic cpu_read(input int a, output logic [7:0] v);
    bus_msx.addr = 27'(a); bus_msx.rnw = 1; bus_msx.ram_cs = 1; bus_msx.data = 0;
    cyc(3); v = bus_msx.q; bus_msx.ram_cs = 0; cyc();
endtask

task automatic expect_cpu(input string tag, input int a, input logic [7:0] e);
    logic [7:0] v;
    cpu_read(a, v);
    if (v !== e) begin errors++; if (errors < 20) $display("FAIL %s: addr %07h got=%02h exp=%02h", tag, a, v, e); end
endtask

// flash write as MFRSD drives flash_bus: addr = 0x10000 + offset, base_addr = 0x10000 - base_ram
task automatic flash_wr(input int base, input int off, input logic [7:0] v);
    flash_bus.base_addr = 27'h10000 - 27'(base);
    flash_bus.addr = 23'(32'h10000 + off); flash_bus.data_to_flash = v; flash_bus.ce = 1; flash_bus.we = 0;
    cyc(); flash_bus.we = 1; cyc(2); flash_bus.we = 0; flash_bus.ce = 0; cyc(2);
endtask

task automatic flash_program(input int base, input int off, input logic [7:0] v);
    flash_wr(base, 32'hAAA, 8'hAA); flash_wr(base, 32'h555, 8'h55); flash_wr(base, 32'hAAA, 8'hA0);
    flash_wr(base, off, v);
    wait (!flash_req); cyc(4);
endtask

task automatic flash_erase_block0(input int base);
    flash_wr(base, 32'hAAA, 8'hAA); flash_wr(base, 32'h555, 8'h55); flash_wr(base, 32'hAAA, 8'h80);
    flash_wr(base, 32'hAAA, 8'hAA); flash_wr(base, 32'h555, 8'h55); flash_wr(base, 32'h0000, 8'h30);
    wait (flash_erasing); wait (!flash_erasing); cyc(4);
endtask

task automatic bk_write(input int a, input logic [7:0] v);
    wait (bk_ready); @(posedge clk); #0.1;
    bk_addr = 27'(a); bk_din = v; bk_rnw = 0; bk_req = 1; cyc(); bk_req = 0; cyc(2);
    wait (bk_ready); cyc();
endtask

task automatic bk_read(input int a, output logic [7:0] v);
    wait (bk_ready); @(posedge clk); #0.1;
    bk_addr = 27'(a); bk_rnw = 1; bk_req = 1; cyc(); bk_req = 0; cyc(2);
    wait (bk_ready); cyc(); v = bk_dout; bk_rnw = 1;
endtask

function automatic logic [7:0] pat(input int a); return 8'(a ^ (a >> 8) ^ (a >> 16) ^ 8'h3C); endfunction

int bases[3] = '{32'h0020000, 32'h0100000, 32'h0900000};   // BRAM, SDRAM, SDRAM above 8 MB

initial begin
    bus_msx.ram_cs = 0; bus_upload.ram_cs = 0; flash_bus.ce = 0; flash_bus.we = 0;
    flash_bus.addr = '0; flash_bus.base_addr = '0; flash_bus.data_to_flash = '0;
    cyc(5);

    foreach (bases[i]) begin
        int b; b = bases[i];
        // preload block and the location 256 KB above (old bug target) through upload
        for (int k = 0; k < 3; k++) begin
            int o; o = (k == 0) ? 32'h0100 : (k == 1) ? 32'h1234 : 32'h0000;
            up_write(b + o, pat(b + o));
            up_write(b + o + 32'h40000, pat(b + o + 32'h40000));
        end
        expect_cpu("preload", b + 32'h0100, pat(b + 32'h0100));

        flash_program(b, 32'h0100, 8'hA5 ^ 8'(i));
        flash_program(b, 32'h1234, 8'h5A ^ 8'(i));
        expect_cpu($sformatf("flash prog base %07h", b), b + 32'h0100, 8'hA5 ^ 8'(i));
        expect_cpu($sformatf("flash prog base %07h", b), b + 32'h1234, 8'h5A ^ 8'(i));
        expect_cpu($sformatf("flash victim base %07h", b), b + 32'h0100 + 32'h40000, pat(b + 32'h0100 + 32'h40000));
    end

    // sector erase of block 0 (64 KB) for the SDRAM base
    flash_erase_block0(bases[1]);
    expect_cpu("flash erase", bases[1] + 32'h0000, 8'hFF);
    expect_cpu("flash erase", bases[1] + 32'h1234, 8'hFF);
    expect_cpu("flash erase", bases[1] + 32'hFFFF, 8'hFF);

    // NVRAM backup channel: write via ch3, read via CPU; read back via ch3
    foreach (bases[i]) begin
        logic [7:0] v;
        int a; a = bases[i] + 32'h2000;
        bk_write(a, 8'hC3 ^ 8'(i));
        expect_cpu($sformatf("backup write %07h", a), a, 8'hC3 ^ 8'(i));
        up_write(a + 1, 8'h69 ^ 8'(i));
        bk_read(a + 1, v);
        if (v !== (8'h69 ^ 8'(i))) begin errors++; $display("FAIL backup read %07h got=%02h exp=%02h", a + 1, v, 8'h69 ^ 8'(i)); end
    end

`ifdef WAVE
    // wave bus: words written through the CPU channel, bytes written by the wave bus, with the
    // backup channel busy on the same BRAM port in between
    foreach (bases[i]) begin
        logic [15:0] q;
        logic  [7:0] v;
        int a; a = bases[i] + 32'h3000;
        for (int k = 0; k < 6; k++) up_write(a + k, pat(a + k));
        for (int k = 0; k < 6; k++) begin
            wave_acc(a + k, 1'b0, 8'h00, q);
            if (q !== {pat((a + k) | 1), pat((a + k) & ~1)}) begin
                errors++; $display("FAIL wave read %07h got=%04h exp=%04h", a + k, q, {pat((a + k) | 1), pat((a + k) & ~1)});
            end
        end
        wave_acc(a + 3, 1'b1, 8'hE7, q);
        expect_cpu($sformatf("wave write %07h", a + 3), a + 3, 8'hE7);
        expect_cpu($sformatf("wave write neighbour %07h", a + 2), a + 2, pat(a + 2));
        fork
            for (int k = 0; k < 8; k++) bk_write(a + 32'h100 + k, 8'h80 + 8'(k));
            for (int k = 0; k < 8; k++) begin
                wave_acc(a + (k & 4), 1'b0, 8'h00, q);
                if (q !== {pat((a + (k & 4)) | 1), pat(a + (k & 4))}) begin
                    errors++; $display("FAIL wave read beside the backup %07h got=%04h", a + (k & 4), q);
                end
            end
        join
        for (int k = 0; k < 8; k++) expect_cpu("backup beside the wave bus", a + 32'h100 + k, 8'h80 + 8'(k));
    end
`endif

    if (errors == 0) $display("PASS system_memory_tb");
    else             $display("FAILED system_memory_tb: %0d errors", errors);
    $finish;
end

endmodule
