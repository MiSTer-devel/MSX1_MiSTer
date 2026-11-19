// dev_tms CPU write test: VDP register and VRAM writes at every phase vs clk_en_10m7.
// Z80-like IO write (WR held ~1.5 T at 3.58 MHz), req pulse built as in msx.sv.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_tms.sh [alt_tms.sv]
module tms_tb;

logic clk = 0, rst = 1;
always #1 clk = ~clk;

clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

cpu_bus_if cpu_bus(clk, rst);
MSX::video_t video_bus;
vram_bus_if  vram_bus();
MSX::io_device_t io_device[3];

logic [15:0] addr = 0;
logic  [7:0] dout = 0;
logic        iorq = 0, wr = 0, iack = 0;
assign cpu_bus.addr = addr;
assign cpu_bus.data = dout;
assign cpu_bus.iorq = iorq;
assign cpu_bus.mreq = 0;
assign cpu_bus.m1   = 0;
assign cpu_bus.rd   = 0;
assign cpu_bus.wr   = wr;
assign cpu_bus.req  = iorq && wr && !iack;          // as msx.sv
always @(posedge clk) iack <= (iorq && wr) ? (iack | cpu_bus.req) : 1'b0;
assign vram_bus.q_lo = 8'h00;
assign vram_bus.q_hi = 8'h00;

wire [7:0] data;
wire       interrupt;
dev_tms dut (.cpu_bus(cpu_bus), .clock_bus(clock_bus), .video_bus(video_bus), .vram_bus(vram_bus),
             .io_device(io_device), .data(data), .interrupt(interrupt), .border(1'b0));

int vram_writes = 0;
logic [13:0] vram_last_addr;
logic  [7:0] vram_last_data;
always @(posedge clk) if (vram_bus.we_lo) begin
    vram_writes++;
    vram_last_addr = vram_bus.addr[13:0];
    vram_last_data = vram_bus.data;
end

task automatic cyc(input int n); repeat (n) @(posedge clk); #0.1; endtask

// OUT (port),value: IORQ+WR for 9 clk (1.5 T at 3.58 MHz), then idle
task automatic out(input logic [7:0] port, input logic [7:0] value, input int phase);
    cyc(phase);
    addr = {8'h00, port}; dout = value; iorq = 1; wr = 1;
    cyc(9);
    iorq = 0; wr = 0;
    cyc(12);
endtask

int errors = 0;

initial begin
    io_device[0] = '{mask: 8'hFE, port: 8'h98, param: 8'h00, mem_ref: '0, device_ref: '0, enable: 1'b1};
    io_device[1] = '{default: '0};
    io_device[2] = '{default: '0};
    cyc(20); rst = 0; cyc(20);

    for (int phase = 0; phase < 4; phase++) begin
        // Register write: value, then 80h | reg
        for (int r = 0; r < 8; r++) begin
            logic [7:0] v;
            v = 8'(8'h11 * (r + 1) + phase);
            out(8'h99, v, phase);
            out(8'h99, 8'h80 | 8'(r), phase);
            if (dut.tms_i.cpu_io_b.ctrl_reg_q[r] !== v) begin
                errors++;
                $display("FAIL phase=%0d reg%0d got=%02h exp=%02h", phase, r, dut.tms_i.cpu_io_b.ctrl_reg_q[r], v);
            end
        end
        // VRAM write: address 0x1234 (write mode), then data
        begin
            int w0;
            w0 = vram_writes;
            out(8'h99, 8'h34, phase);
            out(8'h99, 8'h40 | 8'h12, phase);
            out(8'h98, 8'hA5 ^ 8'(phase), phase);
            cyc(200);                               // VRAM access slot
            if (vram_writes == w0 || vram_last_addr !== 14'h1234 || vram_last_data !== (8'hA5 ^ 8'(phase))) begin
                errors++;
                $display("FAIL phase=%0d vram writes=%0d addr=%04h data=%02h", phase, vram_writes - w0, vram_last_addr, vram_last_data);
            end
        end
    end

    if (errors == 0) $display("PASS tms_tb");
    else             $display("FAILED tms_tb: %0d errors", errors);
    $finish;
end

endmodule
