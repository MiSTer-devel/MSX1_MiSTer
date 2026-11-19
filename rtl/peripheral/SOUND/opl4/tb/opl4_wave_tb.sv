// opl4_wave against the reference model (opl4_wave_gold.py): register accesses of a scenario,
// every sample (left, right) and every value read back must match.
//   +dir=<mem.bin, scen.txt, expect.txt>
//   +free: sample ticks every 487 clk whatever the memory does; checks that the engine keeps
//          running and never writes the ROM. +slow=<clk>: answer time of the memory.
//          +max_late=<n>: at most n tone samples computed with samples of an older position
`timescale 1ns/1ps
module opl4_wave_tb;
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;

    logic        smp_tick = 0, reg_wr = 0, reg_rd = 0;
    logic  [7:0] reg_addr = 0, reg_wdata = 0;
    wire   [7:0] reg_rdata;
    wire         busy, mem_req, mem_we, mem_ack_w, out_valid, idle, late;
    wire  [21:0] mem_addr;
    wire   [7:0] mem_wdata;
    wire signed [20:0] out_l, out_r;
    wire   [5:0] mix_fm;
    logic        mem_ack = 0;
    logic [15:0] mem_rdata;

    opl4_wave dut (.clk, .reset, .smp_tick, .ram_chunks(5'd16),
                   .reg_wr, .reg_rd, .reg_addr, .reg_wdata, .reg_rdata, .busy, .mix_fm,
                   .mem_req, .mem_we, .mem_addr, .mem_wdata, .mem_ack, .mem_rdata,
                   .out_l, .out_r, .out_valid, .late, .idle);

    // sample memory: answers after a random delay
    byte unsigned mem [4194304];
    int  fails = 0, reads = 0, writes = 0, slow = 0, lates = 0, max_late = -1;
    always @(posedge clk) if (late) lates++;
    bit  free_run = 0;
    always @(posedge clk) begin
        mem_ack <= 0;
        if (mem_req && !mem_ack) begin
            int d;
            d = free_run ? slow : $urandom_range(0, 3);
            repeat (d) @(posedge clk);
            if (mem_we) begin
                writes++;
                if (mem_addr < 22'h200000) begin fails++; $display("FAIL write into the ROM %h", mem_addr); end
                mem[mem_addr] = mem_wdata;
            end else reads++;
            mem_rdata <= {mem[mem_addr | 22'd1], mem[mem_addr & ~22'd1]};
            mem_ack   <= 1;
            @(posedge clk);
        end
    end

    task automatic reg_write(input [7:0] a, input [7:0] d);
        while (busy) @(posedge clk);
        reg_addr <= a; reg_wdata <= d; reg_wr <= 1;
        @(posedge clk);
        reg_wr <= 0;
        @(posedge clk);
    endtask
    task automatic reg_read(input [7:0] a, input [7:0] exp, input int frame);
        while (busy) @(posedge clk);
        reg_addr <= a;
        repeat (2) @(posedge clk);
        if (!free_run && reg_rdata !== exp) begin
            fails++;
            if (fails < 20) $display("FAIL frame %0d read register %h: %h, expected %h", frame, a, reg_rdata, exp);
        end
        reg_rd <= 1;
        @(posedge clk);
        reg_rd <= 0;
        @(posedge clk);
    endtask

    string dir;
    int    fs, fe, fm, n, frame = 0, nf = 0, loud = 0, sf, sk, sr, sv, el, er, got;
    initial begin
        if (!$value$plusargs("dir=%s", dir)) dir = ".";
        free_run = $test$plusargs("free");
        void'($value$plusargs("slow=%d", slow));
        void'($value$plusargs("max_late=%d", max_late));
        fm = $fopen({dir, "/mem.bin"}, "rb");
        n  = $fread(mem, fm);
        $fclose(fm);
        fs = $fopen({dir, "/scen.txt"}, "r");
        fe = $fopen({dir, "/expect.txt"}, "r");
        repeat (5) @(posedge clk);
        reset = 0;
        @(posedge clk);
        while (!idle) @(posedge clk);
        got = $fscanf(fs, "%d %d %d %d", sf, sk, sr, sv);
        while ($fscanf(fe, "%d %d", el, er) == 2) begin
            while (got == 4 && sf == frame) begin
                if (sk) reg_write(sr[7:0], sv[7:0]); else reg_read(sr[7:0], sv[7:0], frame);
                got = $fscanf(fs, "%d %d %d %d", sf, sk, sr, sv);
            end
            if (free_run) begin
                repeat (400) @(posedge clk);
            end else while (!idle) @(posedge clk);
            smp_tick <= 1;
            @(posedge clk);
            smp_tick <= 0;
            begin
                int t;
                t = 0;
                while (!out_valid && t < 2000) begin @(posedge clk); t++; end
                if (!out_valid) begin fails++; if (fails < 20) $display("FAIL frame %0d: no output", frame); end
            end
            if (out_l != 0 || out_r != 0) loud++;
            if (!free_run && (out_l !== 21'(el) || out_r !== 21'(er))) begin
                fails++;
                if (fails < 20) $display("FAIL frame %0d: %0d %0d, expected %0d %0d", frame, out_l, out_r, el, er);
            end
            frame++;
        end
        $display("%0d samples (%0d with sound), %0d memory reads, %0d writes, %0d tone samples late", frame, loud, reads, writes, lates);
        if (!free_run && lates != 0) begin fails++; $display("FAIL tones computed with old samples: %0d", lates); end
        if (max_late >= 0 && lates > max_late) begin fails++; $display("FAIL %0d late tone samples, at most %0d expected", lates, max_late); end
        if (fails == 0 && frame > 0 && loud > 0) $display("PASS opl4_wave_tb%s", free_run ? " (free running)" : "");
        else $display("FAILED opl4_wave_tb: %0d", fails);
        $finish;
    end
endmodule
