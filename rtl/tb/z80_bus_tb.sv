// Bus cycles inside an instruction: TV80a against the Z80 (Zilog data sheet; the same sequences
// come out of the A-Z80 core and the FUSE tests). For the cases of z80_timing_prog.py listed in
// `expect_of` the start of every strobe is compared, in half T states from the first M1:
//   F opcode fetch, X refresh, R / W memory read / write, I / O port read / write,
//   A interrupt acknowledge (IORQ with M1); "/n" = length of the instruction.
// Also: EX (SP),HL reads SP, SP+1 and writes SP+1, SP; the interrupt acknowledge increments R once;
// results of EX (SP),HL / IX / IY, RLD, RRD, INI, INIR and IND (program at A000h).
// Run: wsl.exe -- bash rtl/tb/run_z80_bus.sh
module z80_bus_tb;

logic clk = 0; always #1 clk = ~clk;
logic ph = 0, reset = 1;                 // ph = 1: high half of the CPU clock
always @(posedge clk) ph <= ~ph;

`include "z80_timing_cases.svh"

logic m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
logic [15:0] a; logic [7:0] dout, di;
logic int_n = 1;
TV80a #(.Mode(0), .R800_MULU(1), .IOWait(1)) cpu (
    .RESET_n(~reset), .R800_mode(1'b0), .CMOS(1'b0), .CLK(clk), .CE_p(~ph), .CE_n(ph),
    .WAIT_n(1'b1), .INT_n(int_n), .NMI_n(1'b1), .BUSRQ_n(1'b1),
    .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n), .RFSH_n(rfsh_n),
    .HALT_n(), .BUSAK_n(), .A(a), .DI(di), .DO(dout), .MC(), .TS(), .IntCycle_n(), .MULU(),
`ifdef TV80_FAST
    .FAST(1'b0), .LAST_T(), .ACC_START(),
`endif
    .REG(), .DIRSet(1'b0), .DIR('0));
logic [7:0] mem [0:65535];
assign di = ~mreq_n ? mem[a] : (~iorq_n && ~m1_n) ? 8'hFF : (a[7:0] ^ 8'h5A);
always @(posedge clk) if (~mreq_n && ~wr_n) mem[a] <= dout;

function automatic string expect_of(input string n);
    if (n == "E3 EX (SP),HL")                       return "F0 X4 R8 R14 W24 W30 /38";
    if (n == "DD E3 EX (SP),HL" || n == "FD E3 EX (SP),HL") return "F0 X4 F8 X12 R16 R22 W32 W38 /46";
    if (n == "ED 67 RRD/RLD" || n == "ED 6F RRD/RLD") return "F0 X4 F8 X12 R16 W32 /36";
    if (n == "ED A2 block" || n == "ED AA block")   return "F0 X4 F8 X12 I19 W28 /32";
    if (n == "ED A3 block" || n == "ED AB block")   return "F0 X4 F8 X12 R18 O25 /32";
    if (n == "ED B2 INIR..OTDR repeat" || n == "ED BA INIR..OTDR repeat") return "F0 X4 F8 X12 I19 W28 /42";
    if (n == "ED B2 INIR..OTDR last" || n == "ED BA INIR..OTDR last")     return "F0 X4 F8 X12 I19 W28 /32";
    if (n == "ED B3 INIR..OTDR repeat" || n == "ED BB INIR..OTDR repeat") return "F0 X4 F8 X12 R18 O25 /42";
    if (n == "INT IM 1" || n == "INT IM 0 (RST 38h on the bus)") return "A4 X8 W16 W22 /26";
    if (n == "INT IM 2")                            return "A4 X8 W16 W22 R26 R32 /38";
    if (n == "00 NOP")                              return "F0 X4 /8";
    if (n == "D3 OUT (n),A")                        return "F0 X4 R8 O15 /22";
    if (n == "DB IN A,(n)")                         return "F0 X4 R8 I15 /22";
    return "";
endfunction

// Results of the reordered instructions: program at A000h, run before the cases
localparam int FN = 117;
logic [7:0] fprog [FN] = '{8'h31, 8'h00, 8'hF0, 8'h21, 8'h34, 8'h12, 8'h01, 8'h78, 8'h56, 8'hC5, 8'hE3, 8'h22, 8'h00, 8'hD1, 8'hE1, 8'h22, 8'h02, 8'hD1, 8'hDD, 8'h21, 8'hCD, 8'hAB, 8'hC5, 8'hDD, 8'hE3, 8'hDD, 8'h22, 8'h04, 8'hD1, 8'hE1, 8'h22, 8'h06, 8'hD1, 8'hFD, 8'h21, 8'hEF, 8'hBE, 8'hC5, 8'hFD, 8'hE3, 8'hFD, 8'h22, 8'h08, 8'hD1, 8'hE1, 8'h22, 8'h0A, 8'hD1, 8'h21, 8'h10, 8'hD1, 8'h36, 8'h34, 8'h3E, 8'h12, 8'hED, 8'h6F, 8'h32, 8'h0C, 8'hD1, 8'h7E, 8'h32, 8'h0D, 8'hD1, 8'h36, 8'h34, 8'h3E, 8'h12, 8'hED, 8'h67, 8'h32, 8'h0E, 8'hD1, 8'h7E, 8'h32, 8'h0F, 8'hD1, 8'h21, 8'h20, 8'hD1, 8'h01, 8'h10, 8'h03, 8'hED, 8'hA2, 8'h78, 8'h32, 8'h11, 8'hD1, 8'h22, 8'h12, 8'hD1, 8'h21, 8'h30, 8'hD1, 8'h01, 8'h10, 8'h02, 8'hED, 8'hB2, 8'h22, 8'h14, 8'hD1, 8'h21, 8'h40, 8'hD1, 8'h01, 8'h10, 8'h01, 8'hED, 8'hAA, 8'h22, 8'h16, 8'hD1, 8'hC3, 8'h00, 8'h01};
localparam int EN = 27;
int  eaddr [EN] = '{'hD100, 'hD101, 'hD102, 'hD103, 'hD104, 'hD105, 'hD106, 'hD107, 'hD108, 'hD109, 'hD10A, 'hD10B, 'hD10C, 'hD10D, 'hD10E, 'hD10F, 'hD111, 'hD112, 'hD113, 'hD114, 'hD115, 'hD116, 'hD117, 'hD120, 'hD130, 'hD131, 'hD140};
logic [7:0] edata [EN] = '{8'h78, 8'h56, 8'h34, 8'h12, 8'h78, 8'h56, 8'hCD, 8'hAB, 8'h78, 8'h56, 8'hEF, 8'hBE, 8'h13, 8'h42, 8'h14, 8'h23, 8'h02, 8'h21, 8'hD1, 8'h32, 8'hD1, 8'h3F, 8'hD1, 8'h4A, 8'h4A, 8'h4A, 8'h4A};

int idx = 0, errors = 0, checked = 0, h = 0, stopc = 0;
bit arm = 0; logic pm1 = 0; string ev = "", prev = "";
logic [15:0] ea [$];                    // addresses of the R / W events of the case
logic [6:0] last_r = 0, case_r = 0; bit got_x = 0;

task automatic finish_case();
    string exp = expect_of(case_name[idx]);
    string got = {ev, $sformatf(" /%0d", h)};
    if (exp != "") begin
        checked++;
        if (got != {" ", exp}) begin
            errors++; $display("FAIL %s: bus %s, expected  %s", case_name[idx], got, exp);
        end
        if (case_name[idx] == "E3 EX (SP),HL" && ea.size() == 4 &&
            !(ea[1] == ea[0] + 16'd1 && ea[2] == ea[1] && ea[3] == ea[0])) begin
            errors++; $display("FAIL %s: addresses %04x %04x %04x %04x, expected SP, SP+1, SP+1, SP", case_name[idx], ea[0], ea[1], ea[2], ea[3]);
        end
        if (case_trig[idx] != 0 && got_x && case_r != last_r + 7'd1) begin
            errors++; $display("FAIL %s: R %02x after R %02x, expected one increment", case_name[idx], case_r, last_r);
        end
    end
endtask

always @(negedge clk) if (!reset) begin
    string kind;
    kind = "";
    if (~mreq_n && ~rd_n && ~m1_n) kind = "F";
    else if (~mreq_n && ~rd_n) kind = "R";
    else if (~mreq_n && ~wr_n) kind = "W";
    else if (~iorq_n && ~rd_n) kind = "I";
    else if (~iorq_n && ~wr_n) kind = "O";
    else if (~iorq_n && ~m1_n) kind = "A";
    else if (~mreq_n && ~rfsh_n) kind = "X";
    if (!ph) begin                      // low half: an M1 starts when M1 was not active one T before
        bit m1s = ~m1_n && !pm1;
        pm1 = ~m1_n;
        if (m1s && idx < N_CASES) begin
            bit again = 1;
            if (case_trig[idx] != 0 && !arm && int'(a) == case_trig[idx]) int_n = 0;
            while (again && idx < N_CASES) begin
                again = 0;
                if (!arm) begin
                    if (int'(a) == case_x[idx]) begin arm = 1; ev = ""; prev = ""; h = 0; ea.delete(); got_x = 0; end
                end else if (int'(a) == case_y[idx]) begin
                    finish_case();
                    idx++; arm = 0; again = 1;
                end
            end
        end
    end
    if (arm) begin
        if (kind != "" && kind != prev) begin
            ev = {ev, " ", kind, $sformatf("%0d", h)};
            if (kind == "R" || kind == "W") ea.push_back(a);
            if (kind == "X" && !got_x) begin case_r = a[6:0]; got_x = 1; end
        end
        prev = kind;
        h++;
    end else if (kind == "X") last_r = a[6:0];
    if (~iorq_n && ~m1_n) int_n = 1;
    stopc++;
    if (idx >= N_CASES - 2 || stopc > 3000000) begin
        for (int i = 0; i < EN; i++) if (mem[eaddr[i]] !== edata[i]) begin
            errors++; $display("FAIL result at %04x: %02x, expected %02x", eaddr[i], mem[eaddr[i]], edata[i]);
        end
        if (errors == 0 && checked >= 20 && idx >= N_CASES - 2) $display("PASS z80_bus_tb: %0d cases checked", checked);
        else $display("FAILED z80_bus_tb: %0d errors, %0d cases checked, stopped at case %0d", errors, checked, idx);
        $finish;
    end
end

initial begin
    string hex;
    if (!$value$plusargs("hex=%s", hex)) hex = "z80_timing.hex";
    $readmemh(hex, mem);
    for (int i = 0; i < FN; i++) mem[16'hA000 + i] = fprog[i];
    mem[1] = 8'h00; mem[2] = 8'hA0;                 // JP A000h first
    repeat (16) @(posedge clk); reset = 0;
end
endmodule
