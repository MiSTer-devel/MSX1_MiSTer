// S1990 system timer (MSX turbo R, OCM): 16-bit free-running counter, one tick per
// 3.911 us (3.58 MHz / 14 = clk_core / 84). Read: E6h low byte, E7h high byte.
// A write to either port clears the counter, the prescaler phase is kept (openMSX
// MSXE6Timer, verified on a turbo R; OCM systemtimer.vhd ignores writes).
module dev_systimer (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::io_device_t io_device[3],       // single instance: [0]
    output            [7:0] data
);

    localparam int DIV = MSX::CLK_CORE_HZ * 14 / 3579545;   // 84

    wire cs = io_device[0].enable && cpu_bus.iorq && ~cpu_bus.m1
              && (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;

    logic  [6:0] prescaler;
    logic [15:0] counter;
    wire         tick = prescaler == 7'd0;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            prescaler <= '0;
            counter   <= '0;
        end else begin
            prescaler <= tick ? 7'(DIV - 1) : prescaler - 7'd1;
            if (cs && cpu_bus.wr && cpu_bus.req)
                counter <= '0;
            else if (tick)
                counter <= counter + 16'd1;
        end
    end

    assign data = cs && cpu_bus.rd ? (cpu_bus.addr[0] ? counter[15:8] : counter[7:0]) : 8'hFF;

endmodule
