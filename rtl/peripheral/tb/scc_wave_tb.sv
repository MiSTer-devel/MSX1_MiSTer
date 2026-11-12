// scc_wave testbench against openMSX SCC.cc (Konami SCC, Real mode):
// - deformation bits 0/1 (frequency width, applied when the frequency is written)
// - a frequency write restarts the current byte; a period of 8 or less holds the channel
// - reading the deformation register writes FFh
// - bits 6/7: rotation of the wave data as read by the CPU and write protection
// The step period of a channel (ff_ptr) is measured in clkena ticks: period register + 1.
`timescale 1ns/1ps
module scc_wave_tb;
    logic       clk = 0, clkena = 0, reset = 1, req = 0, wrt = 0;
    logic [7:0] adr = '0, dbo = '0;
    wire  [7:0] dbi;
    wire        ack;
    wire signed [14:0] wave;
    int         errors = 0;

    always #5 clk = ~clk;

    int div = 0;
    always @(posedge clk) begin
        div    <= div == 5 ? 0 : div + 1;
        clkena <= div == 5;
    end

    // dut: SCC; plus: SCC+ (plus_mode 1 = SCC+ mode, 0 = SCC compatible mode). sel picks one.
    logic       sel = 0, plus_mode = 1;
    logic [7:0] fbase = 8'h80, dbase = 8'hE0;  // frequency block and deformation register
    wire  [7:0] dbi_scc, dbi_plus;
    wire  signed [14:0] wave_plus;
    assign dbi = sel ? dbi_plus : dbi_scc;

    scc_wave dut (
        .clk(clk), .clkena(clkena), .reset(reset), .req(req & ~sel), .ack(ack), .wrt(wrt),
        .adr(adr), .dbo(dbo), .dbi(dbi_scc), .wave(wave), .sccPlusChip(1'b0), .sccPlusMode(1'b0)
    );

    scc_wave plus (
        .clk(clk), .clkena(clkena), .reset(reset), .req(req & sel), .ack(), .wrt(wrt),
        .adr(adr), .dbo(dbo), .dbi(dbi_plus), .wave(wave_plus), .sccPlusChip(1'b1), .sccPlusMode(plus_mode)
    );

    task automatic fail(input string msg);
        $display("FAIL %s", msg);
        errors++;
    endtask

    task automatic ok(input string msg);
        $display("ok   %s", msg);
    endtask

    task automatic wr(input logic [7:0] a, input logic [7:0] d);
        @(negedge clk); adr = a; dbo = d; req = 1; wrt = 1;
        repeat (2) @(negedge clk);
        req = 0; wrt = 0;
        repeat (2) @(negedge clk);
    endtask

    task automatic rd(input logic [7:0] a, output logic [7:0] d);
        @(negedge clk); adr = a; req = 1; wrt = 0;
        @(negedge clk); d = dbi;
        @(negedge clk); req = 0;
        repeat (2) @(negedge clk);
    endtask

    task automatic freq(input int ch, input logic [11:0] f);
        wr(fbase + 8'(2 * ch), f[7:0]);
        wr(fbase + 8'(2 * ch + 1), {4'd0, f[11:8]});
    endtask

    task automatic ticks(input int n);
        for (int i = 0; i < n; i++) begin
            @(posedge clk);
            while (!clkena) @(posedge clk);
        end
    endtask

    // clkena ticks between two steps of channel 1
    task automatic period(output int ticks);
        logic [4:0] p;
        int t;
        p = dut.ff_ptr[0];
        while (dut.ff_ptr[0] == p) @(posedge clk);
        p = dut.ff_ptr[0];
        t = 0;
        while (dut.ff_ptr[0] == p) begin
            @(posedge clk);
            if (clkena) t++;
        end
        ticks = t;
    endtask

    task automatic check(input string name, input logic [7:0] deform, input logic [11:0] f,
                         input int expect_ticks);
        int t;
        wr(dbase, deform);
        freq(0, f);
        period(t);
        if (t != expect_ticks)
            fail($sformatf("%s: deform %02h freq %03h -> %0d ticks, expected %0d", name, deform, f, t, expect_ticks));
        else
            ok($sformatf("%s: %0d ticks", name, t));
    endtask

    task automatic expect_rd(input string name, input logic [7:0] a, input logic [7:0] exp);
        logic [7:0] d;
        rd(a, d);
        if (d != exp) fail($sformatf("%s: read %02h = %02h, expected %02h", name, a, d, exp));
        else          ok($sformatf("%s: read %02h = %02h", name, a, d));
    endtask

    // One channel's output: wave x volume without its lower 4 bits (openMSX adjust, measured on
    // a real SCC), at the scale of the full product
    function automatic int prod(input int wav, input int vol);
        return ((wav * vol) >>> 4) * 16;
    endfunction

    task automatic expect_out(input string name, input int exp);
        int o;
        o = sel ? int'(wave_plus) : int'(wave);
        if (o != exp) fail($sformatf("%s: output %0d, expected %0d", name, o, exp));
        else          ok($sformatf("%s: output %0d", name, o));
    endtask

    task automatic fill_waves(input int n);
        for (int i = 0; i < n; i++) wr(8'(i), 8'(i));     // wave n, sample k = 32n + k
    endtask

    initial begin
        int t;
        logic [4:0] p;
        repeat (10) @(posedge clk);
        reset = 0;
        repeat (300) @(posedge clk);                    // wave RAM clear
        wr(8'h8A, 8'h0F);                               // volume 1
        wr(8'h8F, 8'h01);                               // enable channel 1

        // --- deformation bits 0/1
        check("12 bit",            8'h00, 12'h120, 12'h120 + 1);
        check("8 bit (bit 1)",     8'h02, 12'hF20, 12'h020 + 1);
        check("4 bit (bit 0)",     8'h01, 12'hA05, 12'h00A + 1);
        check("bit 1 over bit 0",  8'h03, 12'hF20, 12'h020 + 1);
        wr(8'hE0, 8'h00);                               // masked when written, not now
        period(t);
        if (t != 12'h020 + 1) fail($sformatf("deform change without a frequency write: %0d ticks, expected %0d", t, 12'h020 + 1));
        else                  ok($sformatf("deform change without a frequency write: %0d ticks", t));

        // --- a frequency write restarts the current byte (openMSX count = 0)
        freq(0, 12'h100);
        p = dut.ff_ptr[0];
        while (dut.ff_ptr[0] == p) @(posedge clk);
        ticks(100);
        p = dut.ff_ptr[0];
        wr(8'h80, 8'h00);                               // same value
        t = 0;
        while (dut.ff_ptr[0] == p) begin
            @(posedge clk);
            if (clkena) t++;
        end
        if (t < 12'h100 || t > 12'h100 + 3) fail($sformatf("frequency write: next step after %0d ticks, expected ~%0d", t, 12'h100 + 1));
        else                                ok($sformatf("frequency write restarts the byte: %0d ticks", t));

        // --- a period of 8 or less holds the channel where it is
        freq(0, 12'h020);
        while (dut.ff_ptr[0] == 5'd0) @(posedge clk);
        for (int per = 8; per >= 0; per -= 3) begin
            freq(0, 12'(per));
            p = dut.ff_ptr[0];
            ticks(300);
            if (dut.ff_ptr[0] != p || p == 5'd0)
                fail($sformatf("period %0d: position %0d -> %0d, expected to stay (not 0)", per, p, dut.ff_ptr[0]));
            else
                ok($sformatf("period %0d holds position %0d", per, p));
            freq(0, 12'h020);
            while (dut.ff_ptr[0] == p) @(posedge clk);
        end
        freq(0, 12'h009);
        p = dut.ff_ptr[0];
        ticks(30);
        if (dut.ff_ptr[0] == p) fail("period 9 does not play");
        else                    ok("period 9 plays");

        // --- reading the deformation register writes FFh: bit 1 then cuts the frequency to 8 bits
        wr(8'hE0, 8'h00);
        begin logic [7:0] d; rd(8'hE0, d); end
        freq(0, 12'hF20);
        period(t);
        if (t != 12'h020 + 1) fail($sformatf("deform read: %0d ticks, expected %0d (FFh written)", t, 12'h020 + 1));
        else                  ok("reading the deformation register writes FFh");
        wr(8'hE0, 8'h00);

        // --- rotation and write protection (bits 6/7)
        fill_waves(128);
        freq(0, 12'h020);                               // channel 1: shift every 33 ticks
        freq(1, 12'h020);
        freq(3, 12'h100);                               // channel 4: own period
        freq(4, 12'h020);                               // channel 5: rotation speed of 4 and 5 in mode 40h
        expect_rd("no rotation", 8'h00, 8'h00);

        wr(8'hE0, 8'h40);                               // all rotate, all protected
        ticks(33 * 5 + 10);
        expect_rd("40h: channel 1 rotated by 5", 8'h00, 8'h05);
        expect_rd("40h: channel 1 wraps",        8'h1F, 8'h04);
        expect_rd("40h: channel 4 at channel 5 speed", 8'h60, 8'h65);
        wr(8'h01, 8'hAA);
        wr(8'h61, 8'hAA);
        wr(8'hE0, 8'h00);
        expect_rd("40h: channel 1 protected", 8'h01, 8'h01);
        expect_rd("40h: channel 4 protected", 8'h61, 8'h61);

        wr(8'hE0, 8'h80);                               // channels 4/5 rotate and protected
        ticks(257 * 2 + 10);
        expect_rd("80h: channel 1 not rotated",   8'h00, 8'h00);
        expect_rd("80h: channel 4 at own speed",  8'h60, 8'h62);
        wr(8'h02, 8'hAA);
        wr(8'h62, 8'hAA);
        wr(8'hE0, 8'h00);
        expect_rd("80h: channel 1 writable",  8'h02, 8'hAA);
        expect_rd("80h: channel 4 protected", 8'h62, 8'h62);

        wr(8'hE0, 8'hC0);                               // channels 1-3 rotate, all protected
        ticks(33 * 3 + 10);
        expect_rd("C0h: channel 2 rotated by 3", 8'h20, 8'h23);
        expect_rd("C0h: channel 4 not rotated",  8'h60, 8'h60);
        wr(8'h23, 8'hAA);
        wr(8'h63, 8'hAA);
        wr(8'hE0, 8'h00);
        expect_rd("C0h: channel 2 protected", 8'h23, 8'h23);
        expect_rd("C0h: channel 4 protected", 8'h63, 8'h63);

        // --- channel output latch (openMSX out[]): wave x volume taken at a step or a frequency
        //     write; volume and sample changes wait for it, a disabled channel restarts silent
        for (int i = 0; i < 32; i++) wr(8'(i), 8'h10);
        freq(0, 12'h020);
        ticks(40);
        freq(0, 12'h005);                               // hold: output = 10h x 15
        repeat (30) @(posedge clk);
        expect_out("latch: held channel", 16'h10 * 15);
        wr(8'h8A, 8'h08);
        repeat (30) @(posedge clk);
        expect_out("latch: volume waits", 16'h10 * 15);
        wr(8'h80, 8'h05);
        repeat (30) @(posedge clk);
        expect_out("latch: volume after a frequency write", 16'h10 * 8);
        wr(8'(dut.ff_ptr[0]), 8'h20);
        repeat (30) @(posedge clk);
        expect_out("latch: sample write waits", 16'h10 * 8);
        wr(8'h80, 8'h05);
        repeat (30) @(posedge clk);
        expect_out("latch: sample after a frequency write", 16'h20 * 8);
        wr(8'h8F, 8'h00);
        repeat (30) @(posedge clk);
        expect_out("latch: disabled channel", 0);
        wr(8'h8F, 8'h01);
        repeat (30) @(posedge clk);
        expect_out("latch: enabled again, silent until a step", 0);
        wr(8'h80, 8'h05);
        repeat (30) @(posedge clk);
        expect_out("latch: plays after a frequency write", 16'h20 * 8);

        // --- lower 4 bits of wave x volume dropped before the channels are added
        for (int i = 0; i < 32; i++) wr(8'(i), 8'h01);
        wr(8'h8A, 8'h0F);
        wr(8'h80, 8'h05);
        repeat (30) @(posedge clk);
        expect_out("+1 x 15 = 15 -> 0", 0);
        for (int i = 0; i < 32; i++) wr(8'(i), 8'hFF);
        wr(8'h80, 8'h05);
        repeat (30) @(posedge clk);
        expect_out("-1 x 15 = -15 -> -16", -16);
        for (int i = 0; i < 32; i++) wr(8'(i), 8'h23);
        wr(8'h80, 8'h05);
        repeat (30) @(posedge clk);
        expect_out("35 x 15 = 525 -> 512", 512);
        wr(8'h8A, 8'h0F);
        for (int i = 0; i < 32; i++) wr(8'(i), 8'(3 * i));
        freq(0, 12'h020);
        begin
            int bad = 0;
            for (int n = 0; n < 8; n++) begin
                p = dut.ff_ptr[0];
                while (dut.ff_ptr[0] == p) @(posedge clk);
                ticks(10);
                if (int'(wave) != prod(int'(8'(3 * dut.ff_ptr[0])), 15)) bad++;
            end
            if (bad != 0) fail($sformatf("playing channel: %0d of 8 steps with a wrong output", bad));
            else          ok("playing channel outputs the sample at its position");
        end

        // --- SCC: channel 5 plays wave 5, which takes a copy of every wave 4 write
        wr(8'h8F, 8'h10);
        wr(8'h8E, 8'h0F);
        freq(4, 12'h005);
        repeat (30) @(posedge clk);
        expect_out("SCC: channel 5 plays the copy of wave 4", prod(int'(8'h60 + 8'(dut.ff_ptr[4])), 15));
        wr(8'h8F, 8'h01);

        // --- SCC+ in SCC+ mode: registers at A0 / C0, bit 7 ignored, wave 5 writable and rotating
        sel = 1; plus_mode = 1; fbase = 8'hA0; dbase = 8'hC0;
        fill_waves(160);
        freq(0, 12'h020);
        freq(3, 12'h100);
        freq(4, 12'h020);
        wr(dbase, 8'hC0);                               // bit 7 masked: as 40h
        ticks(33 * 5 + 10);
        expect_rd("SCC+ C0h = 40h: wave 1 rotated by 5", 8'h00, 8'h05);
        expect_rd("SCC+ C0h = 40h: wave 4 at own speed",  8'h60, 8'h60);
        expect_rd("SCC+ C0h = 40h: wave 5 rotated by 5", 8'h80, 8'h85);
        wr(8'h81, 8'hAA);
        wr(dbase, 8'h00);
        expect_rd("SCC+: wave 5 protected", 8'h81, 8'h81);

        // --- SCC+ in SCC mode: wave 5 (A0-BF) reads wave 4 data with the rotation of channel 5
        plus_mode = 0; fbase = 8'h80;
        // wave 5 keeps its SCC+ mode data until wave 4 is written (openMSX wave[4])
        expect_rd("SCC+ compatible: wave 5 keeps its data", 8'hA3, 8'h83);
        wr(8'h8F, 8'h10);
        wr(8'h8E, 8'h01);
        freq(4, 12'h005);
        repeat (30) @(posedge clk);
        expect_out("SCC+ compatible: channel 5 plays wave 5", prod(int'(signed'(8'h80 + 8'(plus.ff_ptr[4]))), 1));
        for (int i = 96; i < 128; i++) wr(8'(i), 8'(i)); // copied to wave 5
        expect_rd("SCC+ compatible: wave 4 write copied to wave 5", 8'hA3, 8'h63);
        freq(4, 12'h005);
        repeat (30) @(posedge clk);
        expect_out("SCC+ compatible: channel 5 plays the copy", prod(int'(8'h60 + 8'(plus.ff_ptr[4])), 1));
        freq(3, 12'h100);
        freq(4, 12'h020);
        wr(dbase, 8'h40);
        ticks(33 * 5 + 10);
        expect_rd("SCC+ compatible 40h: wave 4 at channel 5 speed", 8'h60, 8'h65);
        expect_rd("SCC+ compatible 40h: wave 5 rotated by 5",       8'hA0, 8'h65);
        begin logic [7:0] d; rd(dbase, d); end            // read writes FFh: bit 1 = 8 bit frequency
        freq(0, 12'hF20);
        while (plus.ff_ptr[0] == 5'd0) @(posedge clk);
        begin
            logic [4:0] q; int u;
            q = plus.ff_ptr[0];
            while (plus.ff_ptr[0] == q) @(posedge clk);
            q = plus.ff_ptr[0]; u = 0;
            while (plus.ff_ptr[0] == q) begin @(posedge clk); if (clkena) u++; end
            if (u != 12'h020 + 1) fail($sformatf("SCC+ deform read at C0: %0d ticks, expected %0d", u, 12'h020 + 1));
            else                  ok("SCC+ deform read at C0 writes FFh");
        end

        if (errors == 0) $display("PASS scc_wave_tb");
        else             $display("FAIL scc_wave_tb (%0d)", errors);
        $finish;
    end

    initial begin
        #50ms;
        $display("FAIL scc_wave_tb: timeout");
        $finish;
    end
endmodule
