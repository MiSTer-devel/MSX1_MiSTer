// TV80a with /WAIT from C++ for tb_wait.cpp (from the Sord M5 core): a test loop in ROM,
// a zero flag in RAM. CPU clock is clk/6 as in rtl/clock.sv.
module tb_wait (
   input  logic        clk,
   input  logic        rst_n,
   input  logic        wait_n,
   input  logic        io_loop,     // 1 = loop with IN A,(30h) (46 T)
   output logic        m1_n,
   output logic [15:0] addr,
   output logic        ce_p
);
   logic [2:0] div6 = '0;
   always_ff @(posedge clk) div6 <= (div6 == 3'd5) ? 3'd0 : div6 + 3'd1;
   assign ce_p = (div6 == 3'd0);
   wire ce_n = (div6 == 3'd3);

   logic [15:0] A;
   logic [7:0]  DO, DI;
   logic        MREQ_n, IORQ_n, RD_n, WR_n;

   TV80a #(.Mode(0), .R800_MULU(0), .IOWait(1)) cpu (
      .RESET_n(rst_n), .R800_mode(1'b0), .CLK(clk), .CE_p(ce_p), .CE_n(ce_n),
      .WAIT_n(wait_n), .INT_n(1'b1), .NMI_n(1'b1), .BUSRQ_n(1'b1),
      .M1_n(m1_n), .MREQ_n(MREQ_n), .IORQ_n(IORQ_n), .RD_n(RD_n), .WR_n(WR_n),
      .RFSH_n(), .HALT_n(), .BUSAK_n(), .A(A), .DI(DI), .DO(DO),
      .MC(), .TS(), .IntCycle_n(), .REG(), .DIRSet(1'b0), .DIR('0)
   );
   assign addr = A;

   // 0000 LD HL,0 / 0003 INC HL / LD A,(8000h) / OR A / JR Z,0003
   // io_loop: 0003 INC HL / IN A,(30h) / LD A,(8000h) / OR A / JR Z,0003
   always_comb
      if (io_loop)
         case (A)
            16'h0000: DI = 8'h21; 16'h0001: DI = 8'h00; 16'h0002: DI = 8'h00;
            16'h0003: DI = 8'h23;
            16'h0004: DI = 8'hDB; 16'h0005: DI = 8'h30;
            16'h0006: DI = 8'h3A; 16'h0007: DI = 8'h00; 16'h0008: DI = 8'h80;
            16'h0009: DI = 8'hB7;
            16'h000A: DI = 8'h28; 16'h000B: DI = 8'hF7;
            default:  DI = 8'h00;
         endcase
      else
      case (A)
         16'h0000: DI = 8'h21; 16'h0001: DI = 8'h00; 16'h0002: DI = 8'h00;
         16'h0003: DI = 8'h23;
         16'h0004: DI = 8'h3A; 16'h0005: DI = 8'h00; 16'h0006: DI = 8'h80;
         16'h0007: DI = 8'hB7;
         16'h0008: DI = 8'h28; 16'h0009: DI = 8'hF9;
         default:  DI = 8'h00;
      endcase
endmodule
