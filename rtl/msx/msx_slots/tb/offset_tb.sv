// mapper_offset: linear memory of a block. mapper_param[0] = 1: an 8 kB memory in the upper
// half of the page (Casio PV-7: 8 kB RAM at E000-FFFF, C000-DFFF unmapped as in openMSX).
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_offset.sh
module offset_tb;

logic clk = 0, reset = 0;
cpu_bus_if cpu_bus(clk, reset);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

logic [15:0] addr;
logic        rd, wr;
assign cpu_bus.addr   = addr;
assign cpu_bus.data   = 8'h00;
assign cpu_bus.mreq   = rd | wr;
assign cpu_bus.iorq   = 1'b0;
assign cpu_bus.rd     = rd;
assign cpu_bus.wr     = wr;
assign cpu_bus.m1     = 1'b0;
assign cpu_bus.req    = rd | wr;
assign cpu_bus.halt   = 1'b0;
assign cpu_bus.rfsh   = 1'b0;
assign cpu_bus.int_rq = 1'b0;

mapper_offset dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out));

int errors = 0;

task automatic check(input string name, input logic [15:0] a, input logic w,
                     input logic exp_cs, input logic [26:0] exp_addr);
    addr = a; rd = !w; wr = w;
    #1;
    if (out.ram_cs !== exp_cs || (exp_cs && (out.addr !== exp_addr || out.rnw !== !w))) begin
        $display("FAIL %s: %h %s -> cs %b addr %h rnw %b, expected cs %b addr %h", name, a,
                 w ? "wr" : "rd", out.ram_cs, out.addr, out.rnw, exp_cs, exp_addr);
        errors++;
    end
    rd = 0; wr = 0; #1;
endtask

initial begin
    block_info = '0;
    block_info.typ = MAPPER_OFFSET;
    rd = 0; wr = 0; addr = '0;

    // 16 kB page 3, as before
    block_info.rom_size = 25'h4000;
    check("16 kB C000",       16'hC000, 0, 1, 27'h0000);
    check("16 kB DFFF",       16'hDFFF, 1, 1, 27'h1FFF);
    check("16 kB E000",       16'hE000, 0, 1, 27'h2000);
    check("16 kB FFFF",       16'hFFFF, 1, 1, 27'h3FFF);

    // 8 kB, lower half (mapper_param 0): C000-DFFF only
    block_info.rom_size = 25'h2000;
    check("8 kB low C000",    16'hC000, 0, 1, 27'h0000);
    check("8 kB low E000",    16'hE000, 0, 0, 27'h0000);

    // 8 kB, upper half (mapper_param[0]): E000-FFFF -> 0000-1FFF, C000-DFFF unmapped
    block_info.mapper_param = 2'b01;
    check("8 kB high C000",   16'hC000, 0, 0, 27'h0000);
    check("8 kB high DFFF",   16'hDFFF, 1, 0, 27'h0000);
    check("8 kB high E000",   16'hE000, 0, 1, 27'h0000);
    check("8 kB high F380",   16'hF380, 1, 1, 27'h1380);
    check("8 kB high FFFF",   16'hFFFF, 0, 1, 27'h1FFF);
    check("8 kB high page 1", 16'h6000, 0, 1, 27'h0000);   // any page: upper 8 kB of it

    if (errors == 0) $display("PASS offset_tb");
    else             $display("FAIL offset_tb (%0d)", errors);
    $finish;
end

endmodule
