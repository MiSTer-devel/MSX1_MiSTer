// MIDI to the outside: HPS UART (MidiLink), user port (MT32-pi or a plain MIDI adapter)
//
// Copyright (c) 2026 Molekula
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

// User port modes (port_mode):
//   0  MT32-pi: MIDI out on pin 1, I2C / I2S of the Pi on the other pins (sys/mt32pi.sv).
//      Without a Pi it is a plain MIDI out. No MIDI in: pin 0 carries the I2C data.
//   1  MIDI adapter: MIDI out on pin 1, MIDI in on pin 0 at 31250 Bd.
//   2  off: all pins released.
// MIDI in comes from the user port in mode 1, from the HPS UART otherwise. MIDI out always
// goes to the HPS UART too, except while the HPS is in MIDI mode and the Pi plays (the music
// would sound twice).

module midi_port #(
    parameter int         LCD_BITS  = 26,     // "LCD-Auto": shown 2^LCD_BITS clk after an update (3.1 s)
    parameter logic [7:0] INFO_BASE = 8'd13   // first MT32-pi entry of the "I," list
)
(
    input               clk,
    input               reset,
    input               CLK_AUDIO,
    // OSD
    input         [1:0] port_mode,
    input               mt32_disable,       // Pi present but not used
    input         [1:0] mt32_info,          // 0 none, 1 OSD message, 2 LCD on, 3 LCD after an update
    input               mt32_mode_req,      // 0 Munt, 1 FluidSynth
    input         [1:0] mt32_rom_req,
    input         [2:0] mt32_sf_req,
    input               mt32_reset_req,     // "Reset Hanging Notes"
    output logic        mt32_available,
    output logic        mt32_newmode,       // toggles when the Pi reports its mode
    output logic        info_req,
    output logic  [7:0] info,
    // HPS UART
    input         [7:0] uart_mode,          // 3 = MIDI (MidiLink)
    input        [31:0] uart_speed,
    input               UART_RXD,
    output              UART_TXD,
    // user port
    input         [6:0] USER_IN,
    output        [6:0] USER_OUT,
    // MIDI of the machine
    input               midi_tx,
    output              midi_rx,            // serial line for uart_rx
    output       [31:0] midi_rx_speed,
    // audio: machine + Pi, in CLK_AUDIO
    input               pause,
    input        [15:0] core_audio_l,
    input        [15:0] core_audio_r,
    output logic [15:0] audio_l,
    output logic [15:0] audio_r,
    // video with the LCD of the Pi in the top left corner
    input  MSX::video_t video_in,
    output MSX::video_t video_out
);

    wire port_mt32 = port_mode == 2'd0;
    wire port_midi = port_mode == 2'd1;
    wire hps_midi  = uart_mode == 8'd3;

    // ---------------------------------------------------------------- MT32-pi
    wire  [6:0] mt32_out;
    wire [15:0] i2s_l, i2s_r;
    wire  [7:0] pi_mode, pi_rom, pi_sf;
    wire        pi_available, pi_newmode, pi_lcd_update, lcd_en, lcd_pix;

    logic [1:0] rst_a;
    always_ff @(posedge CLK_AUDIO) rst_a <= {rst_a[0], reset | mt32_reset_req | ~port_mt32};

    logic       ce_q;
    wire        ce_rise = video_in.ce_pix & ~ce_q;     // ce_pix of the V99x8 is a square wave
    logic [1:0] avail_s;
    wire        mt32_mute = avail_s[1] &  mt32_disable;
    wire        mt32_use  = avail_s[1] & ~mt32_disable;

    mt32pi mt32pi (
        .CLK_AUDIO(CLK_AUDIO),
        .CLK_VIDEO(clk),
        .CE_PIXEL(ce_rise),
        .VGA_VS(video_in.VS),
        .VGA_DE(~(video_in.hblank | video_in.vblank)),
        .USER_IN(port_mt32 ? USER_IN : 7'h7F),
        .USER_OUT(mt32_out),
        .reset(rst_a[1]),
        .midi_tx(midi_tx | mt32_mute),
        .midi_rx(),
        .mt32_i2s_r(i2s_r),
        .mt32_i2s_l(i2s_l),
        .mt32_available(pi_available),
        .mt32_mode_req(mt32_mode_req),
        .mt32_rom_req(mt32_rom_req),
        .mt32_sf_req({5'd0, mt32_sf_req}),
        .mt32_mode(pi_mode),
        .mt32_rom(pi_rom),
        .mt32_sf(pi_sf),
        .mt32_newmode(pi_newmode),
        .mt32_lcd_en(lcd_en),
        .mt32_lcd_pix(lcd_pix),
        .mt32_lcd_update(pi_lcd_update)
    );

    // ---------------------------------------------------------------- lines
    assign UART_TXD = midi_tx | (hps_midi & mt32_use);
    assign USER_OUT = port_mt32 ? mt32_out :
                      port_midi ? {5'b11111, midi_tx, 1'b1} : 7'h7F;

    // MIDI in. After a change of the source the line is passed on only once it has been idle
    // for longer than a byte, so that a byte is never picked up from its middle.
    logic  [1:0] rx_s;
    logic        rx_user_q, rx_open;
    logic [12:0] idle_cnt;      // 8191 clk = 381 us, a byte at 31250 Bd is 320 us

    always_ff @(posedge clk) begin
        rx_s      <= {rx_s[0], port_midi ? USER_IN[0] : UART_RXD};
        rx_user_q <= port_midi;
        if (reset || rx_user_q != port_midi) begin
            rx_open  <= 1'b0;
            idle_cnt <= '0;
        end else if (!rx_open) begin
            if (!rx_s[1])       idle_cnt <= '0;
            else if (&idle_cnt) rx_open  <= 1'b1;
            else                idle_cnt <= idle_cnt + 1'd1;
        end
    end

    assign midi_rx       = rx_open ? rx_s[1] : 1'b1;
    assign midi_rx_speed = port_midi ? 32'd31250 : uart_speed;

    // ---------------------------------------------------------------- state of the Pi in clk
    logic  [2:0] newmode_s, lcd_upd_s;
    logic [LCD_BITS-1:0] lcd_to;
    logic        lcd_on;

    wire [3:0] info_idx = pi_mode == 8'hA2                 ? {1'b0, pi_sf[2:0]} :
                          pi_mode == 8'hA1 && pi_rom < 8'd3 ? 4'd8 + pi_rom[1:0] : 4'd11;

    always_ff @(posedge clk) begin
        avail_s   <= {avail_s[0], pi_available};
        newmode_s <= {newmode_s[1:0], pi_newmode};
        lcd_upd_s <= {lcd_upd_s[1:0], pi_lcd_update};

        // mode, ROM and SoundFont are stable by the time the toggle gets here
        info_req <= (newmode_s[2] ^ newmode_s[1]) && mt32_info == 2'd1;
        info     <= INFO_BASE + info_idx;

        if (lcd_upd_s[2] ^ lcd_upd_s[1]) lcd_to <= '1;
        else if (lcd_to != 0)            lcd_to <= lcd_to - 1'd1;
        lcd_on <= mt32_info == 2'd2 || (mt32_info == 2'd3 && lcd_to != 0);

        if (reset) lcd_to <= '0;
    end

    assign mt32_available = avail_s[1];
    assign mt32_newmode   = newmode_s[1];

    // ---------------------------------------------------------------- video
    always_ff @(posedge clk) begin
        ce_q      <= video_in.ce_pix;
        video_out <= video_in;
        if (lcd_on && lcd_en) begin
            video_out.R <= {{2{lcd_pix}}, video_in.R[7:2]};
            video_out.G <= {{2{lcd_pix}}, video_in.G[7:2]};
            video_out.B <= {{2{lcd_pix}}, video_in.B[7:2]};
        end
    end

    // ---------------------------------------------------------------- audio
    // The machine audio is taken over when two samples in a row agree; the Pi is added 1:1.
    logic [15:0] l1, l2, r1, r2, core_l, core_r;
    logic [16:0] sum_l, sum_r;
    logic  [1:0] on_s;

    always_ff @(posedge CLK_AUDIO) begin
        l1 <= core_audio_l; l2 <= l1; if (l1 == l2) core_l <= l2;
        r1 <= core_audio_r; r2 <= r1; if (r1 == r2) core_r <= r2;

        on_s  <= {on_s[0], pi_available & ~mt32_disable & ~pause};
        sum_l <= {core_l[15], core_l} + (on_s[1] ? {i2s_l[15], i2s_l} : 17'd0);
        sum_r <= {core_r[15], core_r} + (on_s[1] ? {i2s_r[15], i2s_r} : 17'd0);

        audio_l <= ^sum_l[16:15] ? {sum_l[16], {15{sum_l[15]}}} : sum_l[15:0];
        audio_r <= ^sum_r[16:15] ? {sum_r[16], {15{sum_r[15]}}} : sum_r[15:0];
    end

endmodule
