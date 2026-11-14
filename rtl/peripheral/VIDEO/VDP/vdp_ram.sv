module RAM (
  input  logic [7:0] ADR,
  input  logic CLK,
  input  logic WE,
  input  logic [7:0] DBO,
  output logic [7:0] DBI
);

  logic [7:0] blkram [255:0];
  logic [7:0] iADR;

  always_ff @(posedge CLK) begin
    if (WE) begin
      blkram[ADR] <= DBO;
    end
    iADR <= ADR;
  end

  assign DBI = blkram[iADR];

endmodule

module PALETE_RAM (
  input  logic [7:0] ADR,
  input  logic CLK,
  input  logic WE,
  input  logic [8:0] DBO,
  output logic [8:0] DBI,
  input  logic RESET
);

  logic [8:0] blkram [255:0];
  logic [7:0] iADR;

  always_ff @(posedge CLK) begin
    if (RESET) begin
        blkram[0]  <= 9'h000;
        blkram[1]  <= 9'h000;
        blkram[2]  <= 9'h071;
        blkram[3]  <= 9'h0FB;
        blkram[4]  <= 9'h04F;
        blkram[5]  <= 9'h09F;
        blkram[6]  <= 9'h149;
        blkram[7]  <= 9'h0B7;
        blkram[8]  <= 9'h1C9;
        blkram[9]  <= 9'h1DB;
        blkram[10] <= 9'h1B1;
        blkram[11] <= 9'h1B4;
        blkram[12] <= 9'h061;
        blkram[13] <= 9'h195;
        blkram[14] <= 9'h16D;
        blkram[15] <= 9'h1FF;
    end else if (WE) begin
      blkram[ADR] <= DBO;
    end
    iADR <= ADR;
  end

  assign DBI = blkram[iADR];

endmodule
// sprite line buffer: one read and one write port (a read of the address written in the
// same clock returns the old content; the sprite module forwards the new one itself)
module VDP_LINEBUF (
  input  logic CLK,
  input  logic [7:0] RADR,
  output logic [7:0] Q,
  input  logic WE,
  input  logic [7:0] WADR,
  input  logic [7:0] D
);

  logic [7:0] blkram [255:0];

  always_ff @(posedge CLK) begin
    if (WE) begin
      blkram[WADR] <= D;
    end
    Q <= blkram[RADR];
  end

endmodule
