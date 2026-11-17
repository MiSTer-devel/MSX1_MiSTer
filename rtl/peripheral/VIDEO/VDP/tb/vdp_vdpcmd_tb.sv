// V9938 / V9958 (ESE VDP) command speed as measured by bengalack's vdpcmd (tools/vdpcmd):
// the pixels a command handles in one frame, 50 tests in SCREEN 8 (HMMM, LMMM, YMMM, HMMV,
// LMMV; landscape 256x40 and portrait 40x256; normal, sprites off, display off, normal with
// the CPU writing VRAM, display off with the CPU writing VRAM).
//
// The port writes that matter are made at the cycles openMSX makes them, taken from a trace
// of vdpcmd.rom in openMSX (tools/vdpcmd: trace.tcl, mkdata.py): the command start and the
// CPU's OUT (98h) after the interrupt before it, the abort (R#46 = 0) after the next one.
// Everything else (register setup, pixel count, cleanup) is done directly.
//
//   wsl.exe -- bash rtl/peripheral/VIDEO/VDP/tb/run_vdp_vdpcmd.sh gt|nms
//   +k=<n>    cycles added to every timed port write (default -1: INT_N is one cycle after the
//             openMSX interrupt, so the writes land on the openMSX cycle)
//   +only=<n> one test; +dbg: tick of the command write and of the command start

`timescale 1ns/1ps

module vdp_vdpcmd_tb;
    logic clk = 0;
    always #23 clk = ~clk;                      // 21.477 MHz

    logic        reset = 1;
    logic        req = 0, wrt = 0;
    logic [15:0] adr = 0;
    logic  [7:0] dbo = 0;
    wire   [7:0] dbi;
    wire         int_n, we_n, dl_clk;
    wire  [16:0] vaddr;
    wire   [7:0] vdata;
    logic  [7:0] q_lo, q_hi;

    VDP VDP_i (
        .CLK21M(clk), .RESET(reset), .REQ(req), .ACK(), .WRT(wrt), .ADR(adr), .DBI(dbi), .DBO(dbo),
        .INT_N(int_n), .PRAMOE_N(), .PRAMWE_N(we_n), .PRAMADR(vaddr), .PRAMDBI({q_hi, q_lo}),
        .PRAMDBO(vdata), .VDPSPEEDMODE(1'b0), .CENTERYJK_R25_N(1'b0),
        .PVIDEOR(), .PVIDEOG(), .PVIDEOB(), .PVIDEODE(), .HBLANK(), .VBLANK(),
        .PVIDEOHS_N(), .PVIDEOVS_N(), .PVIDEOCS_N(), .PVIDEODHCLK(), .PVIDEODLCLK(dl_clk),
        .NTSC_PAL_TYPE(1'b1), .FORCED_V_MODE(1'b0), .BORDER(1'b0), .VDP_ID(5'b00010), .OFFSET_Y(7'd0)
    );

    // VRAM as in dev_v99 / msx_system: two 64 kB banks, registered read
    logic [7:0] mem_lo [65536], mem_hi [65536];
    always_ff @(posedge clk) begin
        if (~we_n & dl_clk & ~vaddr[16]) mem_lo[vaddr[15:0]] <= vdata;
        if (~we_n & dl_clk &  vaddr[16]) mem_hi[vaddr[15:0]] <= vdata;
        q_lo <= mem_lo[vaddr[15:0]];
        q_hi <= mem_hi[vaddr[15:0]];
    end

    longint cyc = 0, irq_t = 0;
    int     nirq = 0;
    always @(posedge clk) cyc++;
    always @(negedge int_n) begin irq_t = cyc; nirq++; end

    // one port access: REQ for one clock from the clock 'cyc == t' on (as msx.sv: iack)
    task automatic port_at(input longint t, input logic [1:0] p, input logic w, input logic [7:0] d);
        while (cyc < t) @(posedge clk);
        adr <= {14'h0026, p}; dbo <= d; wrt <= w; req <= 1;
        @(posedge clk); req <= 0;
    endtask
    task automatic port_wr(input logic [1:0] p, input logic [7:0] d);
        port_at(cyc + 1, p, 1, d); repeat (40) @(posedge clk);
    endtask
    task automatic set_reg(input int n, input logic [7:0] v);
        port_wr(2'd1, v); port_wr(2'd1, 8'h80 | 8'(n));
    endtask
    task automatic wait_irq(output longint t);
        int n = nirq;
        while (nirq == n) @(posedge clk);
        t = irq_t;
    endtask

    // test parameters (vdpcmd main.c)
    localparam int NT = 50;
    int  t_cmd [NT], t_start [NT], t_ab0 [NT], t_ab [NT], t_cpu0 [NT], n_cpu [NT], g_cpu [NT];
    logic [7:0] r0 [24];
    int  ref_v [NT];
    bit  have_ref = 0;
    const string NAME [5] = '{"Copy HMMM", "Copy LMMM", "Copy YMMM", "Fill HMMV", "Fill LMMV"};

    function automatic int count_pixels();      // page 1: physical offsets 8000h-FFFFh of both banks
        int n = 0;
        for (int i = 16'h8000; i < 65536; i++) n += (mem_lo[i] != 0) + (mem_hi[i] != 0);
        return n;
    endfunction

    int got [NT];
    always @(posedge clk) if ($test$plusargs("dbg") && VDP_i.VDPCMDSTART)
        $display("  START seen at tick %0d", VDP_i.U_VDP_ACCESS_SLOTS.tick);

    initial begin
        string df, rf, line;
        int fd, k, n, only, a [7];
        longint t0, t1;
        if (!$value$plusargs("data=%s", df)) begin $display("FAIL +data= missing"); $finish; end
        if (!$value$plusargs("k=%d", k)) k = -1;
        if (!$value$plusargs("only=%d", only)) only = -1;
        fd = $fopen(df, "r");
        if (fd == 0) begin $display("FAIL cannot read %s", df); $finish; end
        void'($fgets(line, fd));
        for (int i = 0; i < 24; i++) begin
            int v;
            void'($sscanf(line.substr(2 + 3 * i, 3 + 3 * i), "%h", v));
            r0[i] = 8'(v);
        end
        for (int i = 0; i < NT; i++) begin
            void'($fgets(line, fd));
            void'($sscanf(line, "%d %d %d %d %d %d %d", a[0], a[1], a[2], a[3], a[4], a[5], a[6]));
            t_cmd[i] = a[0]; t_start[i] = a[1]; t_ab0[i] = a[2]; t_ab[i] = a[3];
            t_cpu0[i] = a[4]; n_cpu[i] = a[5]; g_cpu[i] = a[6];
        end
        $fclose(fd);
        if ($value$plusargs("ref=%s", rf)) begin   // vdpcmd screen dump: rows " 1 Copy HMMM  THIS REAL | ..."
            fd = $fopen(rf, "r");
            while (fd != 0 && $fgets(line, fd)) begin
                int r, v [10];
                string nm1, nm2;
                if ($sscanf(line, "%d %s %s %d %d | %d %d | %d %d | %d %d | %d %d", r, nm1, nm2,
                            v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9]) == 13 && r >= 1 && r <= 10)
                    for (int c = 0; c < 5; c++) ref_v[c * 10 + r - 1] = v[2 * c];
            end
            have_ref = 1;
        end

        // VRAM: page 0 = FFh (the copy source and vdpcmd's fill), page 1 = 0
        foreach (mem_lo[i]) begin mem_lo[i] = i < 16'h8000 ? 8'hFF : 8'h00; mem_hi[i] = mem_lo[i]; end
        repeat (20) @(posedge clk);
        reset = 0;
        repeat (20) @(posedge clk);
        for (int i = 0; i < 24; i++) if (i != 14 && i != 15 && i != 17) set_reg(i, r0[i]);
        set_reg(15, 8'h00);
        for (int i = 0; i < 4; i++) begin           // a few frames in the mode (R#9 50/60 Hz)
            wait_irq(t0); port_at(cyc + 100, 2'd1, 0, 0);
        end

        for (int i = 0; i < NT; i++) begin
            int cond = i / 10, orient = (i % 10) / 5;
            int x = orient ? 216 : 0;
            int nx = orient ? 40 : 256, ny = orient ? 256 : 40;
            logic [7:0] p [14];
            if (only >= 0 && i != only) continue;
            set_reg(8, cond == 1 ? r0[8] | 8'h02 : r0[8]);
            set_reg(1, (cond == 2 || cond == 4) ? r0[1] & ~8'h40 : r0[1]);
            wait_irq(t0);                                   // SYNC 1
            port_at(cyc + 100, 2'd1, 0, 0);                 // ISR reads S#0
            repeat (4) @(posedge clk);
            set_reg(17, 8'd32);                             // setVDPCmdParamsNI(1, ...)
            p = '{8'(x), 0, 0, 0, 8'(x), 0, 0, 1, 8'(nx), 8'(nx >> 8), 8'(ny), 8'(ny >> 8), 8'hFF, 0};
            for (int j = 0; j < 14; j++) port_wr(2'd3, p[j]);
            if (cond >= 3) begin set_reg(14, 0); port_wr(2'd1, 8'h00); port_wr(2'd1, 8'h40); end
            wait_irq(t0);                                   // SYNC 2
            port_at(t0 + 100, 2'd1, 0, 0);                  // ISR reads S#0
            port_at(t0 + t_start[i] + k, 2'd3, 1, 8'(t_cmd[i]));
            if ($test$plusargs("dbg")) $display("test %0d cmd at tick %0d, irq->cmd %0d, V_CNT %0d", i,
                VDP_i.U_VDP_ACCESS_SLOTS.tick, t_start[i], VDP_i.V_CNT);
            for (int j = 0; j < n_cpu[i]; j++) port_at(t0 + t_cpu0[i] + j * g_cpu[i] + k, 2'd0, 1, 8'hFF);
            t1 = irq_t;
            if (t1 == t0) wait_irq(t1);                     // the next interrupt
            port_at(t1 + t_ab0[i] - 120, 2'd1, 0, 0);       // ISR reads S#0
            port_at(t1 + t_ab0[i] + k, 2'd1, 1, 8'h00);
            port_at(t1 + t_ab[i] + k, 2'd1, 1, 8'hAE);      // R#46 = 0: stop
            repeat (100) @(posedge clk);
            got[i] = count_pixels();
            for (int j = 16'h8000; j < 65536; j++) begin mem_lo[j] = 0; mem_hi[j] = 0; end
            for (int j = 0; j < 16'h8000; j++) begin mem_lo[j] = 8'hFF; mem_hi[j] = 8'hFF; end
        end

        $display("#  OPERATION    NORMAL      NO SPR      NO SCR    NORMAL+CPU  NO SCR+CPU   (tb  ref)");
        for (int r = 0; r < 10; r++) begin
            string s = $sformatf("%2d %s ", r + 1, NAME[r % 5]);
            for (int c = 0; c < 5; c++)
                s = {s, $sformatf(" %5d %5d", got[c * 10 + r], have_ref ? ref_v[c * 10 + r] : 0)};
            $display("%s", s);
        end
        if (have_ref) begin
            int d, worst [5];
            foreach (worst[c]) worst[c] = 0;
            for (int i = 0; i < NT; i++) begin
                d = got[i] - ref_v[i];
                if (d < 0) d = -d;
                if (d > worst[i / 10]) worst[i / 10] = d;
            end
            $display("largest difference per column: %0d %0d %0d %0d %0d", worst[0], worst[1], worst[2], worst[3], worst[4]);
        end
        $finish;
    end
endmodule
