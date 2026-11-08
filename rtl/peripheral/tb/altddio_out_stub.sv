// Simulation stub of the Altera altddio_out primitive (as used by sdram.sv for SDRAM_CLK).
module altddio_out #(
    parameter extend_oe_disable = "OFF", intended_device_family = "", invert_output = "OFF",
              lpm_hint = "UNUSED", lpm_type = "altddio_out", oe_reg = "UNREGISTERED",
              power_up_high = "OFF", width = 1
)(
    input  [width-1:0] datain_h, datain_l,
    input              outclock, aclr, aset, oe, outclocken, sclr, sset,
    output [width-1:0] dataout
);
    assign dataout = outclock ? datain_h : datain_l;
endmodule
