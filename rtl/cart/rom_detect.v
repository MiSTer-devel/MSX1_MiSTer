module rom_detect
(
    input             clk,
    input             ioctl_isROM,
    input      [26:0] ioctl_addr,
    input       [7:0] ioctl_dout,
    input             ioctl_wr,
    output      [5:0] mapper,
    output      [3:0] offset,
    output reg [24:0] rom_size
);

reg last_isROM;
reg [7:0]  head  [0:7];
reg [7:0]  head2 [0:7];
reg signed [15:0] asc16, asc8, kon4, kon5;
//reg game1, game2;

always @(posedge clk) begin
    last_isROM = ioctl_isROM;
end

always @(posedge clk) begin
reg [7:0] a0,a1,a2;

    if (ioctl_isROM && ~last_isROM) begin
        asc16 <= 0;
        asc8  <= 0;
        kon4  <= 0;
        kon5  <= 0;
        //game1 <= 0;
        //game2 <= 0;
        a0    <= 0;
        a1    <= 0;
        a2    <= 0;
    end
    if (ioctl_wr) begin
        rom_size <= ioctl_addr[24:0];
        if (ioctl_addr[26:7] == 0) begin
            if (ioctl_addr[5:3] == 0) begin
                if (ioctl_addr[6] == 0) begin
                        head  [ioctl_addr[2:0]] <= ioctl_dout;
                        head2 [ioctl_addr[2:0]] <= 0;
                end else begin
                        head2[ioctl_addr[2:0]] <= ioctl_dout;
                end
            end
            //if (ioctl_addr[6:1] == 6'b001000) begin
                //if (ioctl_addr[0] == 0 && ioctl_dout == "Y")
                //        game1 <= 1;
                //if (ioctl_addr[0] == 1 && ioctl_dout == "Z")
                //        game2 <= 1;
            //end
        end
        a0 <= a1;
        a1 <= a2;
        a2 <= ioctl_dout;
        if (ioctl_addr > 2)	begin
            if (a0 == 8'h32 && a1 == 0) begin
                case (a2)
                        8'h60,
                        8'h70: begin
                            asc16 <= asc16 + 1'd1;
                            asc8 <= asc8 + 1'd1;
                        end
                        8'h68,
                        8'h78: begin
                            asc8 <= asc8 + 1'd1;
                            asc16 <= asc16 - 1'd1;
                        end
                endcase
                case (a2)
                        8'h60,
                        8'h80,
                        8'ha0: begin
                            kon4 <= kon4 + 1'd1;
                        end
                        8'h50,
                        8'h70,
                        8'h90,
                        8'hb0: begin
                            kon5 <= kon5 + 1'd1;
                        end
                endcase
            end
        end
    end
end

wire [15:0] kon    = kon4 > kon5 ? kon4 : kon5;
wire [15:0] ascii  = asc8 > asc16 ? asc8 : asc16;
assign      mapper = rom_size < 25'h2000                        ? MAPPER_NO_UNKNOWN                 :
                     rom_size < 25'h10000                       ? MAPPER_NO_UNKNOWN                 :
   //                  game1 && game2 && rom_size > 25'h18000     ? MAPPER_GM2                        :
                     kon > ascii                                ? (kon5 > kon4  ? MAPPER_KONAMI_SCC : 
                                                                                  MAPPER_KONAMI)    :
                                                                  (asc8 > asc16 ? MAPPER_ASCII8     : 
                                                                                  MAPPER_ASCII16)   ;
wire [15:0] start = head[3] << 8 | head[2];
wire [15:0] start4000 = head2[3] << 8 | head2[2];
wire romSig_at_0000 = head [0] == "A" && head [1] == "B";
wire romSig_at_4000 = head2[0] == "A" && head2[1] == "B";

wire [3:0] start_1 = start == 0 ?  ((head[5] & 8'hC0) != 8'h40 ? 4'h8 : 4'h4) : ((start & 16'hC000) == 16'h8000 ? 4'h8 : 4'h4);
wire [3:0] start_2 = (~romSig_at_0000 && romSig_at_4000) ? ((start4000 == 0 && (head2[5] & 8'hC0) == 8'h40) || start4000 < 16'h8000 || start4000 >= 16'hC000) ? 4'h0 : 4'h4 : 4'h4;
wire [3:0] start_3 = (~(romSig_at_0000 && ~romSig_at_4000)) ? 4'h0 : 4'h4;
assign offset = rom_size == 16'h1000 ? start_1 :
                rom_size == 16'h2000 ? start_1 :
                rom_size == 16'h4000 ? start_1 :
                rom_size == 16'h8000 ? start_2 :
                rom_size == 16'hC000 ? start_3 :
                                       4'h0;
endmodule
