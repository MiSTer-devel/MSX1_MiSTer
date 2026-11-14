// V9938 sprite mode 2: a sprite with Y covers display lines Y+1 .. Y+16 (Y = 255: lines 0..15).
// Graphic 3, black picture, two white 16x16 sprites at Y = 255 and Y = 63; per output line of
// the window (BORDER = 0) the tb notes whether white pixels are on it. Lilly's Saga masks the
// right edge with such sprite columns, rewritten by a line interrupt every 64 lines.
//
//   wsl.exe -- bash rtl/peripheral/VIDEO/VDP/tb/run_vdp_sprite_y.sh

`timescale 1ns/1ps

module vdp_sprite_y_tb;
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

    task automatic vram_wr(input logic [13:0] a, input logic [7:0] d [$]);
        port_wr(2'd1, a[7:0]); port_wr(2'd1, {2'b01, a[13:8]});
        foreach (d[i]) port_wr(2'd0, d[i]);
    endtask

    // lines of the window with white (sprite) pixels in the last whole frame
    localparam int ROWS = 320;
    int  row = 0, frame = 0, f_rows = 0;
    bit  c_white [ROWS], f_white [ROWS];
    bit  hb_prev = 1, vb_prev = 1, on_line = 0;
    wire white = r > 6'd30 && g > 6'd30 && b > 6'd30;
    always @(posedge clk) begin
        if (!vblank && vb_prev) row = 0;
        if (vblank && !vb_prev) begin f_white = c_white; f_rows = row; frame++; end
        if (!hblank) begin
            if (hb_prev) on_line = 0;
            if (white) on_line = 1;
        end else if (!hb_prev && !vblank && row < ROWS) begin
            c_white[row] = on_line;
            row++;
        end
        hb_prev = hblank; vb_prev = vblank;
    end

    task automatic wait_frames(input int k);
        int f = frame + k;
        while (frame < f) @(posedge clk);
    endtask

    int errors = 0;

    // runs of white lines must be exactly [a0, a1] and [b0, b1]
    task automatic check(input string what, input int a0, input int a1, input int b0, input int b1);
        string got = "";
        bit ok = 1;
        int s = -1;
        for (int i = 0; i <= f_rows; i++) begin
            bit w = i < f_rows && f_white[i];
            if (w && s < 0) s = i;
            if (!w && s >= 0) begin got = {got, $sformatf(" %0d..%0d", s, i - 1)}; s = -1; end
        end
        for (int i = 0; i < f_rows; i++) if (f_white[i] != ((i >= a0 && i <= a1) || (i >= b0 && i <= b1))) ok = 0;
        $display("  %-34s sprite lines%-16s expected %0d..%0d %0d..%0d  %s", what, got, a0, a1, b0, b1, ok ? "OK" : "FAIL");
        if (!ok) errors++;
    endtask

    initial begin
        logic [7:0] pat [$], col [$];
        repeat (20) @(posedge clk);
        reset = 0;
        repeat (20) @(posedge clk);
        set_reg(0, 8'h04);                      // Graphic 3
        set_reg(1, 8'h42);                      // display on, 16x16 sprites
        set_reg(2, 8'h06); set_reg(3, 8'hFF); set_reg(4, 8'h03);
        set_reg(5, 8'h3F); set_reg(11, 8'h00);  // attributes 1E00h, colours 1C00h
        set_reg(6, 8'h07);                      // patterns 3800h
        set_reg(7, 8'h00);
        set_reg(8, 8'h08);
        set_reg(9, 8'h00);                      // NTSC, 192 lines
        set_reg(18, 8'h00); set_reg(23, 8'h00); set_reg(14, 8'h00);
        set_reg(16, 8'h0F); port_wr(2'd2, 8'h77); port_wr(2'd2, 8'h07);   // 15: white
        set_reg(16, 8'h00); port_wr(2'd2, 8'h00); port_wr(2'd2, 8'h00);   // 0: black
        repeat (32) pat.push_back(8'hFF);
        vram_wr(14'h3800, pat);
        repeat (32) col.push_back(8'h0F);
        vram_wr(14'h1C00, col);
        vram_wr(14'h1E00, '{8'd255, 8'd100, 8'd0, 8'd0, 8'd63, 8'd100, 8'd0, 8'd0, 8'd216});

        wait_frames(3);
        check("NTSC 192, Y = 255 and 63", 0, 15, 64, 79);
        set_reg(18, 8'h0C); wait_frames(2);
        check("NTSC 192, R#18 = 0C", 0, 15, 64, 79);
        set_reg(18, 8'h00);
        set_reg(9, 8'h02); wait_frames(3);
        check("PAL 192", 0, 15, 64, 79);
        set_reg(18, 8'h0C); wait_frames(2);
        check("PAL 192, R#18 = 0C", 0, 15, 64, 79);

        $display("%s vdp_sprite_y_tb (%0d errors)", errors ? "FAIL" : "PASS", errors);
        $finish;
    end

    initial begin
        #2_000_000_000;
        $display("FAIL vdp_sprite_y_tb: timeout");
        $finish;
    end
endmodule
