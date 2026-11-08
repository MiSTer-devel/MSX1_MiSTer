module fdd_crc #( 
    parameter int CRC_WIDTH = 16, // Možnost volby 16 nebo 32 bitového CRC
    parameter logic [CRC_WIDTH-1:0] POLYNOM = 16'h1021 // Výchozí polynom
)(
    input  logic                  clk,
    input  logic [7:0]            data_in,
    input  logic                  valid,
    input  logic                  we,
    output logic [CRC_WIDTH-1:0]  crc
);

    logic [CRC_WIDTH-1:0] crc_reg;
    logic last_valid;

    initial begin
        crc_reg =  {CRC_WIDTH{1'b1}};
    end

    always_ff @(posedge clk) begin
        if (valid) begin
            if (we) begin
                crc_reg <= crc_next(crc_reg, data_in);
            end
        end else begin
            if (last_valid) begin
                crc_reg <=  {CRC_WIDTH{1'b1}};
                crc     <= crc_reg;    
            end
        end
        last_valid <= valid;
    end

    function logic [CRC_WIDTH-1:0] crc_next(logic [CRC_WIDTH-1:0] crc, logic [7:0] data);
        logic [CRC_WIDTH-1:0] new_crc;
        int i;
        
        new_crc = crc ^ ({{CRC_WIDTH-8{1'b0}}, data} << (CRC_WIDTH - 8));
        
        for (i = 0; i < 8; i = i + 1) begin
            if (new_crc[CRC_WIDTH-1]) begin
                new_crc = (new_crc << 1) ^ POLYNOM;
            end else begin
                new_crc = (new_crc << 1);
            end
        end
        
        return new_crc;
    endfunction

endmodule
