// MSX mouse on a joystick port from the MiSTer PS/2 mouse (after MSX_MiSTer ps2mouse.v,
// https://github.com/MiSTer-devel/MSX_MiSTer).
// Protocol: each strobe (pin 8) edge gives the next nibble: X high, X low, Y high, Y low;
// the counts are latched on the first rising edge, at most once per ~1.5 ms.
// data[5:4] = buttons (active low), data[3:0] = nibble.
// Differences from ps2mouse.v: the X high nibble comes from the latched value (was dx[7:4],
// so fast X movement was distorted), counts saturate to -128..127, and an unfinished
// sequence restarts after ~1.5 ms without strobe edges.
module ps2mouse (
    input             clk,
    input             reset,
    input             strobe,
    output logic [5:0] data,
    input      [24:0] ps2_mouse        // [24] toggle, [23:16] dy, [15:8] dx, [5:4] sign, [1:0] buttons
);

    wire [11:0] mdx = {{4{ps2_mouse[4]}}, ps2_mouse[15:8]};
    wire [11:0] mdy = {{4{ps2_mouse[5]}}, ps2_mouse[23:16]};

    function automatic logic [7:0] sat8(input logic [11:0] v);   // (v / 2) clamped
        logic [10:0] h;
        h = v[11:1];
        if (~h[10] && |h[9:7])      return 8'h7F;
        else if (h[10] && ~&h[9:7]) return 8'h80;
        else                        return h[7:0];
    endfunction

    logic  [2:0] state = '0;
    logic [14:0] timer = '0;           // 32767 clk = 1.5 ms
    logic  [7:0] mx, my;
    logic [11:0] dx, dy;
    logic        old_strobe = 1'b0, old_stb = 1'b0;

    wire [7:0] dx_s = sat8(dx), dy_s = sat8(dy);
    wire timeout = &timer;
    wire rise    = ~old_strobe && strobe;
    wire fall    = old_strobe && ~strobe;

    always_ff @(posedge clk) begin
        if (~timeout) timer <= timer + 1'b1;
        old_strobe <= strobe;
        old_stb    <= ps2_mouse[24];

        if (reset) begin
            dx    <= '0;
            dy    <= '0;
            data  <= 6'b110000;
            state <= '0;
        end else begin
            if (old_stb ^ ps2_mouse[24]) begin
                data[5:4] <= ~ps2_mouse[1:0];
                dx <= dx - mdx;
                dy <= dy + mdy;
            end

            case (state)
                3'd0: if (rise && timeout) begin
                        state     <= 3'd1;
                        mx        <= dx_s;
                        my        <= dy_s;
                        dx        <= '0;
                        dy        <= '0;
                        timer     <= '0;
                        data[3:0] <= dx_s[7:4];
                    end
                3'd1: if (fall) begin state <= 3'd2; data[3:0] <= mx[3:0]; end
                3'd2: if (rise) begin state <= 3'd3; data[3:0] <= my[7:4]; end
                3'd3: if (fall) begin state <= 3'd4; data[3:0] <= my[3:0]; end
                default: if (rise) begin state <= 3'd0; data[3:0] <= '0; end
            endcase

            if (state != 3'd0 && timeout) begin     // abandoned sequence
                state     <= 3'd0;
                data[3:0] <= '0;
            end
        end
    end

endmodule
