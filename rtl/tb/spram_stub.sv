// Simulation model of the spram entity (rtl/peripheral/bram.vhd): registered read.
module spram #(parameter addr_width = 8, data_width = 8, mem_init_file = " ", mem_name = "MEM") (
    input                       clock,
    input      [addr_width-1:0] address,
    input      [data_width-1:0] data,
    input                       wren,
    output reg [data_width-1:0] q
);
    reg [data_width-1:0] mem [0:(1<<addr_width)-1];
    always @(posedge clock) begin
        if (wren) mem[address] <= data;
        q <= mem[address];
    end
endmodule
