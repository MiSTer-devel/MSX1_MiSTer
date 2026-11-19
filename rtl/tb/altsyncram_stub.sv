// Simulation model of altsyncram as used by sys/sd_card.sv: two 8-bit ports, registered
// address, unregistered output (one clock read latency), same width on both ports.
module altsyncram #(
    parameter numwords_a = 2048, widthad_a = 11, width_a = 8,
    parameter numwords_b = 2048, widthad_b = 11, width_b = 8,
    parameter address_reg_b = "CLOCK1", clock_enable_input_a = "BYPASS", clock_enable_input_b = "BYPASS",
    parameter clock_enable_output_a = "BYPASS", clock_enable_output_b = "BYPASS", indata_reg_b = "CLOCK1",
    parameter intended_device_family = "Cyclone V", lpm_type = "altsyncram", operation_mode = "BIDIR_DUAL_PORT",
    parameter outdata_aclr_a = "NONE", outdata_aclr_b = "NONE", outdata_reg_a = "UNREGISTERED",
    parameter outdata_reg_b = "UNREGISTERED", power_up_uninitialized = "FALSE",
    parameter read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
    parameter read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
    parameter width_byteena_a = 1, width_byteena_b = 1, wrcontrol_wraddress_reg_b = "CLOCK1"
) (
    input                  clock0, clock1,
    input  [widthad_a-1:0] address_a,
    input  [width_a-1:0]   data_a,
    input                  wren_a,
    output [width_a-1:0]   q_a,
    input  [widthad_b-1:0] address_b,
    input  [width_b-1:0]   data_b,
    input                  wren_b,
    output [width_b-1:0]   q_b,
    input aclr0, aclr1, addressstall_a, addressstall_b, byteena_a, byteena_b,
    input clocken0, clocken1, clocken2, clocken3, rden_a, rden_b,
    output eccstatus
);
    reg [7:0] mem [0:2047];
    reg [widthad_a-1:0] ra;
    reg [widthad_b-1:0] rb;
    always @(posedge clock0) begin
        if (wren_a) mem[address_a] <= data_a;
        ra <= address_a;
    end
    always @(posedge clock1) begin
        if (wren_b) mem[address_b] <= data_b;
        rb <= address_b;
    end
    assign q_a = mem[ra];
    assign q_b = mem[rb];
    assign eccstatus = 1'b0;
endmodule
