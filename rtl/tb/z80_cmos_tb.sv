// CPU variants of msx_cpu / TV80 that software can tell apart (openMSX CPUCore.cc):
//   - NMOS Z80:  SCF / CCF take X and Y from F | A; OUT (C),0 writes 00h;
//   - CMOS Z80 (cmos_z80, Toshiba MSX-Engine): SCF / CCF keep Y, X from F | A; OUT (C),0 writes FFh;
//   - R800 (+r800): SCF / CCF keep X and Y, CCF keeps H.
// Program: for every (A, F) pair and SCF / CCF: LD BC,AF; PUSH BC; POP AF; op; PUSH AF; POP HL;
// LD (res),HL; then LD BC,1234h; OUT (C),0; HALT.
// Plusargs: +cmos=1, +r800=1. Run: wsl.exe -- bash rtl/tb/run_z80_cmos.sh
module z80_cmos_tb;

logic clk = 0;
always #1 clk = ~clk;

clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

logic        reset = 1, is_cmos = 0, r800 = 0;
logic        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
logic [15:0] addr;
logic  [7:0] dout, di;

msx_cpu dut (
    .clock_bus (clock_bus.base_mp),
    .reset     (reset),
    .clock_sel (2'd0),
    .m1_wait   (3'd1),
    .mem_wait  (4'd0),
    .io_wait   (4'd0),
    .ext_wait  (1'b0),
    .r800      (r800),
    .r800_sel  (1'b0),
    .cmos_z80  (is_cmos),
    .vdp_io_wait(1'b0),
    .vdp_wr_hold(1'b0),
    .vdp_wr_wait(1'b0),
    .io_hold   (),
    .cold_reset(reset),
    .r800_active(),
    .bus_phase (),
    .int_rq    (1'b0),
    .di        (di),
    .m1_n, .mreq_n, .iorq_n, .rd_n, .wr_n, .rfsh_n,
    .addr      (addr),
    .dout      (dout)
);

logic [7:0] mem [0:65535];
assign di = (~mreq_n && ~rd_n) ? mem[addr] : 8'hFF;
always @(posedge clk) if (~mreq_n && ~wr_n) mem[addr] <= dout;

int         out_n = 0;
logic [7:0] out_data = 8'hxx;
logic       io_q = 0;
always @(posedge clk) begin
    io_q <= ~iorq_n && ~wr_n;
    if (~iorq_n && ~wr_n && !io_q && addr[7:0] == 8'h34) begin out_n++; out_data <= dout; end
end

localparam int N = 9;
localparam logic [7:0] A_V [N] = '{8'h00, 8'hFF, 8'h00, 8'h28, 8'h00, 8'h08, 8'h20, 8'hD7, 8'h28};
localparam logic [7:0] F_V [N] = '{8'h00, 8'h00, 8'h28, 8'h00, 8'hFF, 8'h20, 8'h08, 8'h11, 8'hD7};
localparam logic [7:0] S = 8'h80, Z = 8'h40, Y = 8'h20, H = 8'h10, X = 8'h08, P = 8'h04, C = 8'h01;

function automatic logic [7:0] exp_f(input logic ccf, input logic [7:0] a, input logic [7:0] f);
    logic [7:0] r;
    if (!ccf) begin                                 // SCF
        if (r800)      r = C | (f & (S | Z | P | X | Y));
        else if (is_cmos) r = C | (f & (S | Z | P | Y)) | ((f | a) & X);
        else           r = C | (f & (S | Z | P)) | ((f | a) & (X | Y));
    end else begin
        if (r800)      r = f & (S | Z | P | C | X | Y | H);
        else if (is_cmos) r = (f & (S | Z | P | C | Y)) | ((f & C) << 4) | ((f | a) & X);
        else           r = (f & (S | Z | P | C)) | ((f & C) << 4) | ((f | a) & (X | Y));
        r ^= C;
    end
    return r;
endfunction

int errors = 0, pc = 0;
task automatic emit(input logic [7:0] b); mem[pc] = b; pc++; endtask

initial begin
    int t, res;
    logic [7:0] f, e;
    if ($value$plusargs("cmos=%d", t)) is_cmos = t[0];
    if ($value$plusargs("r800=%d", t)) r800 = t[0];
    foreach (mem[i]) mem[i] = 8'h00;
    emit(8'h31); emit(8'h00); emit(8'hF0);          // LD SP,F000h
    for (int i = 0; i < 2 * N; i++) begin
        res = 16'hC000 + 2 * i;
        emit(8'h01); emit(F_V[i / 2]); emit(A_V[i / 2]);    // LD BC,AF
        emit(8'hC5); emit(8'hF1);                   // PUSH BC; POP AF
        emit(i[0] ? 8'h3F : 8'h37);                 // CCF / SCF
        emit(8'hF5); emit(8'hE1);                   // PUSH AF; POP HL
        emit(8'h22); emit(res[7:0]); emit(res[15:8]);       // LD (res),HL
    end
    emit(8'h01); emit(8'h34); emit(8'h12);          // LD BC,1234h
    emit(8'hED); emit(8'h71);                       // OUT (C),0
    emit(8'h76);                                    // HALT
    repeat (8) @(posedge clk); reset = 0;
    wait (out_n == 1);
    repeat (100) @(posedge clk);
    for (int i = 0; i < 2 * N; i++) begin
        f = mem[16'hC000 + 2 * i];
        e = exp_f(i[0], A_V[i / 2], F_V[i / 2]);
        if (mem[16'hC001 + 2 * i] !== A_V[i / 2]) begin errors++; $display("FAIL case %0d: A changed", i); end
        if (f !== e) begin
            errors++;
            $display("FAIL %s A=%02h F=%02h: F %02h, expected %02h", i[0] ? "CCF" : "SCF", A_V[i / 2], F_V[i / 2], f, e);
        end
    end
    e = is_cmos ? 8'hFF : 8'h00;
    if (out_data !== e) begin errors++; $display("FAIL OUT (C),0 wrote %02h, expected %02h", out_data, e); end
    if (errors == 0) $display("PASS z80_cmos_tb cmos=%0d r800=%0d", is_cmos, r800);
    else             $display("FAILED z80_cmos_tb cmos=%0d r800=%0d: %0d errors", is_cmos, r800, errors);
    $finish;
end

initial begin
    #2_000_000;
    $display("FAILED z80_cmos_tb: timeout");
    $finish;
end

endmodule
