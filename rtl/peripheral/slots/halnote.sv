module mapper_halnote
(
   input               clk,
   input               reset,
   input        [15:0] cpu_addr,
   input         [7:0] din,
   input               cpu_mreq,
   input               cpu_wr,
   input               cs,
   output              mem_unmaped,
   output       [24:0] mem_addr,
   output              sram_cs,
   output              sram_we
);

logic [7:0] subBank[2], bank[4];
logic       subMapperEnabled;
logic       sramEnabled;

always @(posedge clk) begin
   if (reset) begin
      subBank          <= '{default: '0};
      bank             <= '{default: '0};
      subMapperEnabled <= 1'b0;
      sramEnabled      <= 1'b0;
   end else begin
      if (cpu_addr[10:0] == 11'b111_1111_1111 & cpu_wr & cpu_mreq & cs) begin
         case (cpu_addr[15:11])
            5'b01110: begin subBank[0] <= din;                                         end
            5'b01111: begin subBank[1] <= din;                                         end
            5'b01001: begin bank[0]    <= {1'b0,din[6:0]}; sramEnabled      <= din[7]; end
            5'b01101: begin bank[1]    <= {1'b0,din[6:0]}; subMapperEnabled <= din[7]; end
            5'b10001: begin bank[2]    <= {1'b0,din[6:0]};                             end
            5'b10101: begin bank[3]    <= {1'b0,din[6:0]};                             end
            default: ;
         endcase
      end
   end
end

wire  [1:0] bank_num = {cpu_addr[15],cpu_addr[13]};
assign mem_addr = sram_cs                                    ? 25'(cpu_addr)                                           :
                  subMapperEnabled & cpu_addr[15:12] == 4'h7 ? 25'h80000 + 25'({subBank[cpu_addr[11]],cpu_addr[10:0]}) :
                                                               25'({bank[bank_num],cpu_addr[12:0]})                    ;
assign mem_unmaped = cs & (~^cpu_addr[15:14] & ~sram_cs);
assign sram_cs     = cs & sramEnabled & cpu_addr[15:14] == 2'b00;
assign sram_we     = sram_cs & cpu_wr & cpu_mreq;


endmodule