// V9958 horizontal scroll R#26 / R#27 (with R#25 MSK, SP2).
//
// Static scenes: one hash per output frame (both half dots), to compare two versions of the VDP;
// a scroll set for the whole frame must give the same picture before and after a change.
// Within a line (openMSX: a write is rendered from the dot it falls on): R#27 or R#26 written at
// dot 100 of display line 100 must split that line, the left part with the old scroll and the
// right part with the new one, from a dot no later than the next 8-dot fetch after the write.
//
//   wsl.exe -- bash rtl/peripheral/VIDEO/VDP/tb/run_vdp_hscroll.sh [+dump=<file>]
//   ALT=<dir> takes the VDP sources from <dir>: the scene hashes of two runs must be the same.

`timescale 1ns/1ps

module vdp_hscroll_tb;
    import VDP_PACKAGE::*;

    logic clk = 0;
    always #23 clk = ~clk;                      // 21.477 MHz

    logic        reset = 1;
    logic        req = 0, wrt = 0;
    logic [15:0] adr = 0;
    logic  [7:0] dbo = 0;
    wire   [7:0] dbi;
    wire         we_n, dl_clk, hblank, vblank;
    wire  [16:0] vaddr;
    wire   [7:0] vdata;
    logic  [7:0] q_lo, q_hi;
    wire   [5:0] r, g, b;

    VDP VDP_i (
        .CLK21M(clk), .RESET(reset), .REQ(req), .ACK(), .WRT(wrt), .ADR(adr), .DBI(dbi), .DBO(dbo),
        .INT_N(), .PRAMOE_N(), .PRAMWE_N(we_n), .PRAMADR(vaddr), .PRAMDBI({q_hi, q_lo}),
        .PRAMDBO(vdata), .VDPSPEEDMODE(1'b0), .CENTERYJK_R25_N(1'b0),
        .PVIDEOR(r), .PVIDEOG(g), .PVIDEOB(b), .PVIDEODE(), .HBLANK(hblank), .VBLANK(vblank),
        .PVIDEOHS_N(), .PVIDEOVS_N(), .PVIDEOCS_N(), .PVIDEODHCLK(), .PVIDEODLCLK(dl_clk),
        .NTSC_PAL_TYPE(1'b1), .FORCED_V_MODE(1'b0), .BORDER(1'b0), .VDP_ID(5'b00010), .OFFSET_Y(7'd0)
    );

    logic [7:0] mem_lo [65536], mem_hi [65536];
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

    // ------------------------------------------------------------- frame capture
    // two samples per dot (both halves in the 512-dot modes); read right after the frame ends
    localparam int W = 512, H = 212;
    logic [17:0] cur [H*W];
    int row = 0, col = 0, frame = 0, rows = 0;
    logic [31:0] hash = 0, f_hash = 0;
    bit hb_prev = 1, vb_prev = 1;
    always @(posedge clk) begin
        if (!vblank && vb_prev) begin row = 0; hash = 0; end
        if (vblank && !vb_prev) begin f_hash = hash; rows = row; frame++; end
        if (!hblank && !vblank && (VDP_i.DOTSTATE == 2'b01 || VDP_i.DOTSTATE == 2'b10)) begin
            if (hb_prev) col = 0;
            hash = hash * 32'd33 + {14'b0, r, g, b};
            if (row < H && col < W) cur[row * W + col] = {r, g, b};
            col++;
        end else if (hblank && !hb_prev && !vblank) row++;
        hb_prev = hblank; vb_prev = vblank;
    end

    task automatic wait_frames(input int k);
        int f = frame + k;
        while (frame < f) @(posedge clk);
    endtask

    int fd = 0;
    task automatic dump_frame(input string what);
        if (!fd) return;
        $fwrite(fd, "# %s\n", what);
        for (int y = 0; y < rows && y < H; y++) begin
            $fwrite(fd, "%0d:", y);
            for (int x = 0; x < W; x++) $fwrite(fd, " %05x", cur[y * W + x]);
            $fwrite(fd, "\n");
        end
    endtask

    typedef struct { logic [7:0] r0, r1, r2, r8, r25, r26, r27; } scene_t;
    task automatic apply(input scene_t s);
        set_reg(0, s.r0); set_reg(1, s.r1); set_reg(2, s.r2); set_reg(8, s.r8);
        set_reg(25, s.r25); set_reg(26, s.r26); set_reg(27, s.r27);
    endtask

    task automatic scene(input string what, input scene_t s);
        apply(s);
        wait_frames(2);
        $display("  %-44s rows %0d frame %08x", what, rows, f_hash);
        dump_frame(what);
    endtask

    // ------------------------------------------------------------- write within a line
    logic [17:0] ref_a [H*W], ref_b [H*W];
    int errors = 0;

    // second byte of a register write when the output shows dot `dot` of display line `ln`
    task automatic reg_at(input int n, input logic [7:0] v, input int ln, input int dot);
        port_wr(2'd1, v);
        while (VDP_i.PREDOTCOUNTER_YP != 9'(ln)) @(posedge clk);
        while (VDP_i.H_CNT != 11'(257 + 4 * dot)) @(posedge clk);
        adr <= {14'h0026, 2'd1}; dbo <= 8'h80 | 8'(n); wrt <= 1; req <= 1;
        @(posedge clk); req <= 0;
        repeat (40) @(posedge clk);
    endtask

    task automatic midline(input string what, input scene_t a, input scene_t bs, input int reg_n,
                           input logic [7:0] v, input int ln, input int dot);
        int k = -1, bad_a = 0, bad_b = 0, bad = 0;
        apply(bs); wait_frames(2);
        for (int i = 0; i < H * W; i++) ref_b[i] = cur[i];
        apply(a);  wait_frames(2);
        for (int i = 0; i < H * W; i++) ref_a[i] = cur[i];
        // the frame after one with the write: earlier lines A, the line split, later lines B
        reg_at(reg_n, v, ln, dot);
        while (!vblank) @(posedge clk);
        apply(a);
        wait_frames(1);
        reg_at(reg_n, v, ln, dot);
        while (!vblank) @(posedge clk);
        @(posedge clk);
        for (int x = 0; x < W; x++) begin
            if (cur[(ln - 1) * W + x] != ref_a[(ln - 1) * W + x]) bad_a++;
            if (cur[(ln + 1) * W + x] != ref_b[(ln + 1) * W + x]) bad_b++;
        end
        // first dot of line ln that is B and differs from A; all A before, all B after
        for (int x = 0; x < W; x += 2)
            if (k < 0 && cur[ln * W + x] != ref_a[ln * W + x]) k = x / 2;
        if (k >= 0)
            for (int x = 0; x < W; x += 2)
                if (cur[ln * W + x] != (x / 2 < k ? ref_a[ln * W + x] : ref_b[ln * W + x])) bad++;
        $display("  %-44s line %0d from dot %0d (written at dot %0d), %0d dots of neither, line %0d %0d / line %0d %0d differ",
                 what, ln, k, dot, bad, ln - 1, bad_a, ln + 1, bad_b);
        if (k < dot - 2 || k > dot + 20 || bad || bad_a || bad_b) begin
            errors++; $display("FAIL %s", what);
        end
        apply(a);
    endtask

    // ------------------------------------------------------------- scenes
    initial begin
        logic [15:0] lfsr = 16'hACE1;
        string dump;
        scene_t s;
        if ($value$plusargs("dump=%s", dump)) fd = $fopen(dump, "w");
        // VRAM: pseudo-random, sprite tables written below
        for (int i = 0; i < 65536; i++) begin
            mem_lo[i] = lfsr[7:0]; lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            mem_hi[i] = lfsr[7:0]; lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        end
        // sprite mode 2: attributes 7600h, colours 7400h, patterns 7800h (G4); three sprites
        foreach (mem_lo[i]) if (i >= 16'h7400 && i < 16'h7600) mem_lo[i] = 8'(4 + i[7:4]);
        begin
            logic [7:0] sat [16] = '{50, 0, 0, 0,  50, 100, 4, 0,  60, 250, 8, 0,  8'hD8, 0, 0, 0};
            foreach (sat[i]) mem_lo[16'h7600 + i] = sat[i];
        end
        repeat (20) @(posedge clk);
        reset = 0;
        repeat (20) @(posedge clk);
        set_reg(3, 8'hFF); set_reg(4, 8'h03); set_reg(5, 8'hEF); set_reg(6, 8'h0F);
        set_reg(7, 8'h0D); set_reg(9, 8'h00); set_reg(10, 8'h00); set_reg(11, 8'h00);
        set_reg(18, 8'h00); set_reg(19, 8'h00); set_reg(23, 8'h00);
        for (int i = 0; i < 16; i++) begin      // palette: 16 distinct colours
            set_reg(16, 8'(i)); port_wr(2'd2, 8'({i[3:2], 2'b0, i[1:0], 2'b0})); port_wr(2'd2, 8'(i[2:0] << 1));
        end

        $display("static scenes (hash of one frame)");
        //              R#0    R#1    R#2    R#8    R#25   R#26   R#27
        scene("G4 no scroll, 3 sprites",          '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h00, 8'h00, 8'h00});
        scene("G4 R#27 = 3",                      '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h00, 8'h00, 8'h03});
        scene("G4 R#27 = 7",                      '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h00, 8'h00, 8'h07});
        scene("G4 R#26 = 5, R#27 = 3",            '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h00, 8'h05, 8'h03});
        scene("G4 R#26 = 5, R#27 = 3, MSK",       '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h02, 8'h05, 8'h03});
        scene("G4 R#27 = 0, MSK",                 '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h02, 8'h00, 8'h00});
        scene("G4 SP2, R#26 = 37, R#27 = 5",      '{8'h06, 8'h42, 8'h3F, 8'h08, 8'h01, 8'h25, 8'h05});
        scene("G5 R#26 = 2, R#27 = 3",            '{8'h08, 8'h42, 8'h1F, 8'h08, 8'h00, 8'h02, 8'h03});
        scene("G7 R#26 = 1, R#27 = 6",            '{8'h0E, 8'h42, 8'h1F, 8'h08, 8'h00, 8'h01, 8'h06});
        scene("G7 YJK, R#27 = 3",                 '{8'h0E, 8'h42, 8'h1F, 8'h08, 8'h08, 8'h00, 8'h03});
        scene("G1 R#26 = 3, R#27 = 5, no sprites", '{8'h00, 8'h40, 8'h06, 8'h0A, 8'h00, 8'h03, 8'h05});
        scene("TEXT1 R#27 = 2",                   '{8'h00, 8'h50, 8'h06, 8'h0A, 8'h00, 8'h00, 8'h02});

        $display("writes within a line (dot 100 of line 100)");
        midline("G4 R#27 1 -> 6", '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h00, 8'h02, 8'h01},
                                  '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h00, 8'h02, 8'h06}, 27, 8'h06, 100, 100);
        midline("G4 R#26 2 -> 9", '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h00, 8'h02, 8'h01},
                                  '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h00, 8'h09, 8'h01}, 26, 8'h09, 100, 100);
        midline("G4 MSK R#27 1 -> 6", '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h02, 8'h02, 8'h01},
                                      '{8'h06, 8'h42, 8'h1F, 8'h08, 8'h02, 8'h02, 8'h06}, 27, 8'h06, 100, 100);

        if (fd) $fclose(fd);
        $display("%s vdp_hscroll_tb (%0d errors)", errors ? "FAIL" : "PASS", errors);
        $finish;
    end

    initial begin
        #2_000_000_000;
        $display("FAIL vdp_hscroll_tb: timeout");
        $finish;
    end
endmodule
