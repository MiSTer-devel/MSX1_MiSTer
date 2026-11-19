// V9938 / V9958 (ESE VDP) command duration against openMSX: the measurement of
// tools/vdptest/cmdbench.asm (14 configurations of R#0 / R#1 / R#8 / R#9, eight commands),
// done through the CPU ports like the ROM. Each command is started when VR goes 0 and CE is
// polled every 56 T (336 clocks), as the ROM's loop does; the result is the iteration count.
//
//   wsl.exe -- bash rtl/peripheral/VIDEO/VDP/tb/run_vdp_cmd.sh
//   +ref=<file>  reference (default cmdbench_openmsx.txt), +tol=<percent> (default 2)
//   +only=<config * 10 + command>, +lag: arbiter latency per line (debugging)

`timescale 1ns/1ps

module vdp_cmd_tb;
    logic clk = 0;
    always #23 clk = ~clk;                      // 21.477 MHz

    logic        reset = 1;
    logic        req = 0, wrt = 0;
    logic [15:0] adr = 0;
    logic  [7:0] dbo = 0;
    wire   [7:0] dbi;
    wire         we_n, dl_clk;
    wire  [16:0] vaddr;
    wire   [7:0] vdata;
    logic  [7:0] q_lo, q_hi;

    VDP VDP_i (
        .CLK21M(clk), .RESET(reset), .REQ(req), .ACK(), .WRT(wrt), .ADR(adr), .DBI(dbi), .DBO(dbo),
        .INT_N(), .PRAMOE_N(), .PRAMWE_N(we_n), .PRAMADR(vaddr), .PRAMDBI({q_hi, q_lo}),
        .PRAMDBO(vdata), .VDPSPEEDMODE(1'b0), .CENTERYJK_R25_N(1'b0),
        .PVIDEOR(), .PVIDEOG(), .PVIDEOB(), .PVIDEODE(), .HBLANK(), .VBLANK(),
        .PVIDEOHS_N(), .PVIDEOVS_N(), .PVIDEOCS_N(), .PVIDEODHCLK(), .PVIDEODLCLK(dl_clk),
        .NTSC_PAL_TYPE(1'b1), .FORCED_V_MODE(1'b0), .BORDER(1'b0), .VDP_ID(5'b00010), .OFFSET_Y(7'd0)
    );

    // VRAM as in dev_v99 / msx_system: two 64 kB banks, registered read
    logic [7:0] mem_lo [65536], mem_hi [65536];
    initial foreach (mem_lo[i]) begin mem_lo[i] = 0; mem_hi[i] = 0; end
    always_ff @(posedge clk) begin
        if (~we_n & dl_clk & ~vaddr[16]) mem_lo[vaddr[15:0]] <= vdata;
        if (~we_n & dl_clk &  vaddr[16]) mem_hi[vaddr[15:0]] <= vdata;
        q_lo <= mem_lo[vaddr[15:0]];
        q_hi <= mem_hi[vaddr[15:0]];
    end

    task automatic port_wr(input logic [1:0] p, input logic [7:0] d);
        @(posedge clk); adr <= {14'h0026, p}; dbo <= d; wrt <= 1; req <= 1;
        @(posedge clk); req <= 0;
        repeat (40) @(posedge clk);
    endtask

    task automatic set_reg(input int n, input logic [7:0] v);
        port_wr(2'd1, v); port_wr(2'd1, 8'h80 | 8'(n));
    endtask

    logic [7:0] st;
    task automatic status();                    // 3 clocks
        @(posedge clk); adr <= 16'h0099; wrt <= 0; req <= 1;
        @(posedge clk); req <= 0;
        @(posedge clk); st = dbi;
    endtask

    // cmdbench.asm CFGTAB and CMDTAB
    localparam int NCFG = 14, NCMD = 8;
    // R#0, R#1, R#8, R#9
    const logic [7:0] CFG [NCFG][4] = '{
        '{8'h06, 8'h40, 8'h08, 8'h80}, '{8'h06, 8'h40, 8'h08, 8'h00}, '{8'h06, 8'h40, 8'h0A, 8'h80},
        '{8'h06, 8'h40, 8'h0A, 8'h00}, '{8'h06, 8'h00, 8'h08, 8'h80},
        '{8'h06, 8'h40, 8'h08, 8'h82}, '{8'h06, 8'h40, 8'h08, 8'h02}, '{8'h06, 8'h40, 8'h0A, 8'h82},
        '{8'h06, 8'h40, 8'h0A, 8'h02}, '{8'h06, 8'h00, 8'h08, 8'h82},
        '{8'h08, 8'h40, 8'h08, 8'h80}, '{8'h0A, 8'h40, 8'h08, 8'h80}, '{8'h0E, 8'h40, 8'h08, 8'h80},
        '{8'h0E, 8'h40, 8'h0A, 8'h80}};
    const string CFGNAME [NCFG] = '{"NTSC 212 spr on", "NTSC 192 spr on", "NTSC 212 spr off",
        "NTSC 192 spr off", "NTSC display off", "PAL  212 spr on", "PAL  192 spr on",
        "PAL  212 spr off", "PAL  192 spr off", "PAL  display off",
        "SCR6 212 spr on", "SCR7 212 spr on", "SCR8 212 spr on", "SCR8 212 spr off"};
    // SX, SY, DX, DY, NX, NY, CLR, ARG, CMD
    const int CMD [NCMD][9] = '{
        '{0,   0, 0, 0, 256, 106, 'h44, 0, 'hC0},     // HMMV
        '{0,   0, 0, 0, 256, 106, 'h05, 0, 'h80},     // LMMV
        '{0,  50, 0, 0,   0,   0, 'h05, 2, 'h60},     // SRCH
        '{0, 256, 0, 0, 256, 106, 0,    0, 'hE0},     // YMMM
        '{0, 256, 0, 0, 256, 106, 0,    0, 'hD0},     // HMMM
        '{0, 256, 0, 0, 256, 106, 0,    0, 'h90},     // LMMM
        '{0,   0, 0, 0, 255, 100, 'h0F, 0, 'h70},     // LINE 255 x 100
        '{0,   0, 0, 0, 255, 255, 'h0F, 0, 'h70}};    // LINE 255 x 255

    task automatic run_cmd(input int c, output int iter);
        int n;
        set_reg(17, 8'd32);
        for (int i = 0; i < 6; i++) begin
            port_wr(2'd3, 8'(CMD[c][i])); port_wr(2'd3, 8'(CMD[c][i] >> 8));
        end
        port_wr(2'd3, 8'(CMD[c][6])); port_wr(2'd3, 8'(CMD[c][7]));
        do begin status(); repeat (60) @(posedge clk); end while (!st[6]);     // VR = 1
        do begin status(); repeat (60) @(posedge clk); end while (st[6]);      // VR = 0
        port_wr(2'd3, 8'(CMD[c][8]));
        n = 0;
        forever begin
            status();
            if (!st[0] || n >= 65280) break;
            n++;
            repeat (336 - 3) @(posedge clk);
        end
        iter = n;
    endtask

    // +lag: clocks from the access token to the real access, per line of the frame
    int lag_sum [1024], lag_n [1024], lag_max [1024];
    longint cyc = 0, fires [$];
    bit lag_on = 0;
    wire [10:0] vcnt = VDP_i.V_CNT;
`ifndef OLD_CMDT                         // sources before vdp_access_slots
    always @(posedge clk) begin
        cyc++;
        if (!lag_on) fires.delete();
        else begin
            if (VDP_i.U_VDP_ACCESS_SLOTS.fire) fires.push_back(cyc);
            if (VDP_i.VDP_CMD_XFER && fires.size() > 0) begin
                int lag = int'(cyc - fires.pop_front());
                lag_sum[vcnt[10:1]] += lag; lag_n[vcnt[10:1]]++;
                if (lag > lag_max[vcnt[10:1]]) lag_max[vcnt[10:1]] = lag;
            end
        end
    end
`endif

    int ref_v [NCFG][NCMD];
    int got [NCFG][NCMD];

    initial begin
        string rf, line, s;
        int fd, k, tol, errors, n;
        int a [NCMD];
        real d;
        bit bad;
        if (!$value$plusargs("ref=%s", rf)) rf = "cmdbench_openmsx.txt";
        if (!$value$plusargs("tol=%d", tol)) tol = 2;
        fd = $fopen(rf, "r");
        if (fd == 0) begin $display("FAIL cannot read %s", rf); $finish; end
        k = 0;
        while (k < NCFG && $fgets(line, fd)) begin
            if (line.len() < 2 || line[0] == "#") continue;
            n = $sscanf(line, "%d %d %d %d %d %d %d %d", a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]);
            for (int i = 0; i < NCMD; i++) ref_v[k][i] = a[i];
            k++;
        end
        $fclose(fd);

        repeat (20) @(posedge clk);
        reset = 0;
        repeat (20) @(posedge clk);
        // SCREEN 5 as cmdbench.asm SCR5; SAT 7600h with Y = 216
        set_reg(0, 8'h06); set_reg(1, 8'h00); set_reg(2, 8'h1F); set_reg(5, 8'hEF); set_reg(11, 8'h00);
        set_reg(6, 8'h0F); set_reg(7, 8'h04); set_reg(8, 8'h08); set_reg(9, 8'h00); set_reg(23, 8'h00);
        set_reg(15, 8'h02);

        errors = 0;
        $display("                     HMMV          LMMV          SRCH          YMMM          HMMM          LMMM         LN100         LN255");
        for (int c = 0; c < NCFG; c++) begin
            set_reg(0, CFG[c][0]); set_reg(1, CFG[c][1]); set_reg(8, CFG[c][2]); set_reg(9, CFG[c][3]);
            // SAT Y = 216 (no sprite) at 7600h in the address layout of the mode
            set_reg(14, 8'h01); port_wr(2'd1, 8'h00); port_wr(2'd1, 8'h76); port_wr(2'd0, 8'hD8);
            s = $sformatf("%-17s", CFGNAME[c]);
            for (int m = 0; m < NCMD; m++) begin
                if ($value$plusargs("only=%d", k) && k != c * 10 + m) begin got[c][m] = ref_v[c][m]; continue; end
                lag_on = $test$plusargs("lag");
                run_cmd(m, got[c][m]);
                if (lag_on) begin
                    lag_on = 0;
                    for (int l = 0; l < 1024; l++) if (lag_n[l] > 0)
                        $display("  V_CNT/2 %4d: %5d accesses, lag avg %0d max %0d", l, lag_n[l], lag_sum[l] / lag_n[l], lag_max[l]);
                end
                d = 100.0 * (got[c][m] - ref_v[c][m]) / ref_v[c][m];
                // +-2 iterations of polling are always allowed (short commands)
                bad = (d > tol || d < -tol) && (got[c][m] - ref_v[c][m] > 2 || ref_v[c][m] - got[c][m] > 2);
                if (bad) errors++;
                s = {s, $sformatf(" %5d %6.1f%s", got[c][m], d, bad ? "!" : " ")};
            end
            $display("%s", s);
        end
        $display("(iterations of 56 T and %% against %s; ! = outside +-%0d %%)", rf, tol);
        begin   // VRAM after all commands: must not depend on the timing
            int unsigned h = 32'h811C9DC5;
            for (int i = 0; i < 65536; i++) h = (h ^ mem_lo[i]) * 32'h01000193;
            for (int i = 0; i < 65536; i++) h = (h ^ mem_hi[i]) * 32'h01000193;
            $display("VRAM hash %08h", h);
        end
        $display("%s vdp_cmd_tb (%0d of %0d outside)", errors ? "FAIL" : "PASS", errors, NCFG * NCMD);
        $finish;
    end
endmodule
