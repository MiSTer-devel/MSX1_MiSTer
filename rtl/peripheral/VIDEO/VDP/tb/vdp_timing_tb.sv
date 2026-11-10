// V9938 / V9958 (ESE VDP) vertical timing against openMSX (VDP.cc): VBLANK interrupt,
// S#2 VR, line interrupt and S#1 FH, measured from the first output line of the picture.
//
// openMSX: display start = left border of line lineZero; VSCAN (F, VBLANK interrupt) at
// display start + 192/212 lines; VR = 1 before display start - 1 line and from VSCAN on;
// HSCAN (FH with IE1) at the right border of display line R#19 - R#23, i.e. 56 + 1024 clocks
// after the left border; with IE1 off FH reads 1 from that point to the next left border
// and nothing is latched. F and FH are cleared only by reading S#0 / S#1.
//
// The tb works like the CPU: registers, palette and VRAM through ports 98h-9Ah, status
// through port 99h. Positions are reported as (line, clock) relative to the left border of
// display line 0 in output time: the left border starts 56 clocks before the first picture
// pixel on the video output (openMSX tick 202, picture from 258), the right border right
// after the last one (1024 clocks later). The picture is Graphic 1, every cell white on a
// blue border; its position is measured first and is the reference for everything else.
//
//   wsl.exe -- bash rtl/peripheral/VIDEO/VDP/tb/run_vdp_timing.sh

`timescale 1ns/1ps

module vdp_timing_tb;
    import VDP_PACKAGE::*;

    logic clk = 0;
    always #23 clk = ~clk;                      // 21.477 MHz

    logic        reset = 1;
    logic        req = 0, wrt = 0;
    logic [15:0] adr = 0;
    logic  [7:0] dbo = 0;
    wire   [7:0] dbi;
    wire         int_n, we_n, dl_clk, dh_clk, de, hblank, vblank, hs_n, vs_n;
    wire  [16:0] vaddr;
    wire   [7:0] vdata;
    logic  [7:0] q_lo, q_hi;
    wire   [5:0] r, g, b;

    VDP VDP_i (
        .CLK21M(clk), .RESET(reset), .REQ(req), .ACK(), .WRT(wrt), .ADR(adr), .DBI(dbi), .DBO(dbo),
        .INT_N(int_n), .PRAMOE_N(), .PRAMWE_N(we_n), .PRAMADR(vaddr), .PRAMDBI({q_hi, q_lo}),
        .PRAMDBO(vdata), .VDPSPEEDMODE(1'b0), .CENTERYJK_R25_N(1'b0),
        .PVIDEOR(r), .PVIDEOG(g), .PVIDEOB(b), .PVIDEODE(de), .HBLANK(hblank), .VBLANK(vblank),
        .PVIDEOHS_N(hs_n), .PVIDEOVS_N(vs_n), .PVIDEOCS_N(), .PVIDEODHCLK(dh_clk), .PVIDEODLCLK(dl_clk),
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

    // ------------------------------------------------------------- CPU port access
    task automatic port_wr(input logic [1:0] p, input logic [7:0] d);
        @(posedge clk); adr <= {14'h0026, p}; dbo <= d; wrt <= 1; req <= 1;
        @(posedge clk); req <= 0;
        repeat (40) @(posedge clk);             // well below a Z80 OUT
    endtask

    task automatic set_reg(input int n, input logic [7:0] v);
        port_wr(2'd1, v); port_wr(2'd1, 8'h80 | 8'(n));
    endtask

    logic [7:0] st;
    task automatic status(input int n);
        @(posedge clk); adr <= 16'h0099; wrt <= 0; req <= 1;
        @(posedge clk); req <= 0;
        @(posedge clk); st = dbi;
    endtask

    // ------------------------------------------------------------- position
    wire [10:0] h_cnt = VDP_i.H_CNT;
    int line = 0;                               // left border to left border
    int lb = LEFT_BORDER;                       // H_CNT at the left border start (output time)
    always @(posedge clk) if (h_cnt == 11'(lb)) line <= line + 1;
    function automatic int hpos();               // clocks since the left border
        return (int'(h_cnt) - lb + CLOCKS_PER_LINE) % CLOCKS_PER_LINE;
    endfunction

    // first output line with picture (white) pixels after a line without
    int  disp0 = -1, pic_line = -1, pic_first = -1, pic_last = -1, px_first, px_last;
    bit  pic_seen, pic_prev;
    always @(posedge clk) begin
        if (h_cnt == 11'(lb)) begin
            if (pic_seen && !pic_prev) pic_line = line;
            if (pic_seen) begin pic_first = px_first; pic_last = px_last; end
            pic_prev = pic_seen; pic_seen = 0;
        end
        if (r > 6'd30 && g > 6'd30) begin
            if (!pic_seen) px_first = hpos();
            px_last = hpos();
            pic_seen = 1;
        end
    end

    int errors = 0;
    task automatic expect_pos(input string what, input int l, input int c, input int el, input int ec, input int tol);
        bit ok = (l == el) && (c >= ec - tol) && (c <= ec + tol);
        $display("  %-44s line %4d clk %4d   expected line %4d clk %4d +-%0d  %s",
                 what, l, c, el, ec, tol, ok ? "OK" : "FAIL");
        if (!ok) errors++;
    endtask

    task automatic wait_frame_start();          // just after the picture started
        int s = pic_line;
        while (pic_line == s) @(posedge clk);
        disp0 = pic_line;
    endtask

    // ------------------------------------------------------------- scenarios
    task automatic setup(input logic [7:0] r9);
        set_reg(0, 8'h00);                      // Graphic 1
        set_reg(1, 8'h40);                      // display on, no interrupts
        set_reg(2, 8'h06); set_reg(3, 8'h80); set_reg(4, 8'h00);
        set_reg(5, 8'h36); set_reg(6, 8'h07);
        set_reg(7, 8'h04);                      // border colour 4
        set_reg(8, 8'h0A);                      // sprites off, 64 kB
        set_reg(9, r9);
        set_reg(18, 8'h00); set_reg(19, 8'h00); set_reg(23, 8'h00);
        set_reg(16, 8'h04); port_wr(2'd2, 8'h07); port_wr(2'd2, 8'h00);   // 4: blue
        set_reg(16, 8'h0F); port_wr(2'd2, 8'h77); port_wr(2'd2, 8'h07);   // 15: white
        set_reg(14, 8'h00);
        port_wr(2'd1, 8'h00); port_wr(2'd1, 8'h40);                       // VRAM 0000
        repeat (8) port_wr(2'd0, 8'hFF);                                  // pattern 0
        port_wr(2'd1, 8'h00); port_wr(2'd1, 8'h60);                       // VRAM 2000
        port_wr(2'd0, 8'hF4);                                             // colour 0
        set_reg(15, 8'h02);                                               // S#2
        repeat (2) wait_frame_start();
        $display("R#9 %02h: picture on the output at H_CNT %0d .. %0d", r9, (lb + pic_first) % CLOCKS_PER_LINE,
                 (lb + pic_last) % CLOCKS_PER_LINE);
    endtask

    // VBLANK interrupt and VR in one frame (IE0 on)
    task automatic vblank_vr(input string mode, input int lines);
        int il = -1, ic, vf = -1, vfc, vr = -1, vrc;
        bit vr_prev = 1, int_prev = 1;
        $display("%s: VBLANK interrupt, VR", mode);
        set_reg(1, 8'h60);                      // IE0
        wait_frame_start();
        set_reg(15, 8'h00); status(0); set_reg(15, 8'h02);   // clear F of the previous frame
        int_prev = int_n;
        // VR falls before the next picture start, so track one whole frame from here
        while (il < 0 || vr < 0 || vf < 0 || line < disp0 + lines + 4) begin
            status(2);
            if (!vr_prev && st[6] && vr < 0 && line > disp0) begin vr = line; vrc = hpos(); end
            if (vr_prev && !st[6] && vf < 0 && line > disp0 + lines) begin vf = line; vfc = hpos(); end
            vr_prev = st[6];
            if (int_prev && !int_n && il < 0) begin il = line; ic = hpos(); end
            int_prev = int_n;
            if (line > disp0 + 400) break;
        end
        expect_pos("VBLANK interrupt", il - disp0, ic, lines, 0, 8);
        expect_pos("VR = 1 (end of display)", vr - disp0, vrc, lines, 0, 16);
        // the next frame's display line 0 is one frame later: report against the next picture
        wait_frame_start();
        expect_pos("VR = 0 (one line before display start)", vf - disp0, vfc, -1, 0, 16);
        set_reg(1, 8'h40);
        status(0);
    endtask

    // line interrupt (IE1): position, and FH not cleared at VBLANK
    task automatic line_int(input string mode, input int r19, input int lines);
        int il = -1, ic;
        bit int_prev = 1, held;
        $display("%s: line interrupt R#19 = %0d", mode, r19);
        wait_frame_start();                     // display line 1: the match is ahead
        set_reg(19, 8'(r19));
        set_reg(15, 8'h01); status(1);          // clear FH
        set_reg(0, 8'h10);                      // IE1
        int_prev = int_n;
        while (il < 0 && line < disp0 + 400) begin
            @(posedge clk);
            if (int_prev && !int_n) begin il = line; ic = hpos(); end
            int_prev = int_n;
        end
        expect_pos("line interrupt", il - disp0, ic, r19, 1080, 8);
        // FH must survive the end of the display until S#1 is read (also past the old
        // blanking point, up to 30 lines later)
        while (line < disp0 + lines + 30) @(posedge clk);
        held = !int_n;
        $display("  %-44s %s", "INT still low after VBLANK (FH not cleared)", held ? "OK" : "FAIL");
        if (!held) errors++;
        status(1);
        set_reg(0, 8'h00);
        set_reg(15, 8'h02);
    endtask

    // IE1 off: nothing latched, S#1 FH reads the R#19 line window
    task automatic fh_level(input string mode, input int r19);
        int on = -1, onc, off = -1, offc, ones = 0;
        bit prev = 0, irq;
        $display("%s: S#1 FH with IE1 off, R#19 = %0d", mode, r19);
        set_reg(0, 8'h00);
        set_reg(19, 8'(r19));
        set_reg(15, 8'h01); status(1);
        wait_frame_start();
        while (line < disp0 + r19 + 3) begin
            status(1);
            if (st[0]) ones++;
            if (!prev && st[0] && on < 0) begin on = line; onc = hpos(); end
            if (prev && !st[0] && off < 0) begin off = line; offc = hpos(); end
            prev = st[0];
        end
        expect_pos("FH = 1 (right border of the R#19 line)", on - disp0, onc, r19, 1080, 16);
        expect_pos("FH = 0 (next left border)", off - disp0, offc, r19 + 1, 0, 16);
        // a match with IE1 off latches nothing: no S#1 read this time, then IE1 on
        wait_frame_start();
        while (line < disp0 + r19 + 3) @(posedge clk);
        set_reg(0, 8'h10);
        repeat (200) @(posedge clk);
        irq = !int_n;
        $display("  %-44s %s", "IE1 on after the match: no interrupt", irq ? "FAIL" : "OK");
        if (irq) errors++;
        set_reg(0, 8'h00);
        status(1);
        set_reg(15, 8'h02);
    endtask


    // Sprite collision (S#0 C) in SCREEN 5: two overlapping 8x8 sprites at Y; the frame is
    // checked from display line 1 to display line 1 of the next frame, borders included
    task automatic vram_wr(input logic [15:0] a, input logic [7:0] d[$]);
        set_reg(14, 8'(a[15:14]));
        port_wr(2'd1, a[7:0]); port_wr(2'd1, 8'h40 | 8'(a[13:8]));
        foreach (d[i]) port_wr(2'd0, d[i]);
    endtask

    task automatic wait_line1();                // display line 1 starts (no picture needed)
        while (VDP_i.PREDOTCOUNTER_YP == 9'd1) @(posedge clk);
        while (VDP_i.PREDOTCOUNTER_YP != 9'd1) @(posedge clk);
    endtask

    task automatic sprite_coll(input string what, input logic [7:0] r9, input logic [7:0] y, input bit expect_c,
                               input int n = 2);
        logic [7:0] patt[$] = '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF};
        logic [7:0] col[$];
        bit c;
        repeat (32) col.push_back(8'h0F);
        set_reg(0, 8'h06); set_reg(1, 8'h40); set_reg(2, 8'h1F);    // SCREEN 5, 8x8 sprites
        set_reg(5, 8'hEF); set_reg(11, 8'h00); set_reg(6, 8'h0F);   // SAT 7600, patterns 7800
        set_reg(8, 8'h08); set_reg(9, r9); set_reg(23, 8'h00);
        vram_wr(16'h7800, patt);
        vram_wr(16'h7400, col);                                     // colour table of sprites 0, 1
        if (n == 2) vram_wr(16'h7600, '{y, 8'd100, 8'd0, 8'd0, y, 8'd104, 8'd0, 8'd0, 8'hD8});
        else begin                                                  // n sprites at the same place
            logic [7:0] sat[$];
            repeat (n) sat = {sat, y, 8'd100, 8'd0, 8'd0};
            repeat (16 * (32 - 2)) col.push_back(8'h0F);
            vram_wr(16'h7400, col);
            vram_wr(16'h7600, sat);
        end
        set_reg(15, 8'h00);
        wait_line1(); status(0);                                    // clear C
        wait_line1(); status(0);
        c = st[5];
        $display("  %-44s C = %0d, expected %0d  %s", what, c, expect_c, c == expect_c ? "OK" : "FAIL");
        if (c != expect_c) errors++;
        set_reg(15, 8'h02);
    endtask


    // VDP command duration (informational): SCREEN 5, display on, sprites off, as vdptest
    task automatic cmd_time(input string what, input logic [7:0] regs[$]);
        int t0, t;
        set_reg(17, 8'd32);
        foreach (regs[i]) port_wr(2'd3, regs[i]);
        t0 = line;
        set_reg(15, 8'h02);
        do status(2); while (st[0] && line < t0 + 20000);
        t = line - t0;
        $display("  %-24s %5d lines%s", what, t, st[0] ? "  (CE still 1: timeout)" : "");
    endtask

    initial begin
        string only;
        repeat (20) @(posedge clk);
        reset = 0;
        repeat (20) @(posedge clk);

        setup(8'h00);
        $display("picture on the output: H_CNT %0d .. %0d (LEFT_BORDER %0d)", (lb + pic_first) % CLOCKS_PER_LINE,
                 (lb + pic_last) % CLOCKS_PER_LINE, LEFT_BORDER);
        if (pic_last - pic_first != 1023) begin errors++; $display("FAIL picture width %0d", pic_last - pic_first + 1); end
        lb = (lb + pic_first - 56 + CLOCKS_PER_LINE) % CLOCKS_PER_LINE;
        $display("left border start (reference) at H_CNT %0d", lb);
        repeat (2) wait_frame_start();
        vblank_vr("NTSC 192", 192);
        line_int("NTSC 192", 100, 192);
        line_int("NTSC 192", 190, 192);
        fh_level("NTSC 192", 100);

        setup(8'h80);
        vblank_vr("NTSC 212", 212);
        line_int("NTSC 212", 210, 212);

        setup(8'h02);
        vblank_vr("PAL 192", 192);
        setup(8'h82);
        vblank_vr("PAL 212", 212);

        $display("SCREEN 5: sprite collision");
        sprite_coll("Y = 99, 192 lines (visible)", 8'h00, 8'd99, 1);
        sprite_coll("Y = 209, 192 lines (not displayed)", 8'h00, 8'd209, 0);
        sprite_coll("Y = 209, 212 lines (lines 210-211)", 8'h80, 8'd209, 1);
        sprite_coll("32 sprites at Y = 209, 192 lines", 8'h00, 8'd209, 0, 32);
        sprite_coll("32 sprites at Y = 217, 192 lines", 8'h00, 8'd217, 0, 32);
        sprite_coll("32 sprites at Y = 230, 192 lines", 8'h00, 8'd230, 0, 32);
        sprite_coll("Y = 252, top edge (display lines 0-4)", 8'h00, 8'd252, 1);
        sprite_coll("Y = 190, bottom edge (display line 191)", 8'h00, 8'd190, 1);
        // openMSX checks the last top border line and the display lines, shown one line lower:
        // line 192 is still checked (unlike the TMS9929A measured on the Sord M5)
        sprite_coll("Y = 191, 192 lines (line 192 checked)", 8'h00, 8'd191, 1);

        if ($test$plusargs("cmd")) begin
            $display("SCREEN 5: command time (display on, sprites off)");
            set_reg(0, 8'h06); set_reg(1, 8'h40); set_reg(2, 8'h1F); set_reg(8, 8'h0A); set_reg(9, $test$plusargs("pal") ? 8'h02 : 8'h00);
            cmd_time("HMMV 256x212", '{0,0,0,0,0,0,0,0,0,1,212,0,8'h44,0,8'hC0});
            cmd_time("LMMV 256x212", '{0,0,0,0,0,0,0,0,0,1,212,0,8'h05,0,8'h80});
            cmd_time("YMMM 212", '{0,0,0,1,0,0,0,0,0,1,212,0,0,0,8'hE0});
            cmd_time("HMMM 256x212", '{0,0,0,1,0,0,0,0,0,1,212,0,0,0,8'hD0});
            cmd_time("LMMM 256x212", '{0,0,0,1,0,0,0,0,0,1,212,0,0,0,8'h90});
            cmd_time("LINE 255,100", '{0,0,0,0,0,0,0,0,255,0,100,0,8'h0F,0,8'h70});
        end

        $display("%s vdp_timing_tb (%0d errors)", errors ? "FAIL" : "PASS", errors);
        $finish;
    end

    initial begin
        #8s;
        $display("FAIL vdp_timing_tb timeout");
        $finish;
    end
endmodule
