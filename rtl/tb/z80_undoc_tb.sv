// Undocumented flags of msx_cpu / TV80 against openMSX CPUCore.cc:
//   +memptr: MEMPTR (WZ) of the Z80, z80_memptr.asm (BIT 0,(HL) after each tested instruction:
//            flags Y / X = bits 13 / 11 of MEMPTR; expected high bytes in the program);
//   default: INI / IND / OUTI / OUTD flags and BIT flags, Z80 or R800 (+r800=1).
// Run: wsl.exe -- bash rtl/tb/run_z80_undoc.sh
module z80_undoc_tb;

logic clk = 0;
always #1 clk = ~clk;

clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

logic        reset = 1, r800 = 0;
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
    .r800_fast (2'd0),
    .r800_memdelay(2'd0),
    .cmos_z80  (1'b0),
    .vdp_io_wait(1'b0),
    .vdp_wr_hold(1'b0),
    .vdp_wr_wait(1'b0),
    .io_hold   (),
    .r800_active(),
    .bus_phase (),
    .bus_phase_next(),
    .acc_start (),
    .mem_free  (),
    .int_rq    (1'b0),
    .di        (di),
    .m1_n, .mreq_n, .iorq_n, .rd_n, .wr_n, .rfsh_n,
    .addr      (addr),
    .dout      (dout)
);

// I/O reads return a value of the port; each one is recorded for the expected flags
function automatic logic [7:0] io_in(input logic [15:0] a);
    return a[7:0] ^ a[15:8] ^ 8'h5A;
endfunction

logic [7:0] mem [0:65535];
assign di = (~mreq_n && ~rd_n) ? mem[addr] : (~iorq_n && ~rd_n && m1_n) ? io_in(addr) : 8'hFF;
always @(posedge clk) if (~mreq_n && ~wr_n) mem[addr] <= dout;

int         out_n = 0, in_n = 0;
logic [7:0] in_val [$];
logic       io_q = 0;
always @(posedge clk) begin
    io_q <= ~iorq_n && m1_n && (~wr_n || ~rd_n);
    if (~iorq_n && m1_n && ~wr_n && !io_q && addr[7:0] == 8'h34) out_n++;
    if (~iorq_n && m1_n && ~rd_n && !io_q) in_val.push_back(io_in(addr));
end

localparam logic [7:0] S = 8'h80, Z = 8'h40, Y = 8'h20, H = 8'h10, X = 8'h08, P = 8'h04, N = 8'h02, C = 8'h01;

int errors = 0, pc = 0;
task automatic emit(input logic [7:0] b); mem[pc] = b; pc++; endtask
task automatic emit16(input logic [15:0] w); emit(w[7:0]); emit(w[15:8]); endtask

// F before the tested instruction: LD DE,(00:f); PUSH DE; POP AF
task automatic set_f(input logic [7:0] f); emit(8'h11); emit(f); emit(8'h00); emit(8'hD5); emit(8'hF1); endtask
// F after: PUSH AF; POP DE; LD HL,res; LD (HL),E
task automatic save_f(input logic [15:0] res); emit(8'hF5); emit(8'hD1); emit(8'h21); emit16(res); emit(8'h73); endtask

// ---- block I/O cases
typedef struct { logic [7:0] op, b, c, l, val, f; } bio_t;
bio_t bio [$];

function automatic logic [7:0] exp_bio(input bio_t t, input logic [7:0] val);
    logic [7:0] b1 = t.b - 8'd1, add, f;
    logic [8:0] k;
    if (r800) return (t.f & ~(Z | N)) | (b1 == 0 ? Z : 8'h00) | N;
    add = (t.op[0] ? t.l : t.c) + (t.op[3] ? 8'hFF : 8'h01);
    k = {1'b0, val} + {1'b0, add};
    f = (b1 & (S | Y | X)) | (b1 == 0 ? Z : 8'h00) | (k[8] ? (H | C) : 8'h00) | (val[7] ? N : 8'h00);
    if (~^({5'd0, k[2:0]} ^ b1)) f |= P;
    return f;
endfunction

// ---- BIT cases: kind 0 BIT n,B; 1 BIT n,(HL); 2 BIT n,(IX+d) (IX + d = 2840h)
typedef struct { int kind; logic [2:0] n; logic [7:0] v, f; } bit_t;
bit_t bits [$];

function automatic logic [7:0] exp_bit(input bit_t t);
    logic set = t.v[t.n];
    logic [7:0] f = H | (set ? 8'h00 : Z);
    if (r800) return f | (t.f & (S | P | C | X | Y));
    f |= (t.f & C) | (set ? 8'h00 : P) | ((set && t.n == 3'd7) ? S : 8'h00);
    if (t.kind == 0) f |= t.v & (X | Y);
    if (t.kind == 2) f |= 8'h28 & (X | Y);          // high byte of IX + d
    return f;
endfunction

initial begin
    int t;
    bit memptr;
    if ($value$plusargs("r800=%d", t)) r800 = t[0];
    memptr = $test$plusargs("memptr");
    foreach (mem[i]) mem[i] = 8'h00;

    if (memptr) $readmemh("z80_memptr.hex", mem);
    else begin
        logic [7:0] ops [4] = '{8'hA2, 8'hAA, 8'hA3, 8'hAB};
        logic [7:0] bv [4] = '{8'h01, 8'h80, 8'h08, 8'h21};
        logic [7:0] cv [3] = '{8'h00, 8'hFF, 8'h7F};
        logic [7:0] fv [3] = '{8'h00, 8'hFF, 8'h7C};
        int i = 0;
        foreach (ops[o]) foreach (bv[b]) foreach (cv[c]) begin
            bio_t x;
            x.op = ops[o]; x.b = bv[b]; x.c = cv[c]; x.l = cv[(c + b) % 3] ^ 8'h80;
            x.val = 8'h3C + 8'(17 * i); x.f = fv[i % 3];
            bio.push_back(x); i++;
        end
        for (int n = 0; n < 8; n += 7)
            foreach (fv[f]) for (int k = 0; k < 3; k++) for (int s = 0; s < 2; s++) begin
                bit_t y;
                y.kind = k; y.n = 3'(n); y.f = fv[f];
                y.v = s ? (8'h28 | (8'h01 << n)) : (8'h28 & ~(8'h01 << n));
                bits.push_back(y);
            end

        emit(8'h31); emit16(16'hF000);                                  // LD SP,F000h
        emit(8'hDD); emit(8'h21); emit16(16'h2830);                     // LD IX,2830h
        foreach (bio[j]) begin
            emit(8'h21); emit16({8'h40, bio[j].l});                     // LD HL,40xxh
            emit(8'h36); emit(bio[j].val);                              // LD (HL),val (OUTI data)
            set_f(bio[j].f);
            emit(8'h01); emit16({bio[j].b, bio[j].c});                  // LD BC,bc
            emit(8'h21); emit16({8'h40, bio[j].l});                     // LD HL,40xxh
            emit(8'hED); emit(bio[j].op);
            save_f(16'hC000 + 16'(j));
        end
        foreach (bits[j]) begin
            case (bits[j].kind)
                0: begin emit(8'h06); emit(bits[j].v); end              // LD B,v
                1: begin emit(8'h21); emit16(16'h4100); emit(8'h36); emit(bits[j].v); end   // LD HL,4100h; LD (HL),v
                2: begin emit(8'h21); emit16(16'h2840); emit(8'h36); emit(bits[j].v); end   // IX + 10h
            endcase
            set_f(bits[j].f);
            case (bits[j].kind)
                0: begin emit(8'hCB); emit({2'b01, bits[j].n, 3'b000}); end                 // BIT n,B
                1: begin emit(8'h21); emit16(16'h4100); emit(8'hCB); emit({2'b01, bits[j].n, 3'b110}); end
                2: begin emit(8'hDD); emit(8'hCB); emit(8'h10); emit({2'b01, bits[j].n, 3'b110}); end
            endcase
            save_f(16'hC800 + 16'(j));
        end
        emit(8'hD3); emit(8'h34);                                       // OUT (34h),A
        emit(8'h76);                                                    // HALT
    end

    repeat (8) @(posedge clk); reset = 0;
    wait (out_n == 1);
    repeat (100) @(posedge clk);

    if (memptr) begin
        for (int j = 0; j < 40; j++) begin
            logic [7:0] f = mem[16'hC000 + j], e = mem[16'hC100 + j];
            if ((f & (X | Y)) !== (e & (X | Y))) begin
                errors++;
                $display("FAIL MEMPTR test %0d: Y X = %b %b, expected %b %b (MEMPTR %02hxxh)", j, f[5], f[3], e[5], e[3], e);
            end
        end
    end else begin
        if (in_val.size() != 2 * 4 * 3) $display("note: %0d I/O reads", in_val.size());
        begin
            int r = 0;
            foreach (bio[j]) begin
                logic [7:0] val = bio[j].op[0] ? bio[j].val : in_val[r];
                logic [7:0] e = exp_bio(bio[j], val), f = mem[16'hC000 + j];
                if (!bio[j].op[0]) r++;
                if (f !== e) begin
                    errors++;
                    $display("FAIL ED %02h B=%02h C=%02h L=%02h data=%02h F=%02h: F %02h, expected %02h",
                             bio[j].op, bio[j].b, bio[j].c, bio[j].l, val, bio[j].f, f, e);
                end
            end
        end
        foreach (bits[j]) begin
            logic [7:0] e = exp_bit(bits[j]), f = mem[16'hC800 + j], m;
            m = (!r800 && bits[j].kind == 1) ? ~(X | Y) : 8'hFF;   // Z80 (HL): X / Y = MEMPTR (+memptr)
            if ((f & m) !== (e & m)) begin
                errors++;
                $display("FAIL BIT %0d,%s v=%02h F=%02h: F %02h, expected %02h", bits[j].n,
                         bits[j].kind == 0 ? "B" : bits[j].kind == 1 ? "(HL)" : "(IX+d)", bits[j].v, bits[j].f, f, e);
            end
        end
    end
    if (errors == 0) $display("PASS z80_undoc_tb %s r800=%0d", memptr ? "memptr" : "flags", r800);
    else             $display("FAILED z80_undoc_tb %s r800=%0d: %0d errors", memptr ? "memptr" : "flags", r800, errors);
    $finish;
end

initial begin
    #20_000_000;
    $display("FAILED z80_undoc_tb: timeout");
    $finish;
end

endmodule
