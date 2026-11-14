// Sprite picture of static scenes: a hash of one output frame (and S#0, S#3..S#6) per scene,
// to compare two versions of the sprite module pixel by pixel. Scenes: sprite modes 1 and 2,
// 8x8 / 16x16, zoom, EC, CC colour OR, 9 sprites on a line, R#23, 212 lines, PAL + R#18,
// colour 0 with and without TP. Static scenes do not depend on when the Y test runs.
//
//   wsl.exe -- bash rtl/peripheral/VIDEO/VDP/tb/run_vdp_sprite_pix.sh [+dump=<file>]
//   ALT=<dir> takes the VDP sources from <dir>: the hashes of two runs must be the same.

`timescale 1ns/1ps

module vdp_sprite_pix_tb;
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

    task automatic vram_wr(input logic [15:0] a, input logic [7:0] d [$]);
        set_reg(14, 8'(a[15:14]));
        port_wr(2'd1, a[7:0]); port_wr(2'd1, {2'b01, a[13:8]});
        foreach (d[i]) port_wr(2'd0, d[i]);
    endtask

    logic [7:0] st;
    task automatic status(input int n);
        set_reg(15, 8'(n));
        @(posedge clk); adr <= {14'h0026, 2'd1}; wrt <= 0; req <= 1;
        @(posedge clk); req <= 0;
        @(posedge clk); st = dbi;
    endtask

    // one sample per dot of the window; hash and optional dump of the last whole frame
    int fd = 0;
    int row = 0, frame = 0, col = 0;
    logic [31:0] hash = 0, f_hash = 0;
    int f_rows = 0;
    bit hb_prev = 1, vb_prev = 1, in_row = 0;
    always @(posedge clk) begin
        if (!vblank && vb_prev) begin row = 0; hash = 0; end
        if (vblank && !vb_prev) begin f_hash = hash; f_rows = row; frame++; end
        if (!hblank && !vblank && VDP_i.DOTSTATE == 2'b01) begin
            if (!in_row) begin col = 0; in_row = 1; if (fd) $fwrite(fd, "%0d:", row); end
            hash = hash * 32'd33 + {14'b0, r, g, b};
            if (fd) $fwrite(fd, " %05x", {14'b0, r, g, b});
            col++;
        end else if (hblank && !hb_prev && !vblank) begin
            if (fd) $fwrite(fd, "\n");
            row++;
        end
        hb_prev = hblank; vb_prev = vblank;
    end

    task automatic wait_frames(input int k);
        int f = frame + k;
        while (frame < f) @(posedge clk);
    endtask

    // 32 attribute entries (Y, X, pattern, colour); sprite mode 2 colour table 16 rows each
    typedef logic [7:0] sat_t [$];
    task automatic scene(input string what, input bit mode2, input logic [7:0] r0, input logic [7:0] r1,
                         input logic [7:0] r8, input logic [7:0] r9, input logic [7:0] r18,
                         input logic [7:0] r23, input sat_t sat, input sat_t col);
        set_reg(0, r0); set_reg(1, r1); set_reg(8, r8); set_reg(9, r9); set_reg(18, r18); set_reg(23, r23);
        vram_wr(mode2 ? 16'h1E00 : 16'h1F80, sat);    // mode 1: R#5 = 3Fh is 1F80h
        if (mode2) vram_wr(16'h1C00, col);
        if (fd) $fwrite(fd, "# %s\n", what);
        wait_frames(3); status(0);              // clear C and 5S
        wait_frames(1); status(0);
        $write("  %-40s rows %0d frame %08x  S#0 %02x", what, f_rows, f_hash, st);
        status(3); $write(" S#3 %0d", st); status(4); $write(" S#4 %0d", st);
        status(6); $write(" S#6 %0d", st); status(5); $display(" S#5 %0d", st);
    endtask

    function automatic sat_t attr(input logic [7:0] y [$], input logic [7:0] x [$],
                                  input logic [7:0] p [$], input logic [7:0] c [$]);
        sat_t s;
        foreach (y[i]) s = {s, y[i], x[i], p[i], c[i]};
        s.push_back(8'd216);
        return s;
    endfunction

    function automatic sat_t colours(input logic [7:0] c [$]);   // mode 2: 16 rows per sprite
        sat_t s;
        foreach (c[i]) repeat (16) s.push_back(c[i]);
        return s;
    endfunction

    initial begin
        logic [7:0] pat [$], one [$];
        logic [15:0] lfsr = 16'hACE1;
        string dump;
        if ($value$plusargs("dump=%s", dump)) fd = $fopen(dump, "w");
        repeat (20) @(posedge clk);
        reset = 0;
        repeat (20) @(posedge clk);
        set_reg(2, 8'h06); set_reg(3, 8'hFF); set_reg(4, 8'h03);
        set_reg(5, 8'h3F); set_reg(11, 8'h00);  // attributes 1E00h, colours 1C00h
        set_reg(6, 8'h07);                      // patterns 3800h
        set_reg(7, 8'h00); set_reg(19, 8'h00);
        for (int i = 0; i < 16; i++) begin      // palette: 16 distinct colours
            set_reg(16, 8'(i)); port_wr(2'd2, 8'({i[3:2], 2'b0, i[1:0], 2'b0})); port_wr(2'd2, 8'(i[2:0] << 1));
        end
        // pattern table (256 patterns): 1024 pseudo-random bytes, then the inverse
        repeat (1024) begin
            pat.push_back(lfsr[7:0]);
            lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        end
        foreach (pat[i]) if (i < 1024) pat.push_back(~pat[i]);
        vram_wr(16'h3800, pat);
        vram_wr(16'h0000, '{8'h0F, 8'hF0, 8'h0F, 8'hF0, 8'h0F, 8'hF0, 8'h0F, 8'hF0});   // G3 pattern 0
        one = '{8'd9};

        // Graphic 3 (SCREEN 4), sprite mode 2
        scene("G3 16x16, 8 on a line, EC, 9th", 1, 8'h04, 8'h42, 8'h08, 8'h00, 8'h00, 8'h00,
              attr('{50, 50, 50, 50, 50, 50, 50, 50, 50, 100, 120, 150},
                   '{0, 100, 240, 250, 16, 40, 60, 110, 200, 30, 254, 8},
                   '{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44},
                   '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}),
              colours('{1, 2, 3, 4, 8'h85, 8'h86, 7, 8, 9, 10, 11, 12}));
        scene("G3 16x16 zoom", 1, 8'h04, 8'h43, 8'h08, 8'h00, 8'h00, 8'h00,
              attr('{50, 50, 50, 50, 50, 100, 120, 150},
                   '{0, 100, 240, 250, 16, 30, 254, 8},
                   '{0, 4, 8, 12, 16, 36, 40, 44},
                   '{0, 0, 0, 0, 0, 0, 0, 0}),
              colours('{1, 2, 3, 4, 8'h85, 10, 11, 12}));
        scene("G3 8x8", 1, 8'h04, 8'h40, 8'h08, 8'h00, 8'h00, 8'h00,
              attr('{50, 50, 50, 50, 50, 100, 120, 150},
                   '{0, 100, 248, 252, 16, 30, 254, 8},
                   '{0, 1, 2, 3, 4, 36, 40, 44},
                   '{0, 0, 0, 0, 0, 0, 0, 0}),
              colours('{1, 2, 3, 4, 8'h85, 10, 11, 12}));
        scene("G3 8x8 zoom", 1, 8'h04, 8'h41, 8'h08, 8'h00, 8'h00, 8'h00,
              attr('{50, 50, 50, 50, 50, 100, 120, 150},
                   '{0, 100, 240, 252, 16, 30, 254, 8},
                   '{0, 1, 2, 3, 4, 36, 40, 44},
                   '{0, 0, 0, 0, 0, 0, 0, 0}),
              colours('{1, 2, 3, 4, 8'h85, 10, 11, 12}));
        scene("G3 CC colour OR, IC", 1, 8'h04, 8'h42, 8'h08, 8'h00, 8'h00, 8'h00,
              attr('{50, 50, 50, 55, 50, 50, 50, 60},
                   '{100, 100, 104, 100, 150, 150, 150, 150},
                   '{60, 64, 60, 68, 60, 60, 60, 60},
                   '{0, 0, 0, 0, 0, 0, 0, 0}),
              colours('{1, 8'h42, 8'h44, 8, 8'h41, 8'h22, 8'h61, 3}));
        scene("G3 9 sprites at Y = 255, colour 0", 1, 8'h04, 8'h42, 8'h08, 8'h00, 8'h00, 8'h00,
              attr('{255, 255, 255, 255, 255, 255, 255, 255, 255, 250, 60},
                   '{0, 20, 40, 60, 80, 100, 120, 140, 160, 200, 100},
                   '{0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 60},
                   '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}),
              colours('{1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0}));
        scene("G3 colour 0 with TP off (R#8 bit 5)", 1, 8'h04, 8'h42, 8'h28, 8'h00, 8'h00, 8'h00,
              attr('{255, 250, 60, 60},
                   '{0, 200, 100, 104},
                   '{0, 36, 60, 60},
                   '{0, 0, 0, 0}),
              colours('{1, 0, 0, 5}));
        scene("G3 R#23 = 5", 1, 8'h04, 8'h42, 8'h08, 8'h00, 8'h00, 8'h05,
              attr('{255, 50, 100, 180},
                   '{0, 100, 30, 8},
                   '{0, 4, 36, 44},
                   '{0, 0, 0, 0}),
              colours('{1, 2, 10, 12}));
        scene("G3 212 lines, Y = 200, 205", 1, 8'h04, 8'h42, 8'h08, 8'h80, 8'h00, 8'h00,
              attr('{255, 50, 200, 205},
                   '{0, 100, 30, 8},
                   '{0, 4, 36, 44},
                   '{0, 0, 0, 0}),
              colours('{1, 2, 10, 12}));
        scene("G3 PAL, R#18 = 0C", 1, 8'h04, 8'h42, 8'h08, 8'h02, 8'h0C, 8'h00,
              attr('{255, 50, 50, 150},
                   '{0, 100, 16, 8},
                   '{0, 4, 16, 44},
                   '{0, 0, 0, 0}),
              colours('{1, 2, 8'h85, 12}));
        // SCREEN 5 (bitmap), interleaved VRAM
        scene("G4 16x16", 1, 8'h06, 8'h42, 8'h08, 8'h00, 8'h00, 8'h00,
              attr('{50, 50, 50, 100, 120, 150},
                   '{0, 100, 16, 30, 254, 8},
                   '{0, 4, 16, 36, 40, 44},
                   '{0, 0, 0, 0, 0, 0}),
              colours('{1, 2, 8'h85, 10, 11, 12}));
        // Graphic 2 (SCREEN 2), sprite mode 1: colour in the attribute, 4 per line, EC = bit 7
        scene("G2 mode 1 16x16, 5 on a line", 0, 8'h02, 8'h42, 8'h08, 8'h00, 8'h00, 8'h00,
              attr('{50, 50, 50, 50, 50, 100, 120, 150},
                   '{0, 100, 240, 16, 60, 30, 254, 8},
                   '{0, 4, 8, 16, 20, 36, 40, 44},
                   '{1, 2, 3, 8'h85, 7, 10, 11, 12}), one);
        scene("G2 mode 1 8x8 zoom", 0, 8'h02, 8'h41, 8'h08, 8'h00, 8'h00, 8'h00,
              attr('{50, 50, 50, 100, 120, 150},
                   '{0, 100, 16, 30, 254, 8},
                   '{0, 1, 4, 36, 40, 44},
                   '{1, 2, 8'h85, 10, 11, 12}), one);
        scene("G2 mode 1 collision", 0, 8'h02, 8'h42, 8'h08, 8'h00, 8'h00, 8'h00,
              attr('{80, 80, 150},
                   '{100, 104, 8},
                   '{60, 60, 44},
                   '{1, 2, 12}), one);

        if (fd) $fclose(fd);
        $display("END vdp_sprite_pix_tb");
        $finish;
    end

    initial begin
        #2_000_000_000;
        $display("FAIL vdp_sprite_pix_tb: timeout");
        $finish;
    end
endmodule
