// Simulation model of the dpram entity (rtl/peripheral/bram.vhd): registered read, both ports.
module dpram #(parameter addr_width = 8, data_width = 8, mem_init_file = " ", mem_name = "MEM") (
    input                   clock,
    input  [addr_width-1:0] address_a,
    input  [data_width-1:0] data_a,
    input                   wren_a,
    output reg [data_width-1:0] q_a,
    input  [addr_width-1:0] address_b,
    input  [data_width-1:0] data_b,
    input                   wren_b,
    output reg [data_width-1:0] q_b
);
    reg [data_width-1:0] mem [0:(1<<addr_width)-1];
    always @(posedge clock) begin
        if (wren_a) mem[address_a] <= data_a;
        q_a <= mem[address_a];
    end
    always @(posedge clock) begin
        if (wren_b) mem[address_b] <= data_b;
        q_b <= mem[address_b];
    end
endmodule
