// mapper_mirror exhaustive test: all pages x offsets x rom_size[15:0] against reference %.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_mirror.sh [alt_mirror.sv]
module mirror_tb;

logic clk = 0, rst = 0;
cpu_bus_if cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_mirror dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out));

logic [15:0] addr;
logic        mreq, rd, wr;
assign cpu_bus.addr = addr;
assign cpu_bus.mreq = mreq;
assign cpu_bus.rd   = rd;
assign cpu_bus.wr   = wr;

int errors = 0, checked = 0;

function automatic logic [2:0] ref_prefix(input logic [15:0] rom, input logic [2:0] page, input logic [1:0] ofs);
    int bc, s;
    bc = (int'(rom) + 8191) / 8192;            // 0 when rom_size[15:0] == 0 (64 KB)
    s  = int'(page) + 2 * int'(ofs);
    return (bc == 0) ? 3'(s % 8) : 3'(s % bc);
endfunction

initial begin
    block_info.typ        = MAPPER_MIRROR;
    block_info.device_ref = '0;
    block_info.sram_size  = '0;
    block_info.base_ram   = '0;
    block_info.id         = '0;
    mreq = 1; rd = 1; wr = 0;

    for (int rom = 0; rom < 65536; rom++) begin
        block_info.rom_size = 25'(rom);
        for (int ofs = 0; ofs < 4; ofs++) begin
            block_info.offset_ram = 2'(ofs);
            for (int page = 0; page < 8; page++) begin
                addr = {3'(page), 13'h0A5A};
                #1;
                checked++;
                if (out.addr !== {11'b0, ref_prefix(16'(rom), 3'(page), 2'(ofs)), 13'h0A5A} || out.ram_cs !== 1'b1) begin
                    errors++;
                    if (errors <= 10)
                        $display("FAIL rom=%05h ofs=%0d page=%0d got=%07h exp_prefix=%0d",
                                 rom, ofs, page, out.addr, ref_prefix(16'(rom), 3'(page), 2'(ofs)));
                end
            end
        end
    end

    // Write: rnw low; other mapper type: inactive output
    rd = 0; wr = 1; block_info.rom_size = 25'h4000; #1;
    if (out.rnw !== 1'b0 || out.ram_cs !== 1'b1) begin errors++; $display("FAIL write rnw=%b cs=%b", out.rnw, out.ram_cs); end
    block_info.typ = MAPPER_OFFSET; #1;
    if (out.ram_cs !== 1'b0 || out.addr !== '1 || out.rnw !== 1'b1) begin
        errors++; $display("FAIL inactive cs=%b addr=%07h rnw=%b", out.ram_cs, out.addr, out.rnw);
    end
    block_info.typ = MAPPER_MIRROR; mreq = 0; #1;
    if (out.ram_cs !== 1'b0) begin errors++; $display("FAIL no mreq cs=%b", out.ram_cs); end

    if (errors == 0) $display("PASS mirror_tb (%0d combinations)", checked);
    else             $display("FAILED mirror_tb: %0d errors of %0d", errors, checked);
    $finish;
end

endmodule
