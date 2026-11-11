// V9938 / V9958 (ESE VDP): the picture must move inside the output window (HBLANK / VBLANK
// with BORDER = 0, what the MiSTer scaler shows) when R#18 (display adjust), R#27 (horizontal
// scroll) or R#25 MSK change. A window that follows the picture hides the movement: smooth
// scrolling by R#18 (Go Figure, Space Manbow) then only jumps by the page flips.
//
// The picture is Graphic 1, every cell white on a blue border. Per output line the tb counts
// the border clocks before (lead) and after (trail) the white pixels inside the window.
//
//   wsl.exe -- bash rtl/peripheral/VIDEO/VDP/tb/run_vdp_adjust.sh

`timescale 1ns/1ps

module vdp_adjust_tb;
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

    // ------------------------------------------------------------- the output window
    // row = line of the window (VBLANK = 0), counted from its first line
    localparam int ROWS = 320;
    int  row = 0, n = 0, first = -1, last = -1, start_h = 0, frame = 0;
    int  c_lead [ROWS], c_trail [ROWS], c_width [ROWS], c_start [ROWS];      // current frame
    int  f_lead [ROWS], f_trail [ROWS], f_width [ROWS], f_start [ROWS], f_rows;   // last whole frame
    bit  hb_prev = 1, vb_prev = 1;
    wire white = r > 6'd30 && g > 6'd30;
    always @(posedge clk) begin
        if (!vblank && vb_prev) row = 0;
        if (vblank && !vb_prev) begin
            f_lead = c_lead; f_trail = c_trail; f_width = c_width; f_start = c_start; f_rows = row;
            frame++;
        end
        if (!hblank) begin
            if (hb_prev) begin n = 0; first = -1; last = -1; start_h = int'(VDP_i.H_CNT); end
            if (white) begin if (first < 0) first = n; last = n; end
            n++;
        end else if (!hb_prev && !vblank && row < ROWS) begin
            c_width[row] = n;
            c_lead[row]  = first;                       // -1: no picture on the line
            c_trail[row] = first < 0 ? -1 : n - 1 - last;
            c_start[row] = start_h;
            row++;
        end
        hb_prev = hblank; vb_prev = vblank;
    end

    task automatic wait_frames(input int k);
        int f = frame + k;
        while (frame < f) @(posedge clk);
    endtask

    int errors = 0;
    int lead0, trail0, start0;

    task automatic check_row(input string what, input int rw, input int lead, input int trail);
        bit ok = f_width[rw] == 1024 && f_lead[rw] == lead && f_trail[rw] == trail && f_start[rw] == start0;
        $display("  %-40s row %3d: window from H_CNT %4d, %4d clocks, border %3d + %3d   expected %4d, 1024, %3d + %3d  %s",
                 what, rw, f_start[rw], f_width[rw], f_lead[rw], f_trail[rw], start0, lead, trail, ok ? "OK" : "FAIL");
        if (!ok) errors++;
    endtask

    // picture moved by px pixels to the right (negative: to the left) of its R#18 = 0 place,
    // ml / mr pixels masked at its left / right edge
    task automatic check_shift(input string what, input int rw, input int px, input int ml = 0, input int mr = 0);
        int a = lead0 - trail0 + 4 * (px + ml);         // first and last picture clock in the window
        int b = lead0 - trail0 + 4 * (px - mr) + 1023;
        check_row(what, rw, a > 0 ? a : 0, b < 1023 ? 1023 - b : 0);
    endtask

    // rows of the window with picture: first and last
    task automatic check_rows(input string what, input int efirst, input int elast, input int erows);
        int rf = -1, rl = -1;
        bit ok;
        for (int i = 0; i < f_rows && i < ROWS; i++) if (f_lead[i] >= 0) begin if (rf < 0) rf = i; rl = i; end
        ok = rf == efirst && rl == elast && f_rows == erows;
        $display("  %-40s window of %3d lines, picture on %3d .. %3d   expected %3d, %3d .. %3d  %s",
                 what, f_rows, rf, rl, erows, efirst, elast, ok ? "OK" : "FAIL");
        if (!ok) errors++;
    endtask

    initial begin
        repeat (20) @(posedge clk);
        reset = 0;
        repeat (20) @(posedge clk);
        set_reg(0, 8'h00);                      // Graphic 1
        set_reg(1, 8'h40);
        set_reg(2, 8'h06); set_reg(3, 8'h80); set_reg(4, 8'h00);
        set_reg(5, 8'h36); set_reg(6, 8'h07);
        set_reg(7, 8'h04);
        set_reg(8, 8'h0A);                      // sprites off
        set_reg(9, 8'h00);                      // NTSC, 192 lines
        set_reg(18, 8'h00); set_reg(23, 8'h00); set_reg(25, 8'h00); set_reg(26, 8'h00); set_reg(27, 8'h00);
        set_reg(16, 8'h04); port_wr(2'd2, 8'h07); port_wr(2'd2, 8'h00);   // 4: blue
        set_reg(16, 8'h0F); port_wr(2'd2, 8'h77); port_wr(2'd2, 8'h07);   // 15: white
        set_reg(14, 8'h00);
        port_wr(2'd1, 8'h00); port_wr(2'd1, 8'h40);
        repeat (8) port_wr(2'd0, 8'hFF);                                  // pattern 0
        port_wr(2'd1, 8'h00); port_wr(2'd1, 8'h60);
        port_wr(2'd0, 8'hF4);                                             // colour 0

        wait_frames(3);
        lead0 = f_lead[100]; trail0 = f_trail[100]; start0 = f_start[100];
        $display("R#18 = 00: window from H_CNT %0d, %0d clocks, %0d lines, border %0d + %0d clocks",
                 start0, f_width[100], f_rows, lead0, trail0);
        if (f_width[100] != 1024 || lead0 < 0 || lead0 > 3 || trail0 < 0 || trail0 > 3) begin
            errors++; $display("FAIL picture does not fill the window at R#18 = 00");
        end
        check_rows("R#18 = 00", 0, 191, 192);

        $display("R#18 horizontal adjust, whole frame");
        set_reg(18, 8'h02); wait_frames(2); check_shift("R#18 = 02 (2 left)",  100, -2);
        set_reg(18, 8'h07); wait_frames(2); check_shift("R#18 = 07 (7 left)",  100, -7);
        set_reg(18, 8'h08); wait_frames(2); check_shift("R#18 = 08 (8 right)", 100,  8);
        set_reg(18, 8'h0F); wait_frames(2); check_shift("R#18 = 0F (1 right)", 100,  1);
        set_reg(18, 8'h00);

        $display("R#18 written on display line 15, cleared after the display (Go Figure)");
        wait_frames(2);
        while (!(row == 15 && !vblank)) @(posedge clk);
        set_reg(18, 8'h08);
        wait_frames(1);
        set_reg(18, 8'h00);
        check_shift("above the split", 5, 0);
        check_shift("below the split", 100, 8);

        $display("R#18 vertical adjust");
        set_reg(18, 8'h20); wait_frames(2); check_rows("R#18 = 20 (2 up)",   0, 189, 192);
        set_reg(18, 8'hE0); wait_frames(2); check_rows("R#18 = E0 (2 down)", 2, 191, 192);
        set_reg(18, 8'h00);

        $display("V9958 horizontal scroll: the window must keep its place and width");
        set_reg(27, 8'h05); wait_frames(2); check_shift("R#27 = 5", 100, 5);
        set_reg(25, 8'h02); wait_frames(2);
        check_shift("R#27 = 5, R#25 MSK", 100, -4, 8, 0);
        set_reg(27, 8'h00); wait_frames(2);
        check_shift("R#27 = 0, R#25 MSK", 100, -4, 8, 0);     // ESE: a masked picture is centred
        set_reg(25, 8'h00);

        $display("PAL, 212 lines (the same before the fix)");
        set_reg(9, 8'h82); wait_frames(3);
        start0 += 4;                            // LED_TV_X_PAL
        check_shift("R#9 = 82", 100, 0);
        if (f_rows != 212) begin errors++; $display("FAIL window of %0d lines, expected 212", f_rows); end
        set_reg(18, 8'h08); wait_frames(2); check_shift("R#9 = 82, R#18 = 08 (8 right)", 100, 8);

        $display("%s vdp_adjust_tb (%0d errors)", errors ? "FAIL" : "PASS", errors);
        $finish;
    end

    initial begin
        #2_000_000_000;
        $display("FAIL vdp_adjust_tb: timeout");
        $finish;
    end
endmodule
