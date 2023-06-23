module kanji
(
   input         clk,
   input         reset,
   input   [7:0] din,
   input   [7:0] addr,
   input         cpu_wr,
   input         cpu_rd,
   input         cpu_iorq,
   input         cs,
   input  [26:0] base_ram,
   input  [15:0] rom_size,
   output [26:0] mem_addr,
   output        ram_ce
);

logic [26:0] addr1, addr2;

wire kanji_en = cpu_iorq & addr[7:2] == 6'b1101_10;

assign mem_addr = base_ram + (addr[1] ? addr2 : addr1);
assign ram_ce   = cs & addr[0] & cpu_rd & kanji_en & (rom_size == 16'd16 | ~addr[1]);

always @(posedge clk) begin
   logic last_ce;
   if (reset) begin
      addr1 <= 27'h00000;
      addr2 <= 27'h20000;
   end else begin
      if (kanji_en) begin
         if (cpu_wr) begin
            case (addr[1:0])
               2'd0: addr1 <= (addr1 & 27'h1f800) | ((27'(din) & 27'h3f) << 5 );
               2'd1: addr1 <= (addr1 & 27'h007e0) | ((27'(din) & 27'h3f) << 11);
               2'd2: addr2 <= (addr2 & 27'h3f800) | ((27'(din) & 27'h3f) << 5 );
               2'd3: addr2 <= (addr2 & 27'h207e0) | ((27'(din) & 27'h3f) << 11);
            endcase
         end
      end
      if (last_ce & ~ram_ce) begin 
         if (addr[1])
            addr2 <= (addr2 & ~27'h1f) | ((addr2 + 27'd1) & 27'h1f);
         else
            addr1 <= (addr1 & ~27'h1f) | ((addr1 + 27'd1) & 27'h1f);
      end
      last_ce <= ram_ce;
   end
end

endmodule