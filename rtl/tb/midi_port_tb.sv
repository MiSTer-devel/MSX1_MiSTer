// midi_port with the real sys/mt32pi.sv and uart_rx against a model of the Pi (I2C master,
// I2S source) and of the MIDI lines. Run: rtl/tb/run_midi_port.sh
`timescale 1ns/1ps

module midi_port_tb;

    localparam int T_I2C  = 2000;       // quarter of an I2C bit
    localparam int BIT_31 = 32000;      // 31250 Bd
    localparam int BIT_115 = 8681;      // 115200 Bd

    logic clk = 0, clk_audio = 0;
    always #23 clk = ~clk;              // 21.7 MHz
    always #20 clk_audio = ~clk_audio;  // 25 MHz

    logic        reset = 1;
    logic  [1:0] port_mode = 0;
    logic        mt32_disable = 0;
    logic  [1:0] mt32_info = 0;
    logic        mode_req = 0;
    logic  [1:0] rom_req = 0;
    logic  [2:0] sf_req = 0;
    logic        reset_req = 0;
    logic  [7:0] uart_mode = 0;
    logic [31:0] uart_speed = 115200;
    logic        uart_rxd = 1;
    logic        midi_tx = 1;
    logic        pause = 0;
    logic [15:0] core_l = 0, core_r = 0;
    MSX::video_t vin, vout;

    wire         mt32_available, mt32_newmode, info_req, uart_txd, midi_rx;
    wire   [7:0] info;
    wire  [31:0] midi_rx_speed;
    wire   [6:0] user_out;
    wire  [15:0] audio_l, audio_r;

    // user port lines: open drain with pull-ups
    logic pi_sda = 1, pi_scl = 1, pi_ws = 0, pi_bclk = 0, pi_dat = 0, dongle_rx = 1;
    wire  line0 = pi_sda & dongle_rx & user_out[0];
    wire [6:0] user_in = {1'b1, pi_dat, pi_bclk, pi_scl, pi_ws, user_out[1], line0};

    midi_port #(.LCD_BITS(17)) dut (
        .clk(clk), .reset(reset), .CLK_AUDIO(clk_audio),
        .port_mode(port_mode), .mt32_disable(mt32_disable), .mt32_info(mt32_info),
        .mt32_mode_req(mode_req), .mt32_rom_req(rom_req), .mt32_sf_req(sf_req),
        .mt32_reset_req(reset_req),
        .mt32_available(mt32_available), .mt32_newmode(mt32_newmode),
        .info_req(info_req), .info(info),
        .uart_mode(uart_mode), .uart_speed(uart_speed), .UART_RXD(uart_rxd), .UART_TXD(uart_txd),
        .USER_IN(user_in), .USER_OUT(user_out),
        .midi_tx(midi_tx), .midi_rx(midi_rx), .midi_rx_speed(midi_rx_speed),
        .pause(pause), .core_audio_l(core_l), .core_audio_r(core_r),
        .audio_l(audio_l), .audio_r(audio_r),
        .video_in(vin), .video_out(vout)
    );

    wire       rx_strobe;
    wire [7:0] rx_data;
    uart_rx #(.sysCLK(21739130)) uart_rx (
        .clk(clk), .reset(reset), .rx(midi_rx), .uart_speed(midi_rx_speed),
        .data_rx(rx_strobe), .framing_err(), .data(rx_data)
    );

    int errors = 0;
    task automatic check(input string what, input logic ok);
        if (!ok) begin errors++; $display("FAIL %s (t=%0t)", what, $time); end
    endtask

    // ------------------------------------------------------------ received MIDI bytes
    int       rx_cnt = 0;
    logic [7:0] rx_last;
    always @(posedge clk) if (rx_strobe) begin rx_cnt++; rx_last = rx_data; end

    // ------------------------------------------------------------ info messages
    int       info_cnt = 0;
    logic [7:0] info_last;
    always @(posedge clk) if (info_req) begin info_cnt++; info_last = info; end

    // ------------------------------------------------------------ MIDI out lines, checked all the time
    logic tx_noise = 0;
    always @(posedge clk) if (tx_noise) midi_tx <= $urandom_range(0, 3) != 0 ? midi_tx : ~midi_tx;
                          else          midi_tx <= 1;
    logic exp_hps_block = 0;        // UART_TXD held idle
    logic exp_user_tx   = 1;        // pin 1 follows midi_tx
    logic lines_stable  = 0;
    always @(negedge clk) if (lines_stable) begin
        check("UART_TXD", uart_txd == (midi_tx | exp_hps_block));
        check("USER_OUT[1]", user_out[1] == (exp_user_tx ? midi_tx : 1'b1));
        check("USER_OUT[6:2]", user_out[6:2] == 5'b11111);
    end

    // ------------------------------------------------------------ serial byte on a line
    task automatic send_uart(input int bit_ns, input logic [7:0] b);
        uart_rxd = 0; #(bit_ns);
        for (int i = 0; i < 8; i++) begin uart_rxd = b[i]; #(bit_ns); end
        uart_rxd = 1; #(bit_ns);
    endtask
    task automatic send_dongle(input logic [7:0] b);
        dongle_rx = 0; #(BIT_31);
        for (int i = 0; i < 8; i++) begin dongle_rx = b[i]; #(BIT_31); end
        dongle_rx = 1; #(BIT_31);
    endtask

    // ------------------------------------------------------------ Pi: I2C master
    task automatic i2c_start;
        pi_sda = 1; pi_scl = 1; #(T_I2C); pi_sda = 0; #(T_I2C); pi_scl = 0; #(T_I2C);
    endtask
    task automatic i2c_stop;
        pi_sda = 0; #(T_I2C); pi_scl = 1; #(T_I2C); pi_sda = 1; #(T_I2C);
    endtask
    task automatic i2c_wbyte(input logic [7:0] b, output logic ack);
        for (int i = 7; i >= 0; i--) begin
            pi_sda = b[i]; #(T_I2C); pi_scl = 1; #(2*T_I2C); pi_scl = 0; #(T_I2C);
        end
        pi_sda = 1; #(T_I2C); pi_scl = 1; #(T_I2C); ack = ~line0; #(T_I2C); pi_scl = 0; #(T_I2C);
    endtask
    task automatic i2c_rbyte(output logic [7:0] b, input logic ack);
        pi_sda = 1;
        for (int i = 7; i >= 0; i--) begin
            #(T_I2C); pi_scl = 1; #(T_I2C); b[i] = line0; #(T_I2C); pi_scl = 0; #(T_I2C);
        end
        pi_sda = ~ack; #(T_I2C); pi_scl = 1; #(2*T_I2C); pi_scl = 0; #(T_I2C); pi_sda = 1;
    endtask

    // status poll of mt32-pi: read 3 bytes from 45h
    task automatic pi_poll(output logic ack, output logic [7:0] m, output logic [7:0] r, output logic [7:0] s);
        m = 'x; r = 'x; s = 'x;
        i2c_start(); i2c_wbyte({7'h45, 1'b1}, ack);
        if (ack) begin i2c_rbyte(m, 1); i2c_rbyte(r, 1); i2c_rbyte(s, 0); end
        i2c_stop(); #(4*T_I2C);
    endtask
    // report of mt32-pi: write mode, ROM set, SoundFont to 45h
    task automatic pi_report(input logic [7:0] m, input logic [7:0] r, input logic [7:0] s);
        logic ack;
        i2c_start(); i2c_wbyte({7'h45, 1'b0}, ack);
        i2c_wbyte(m, ack); i2c_wbyte(r, ack); i2c_wbyte(s, ack);
        i2c_stop(); #(4*T_I2C);
    endtask
    // SSD1306 data: columns 0-15 of page 0
    logic [7:0] lcd_img [16];
    task automatic pi_lcd;
        logic ack;
        i2c_start(); i2c_wbyte({7'h3C, 1'b0}, ack); i2c_wbyte(8'h40, ack);
        for (int i = 0; i < 16; i++) i2c_wbyte(lcd_img[i], ack);
        i2c_stop(); #(4*T_I2C);
    endtask

    // ------------------------------------------------------------ Pi: I2S, 32 bit slots, BCLK on pin 4
    logic [15:0] pi_l = 0, pi_r = 0;
    logic        i2s_run = 0;
    always #160 pi_bclk = i2s_run ? ~pi_bclk : 1'b0;
    initial forever begin
        for (int ch = 0; ch < 2; ch++) begin
            logic [15:0] w;
            @(negedge pi_bclk); pi_ws = ch[0]; pi_dat = 0; w = ch ? pi_r : pi_l;
            for (int i = 15; i >= 0; i--) begin @(negedge pi_bclk); pi_dat = w[i]; end
            repeat (15) begin @(negedge pi_bclk); pi_dat = 0; end
        end
    end

    function automatic logic [15:0] sat(input logic [15:0] a, input logic [15:0] b);
        int s = $signed(a) + $signed(b);
        if (s >  32767) s =  32767;
        if (s < -32768) s = -32768;
        return s[15:0];
    endfunction
    task automatic check_audio(input string what, input logic with_pi);
        #(200000);          // several I2S frames
        check({what, " L"}, audio_l == (with_pi ? sat(core_l, pi_l) : core_l));
        check({what, " R"}, audio_r == (with_pi ? sat(core_r, pi_r) : core_r));
    endtask

    // ------------------------------------------------------------ video: 200 x 80 pixels, pixel = 2 clk
    localparam int HTOT = 200, HBL = 40, VTOT = 80, VBL = 4;
    int  hc = 0, vc = 0;
    logic pix_ph = 0;
    always @(posedge clk) begin
        pix_ph <= ~pix_ph;
        if (pix_ph) begin
            hc <= hc == HTOT - 1 ? 0 : hc + 1;
            if (hc == HTOT - 1) vc <= vc == VTOT - 1 ? 0 : vc + 1;
        end
    end
    always_comb begin
        vin = '0;
        vin.ce_pix = ~pix_ph;                     // square wave as the V99x8
        vin.hblank = hc < HBL;
        vin.vblank = vc < VBL;
        vin.HS     = hc >= 4 && hc < 20;
        vin.VS     = vc == 1;
        vin.DE     = ~(vin.hblank | vin.vblank);
        vin.R = 8'h80; vin.G = 8'h84; vin.B = 8'h88;
    end

    // video_out = video_in a clk later, apart from the overlay pixels
    MSX::video_t vin_q;
    always @(posedge clk) vin_q <= vin;
    // overlay seen in a frame: per line the first pixel, the count and the pixel values
    int        ov_first [VTOT], ov_cnt [VTOT];
    logic [159:0] ov_pix [VTOT];
    logic      ov_bad;
    int        ohc, ovc;
    always @(negedge clk) begin
        ohc = hc; ovc = vc;     // vout lags by a clk; pixels are 2 clk wide, sample in the second half
        if (!reset && pix_ph) begin
            if (vout.HS !== vin_q.HS || vout.VS !== vin_q.VS || vout.hblank !== vin_q.hblank ||
                vout.vblank !== vin_q.vblank || vout.ce_pix !== vin_q.ce_pix || vout.DE !== vin_q.DE)
                check("video sync passthrough", 0);
            if (vout.R == 8'h80 && vout.G == 8'h84 && vout.B == 8'h88) ;
            else if (vout.R[5:0] == 6'h20 && vout.G[5:0] == 6'h21 && vout.B[5:0] == 6'h22 &&
                     vout.R[7:6] == vout.G[7:6] && vout.R[7:6] == vout.B[7:6] && ^vout.R[7:6] == 0) begin
                if (ov_cnt[ovc] == 0) ov_first[ovc] = ohc;
                if (ov_cnt[ovc] < 160) ov_pix[ovc][ov_cnt[ovc]] = vout.R[7];
                ov_cnt[ovc]++;
            end else ov_bad = 1;
        end
    end
    task automatic frame_clear;
        wait (vc == 0 && hc == 0); @(negedge clk);
        for (int i = 0; i < VTOT; i++) begin ov_cnt[i] = 0; ov_first[i] = -1; ov_pix[i] = '0; end
        ov_bad = 0;
        wait (vc == VTOT - 1 && hc == HTOT - 2);
    endtask
    task automatic check_overlay(input string what, input logic on);
        int n_lines = 0, first = -1;
        logic same = 1, img = 1;
        frame_clear();
        check({what, ": pixel values"}, !ov_bad);
        for (int y = 0; y < VTOT; y++) if (ov_cnt[y] != 0) begin
            n_lines++;
            if (first < 0) first = ov_first[y];
            if (ov_cnt[y] != 128 || ov_first[y] != first || y < VBL || y >= VBL + 64) same = 0;
        end
        if (!on) check({what, ": no overlay"}, n_lines == 0);
        else begin
            check({what, ": 64 lines of 128 pixels"}, n_lines == 64 && same);
            for (int y = 0; y < 8; y++) for (int c = 0; c < 16; c++)
                if (ov_pix[VBL + y][c] !== lcd_img[c][y]) img = 0;
            check({what, ": picture"}, img);
        end
    endtask

    // ------------------------------------------------------------ test
    logic       ack;
    logic [7:0] m, r, s;
    int         n;

    initial begin
        for (int i = 0; i < 16; i++) lcd_img[i] = 8'(i * 37 + 5);
        repeat (20) @(posedge clk);
        reset = 0;
        #(500000);

        // --- no Pi: pin 1 is a MIDI out, HPS UART gets the same
        tx_noise = 1; lines_stable = 1;
        check("no Pi: not available", !mt32_available);
        check("no Pi: USER_OUT[0] released", user_out[0]);
        core_l = 16'h1234; core_r = 16'hF00D;
        check_audio("no Pi audio", 0);
        check_overlay("no Pi", 0);

        // --- MIDI in from the HPS at the speed of the HPS
        n = rx_cnt; send_uart(BIT_115, 8'hA5); #(100000);
        check("HPS RX 115200", rx_cnt == n + 1 && rx_last == 8'hA5);
        uart_speed = 31250; uart_mode = 3;
        n = rx_cnt; send_uart(BIT_31, 8'h90); #(100000);
        check("HPS RX 31250", rx_cnt == n + 1 && rx_last == 8'h90);

        // --- the Pi appears: I2C on pin 0 must never look like MIDI in
        i2s_run = 1; pi_l = 16'h0100; pi_r = 16'hFF00;
        lines_stable = 0;
        n = rx_cnt;
        pi_poll(ack, m, r, s);
        check("Pi poll acknowledged", ack);
        check("first poll after reset: A0", m == 8'hA0 && r == 8'h00 && s == 8'h00);
        #(20000);
        check("Pi available", mt32_available);
        exp_hps_block = 1; lines_stable = 1;       // HPS in MIDI mode and the Pi plays
        mode_req = 1; rom_req = 2; sf_req = 5;
        pi_poll(ack, m, r, s);
        check("poll: FluidSynth, ROM 2, SoundFont 5", m == 8'hA2 && r == 8'h02 && s == 8'h05);
        mode_req = 0;
        pi_poll(ack, m, r, s);
        check("poll: Munt", m == 8'hA1);
        check("I2C is not MIDI in", rx_cnt == n);
        check_audio("Pi audio", 1);

        // --- saturation
        core_l = 16'h7000; pi_l = 16'h2000; core_r = 16'h9000; pi_r = 16'hE000;
        check_audio("saturation", 1);
        check("saturated values", audio_l == 16'h7FFF && audio_r == 16'h8000);
        core_l = 16'h1234; core_r = 16'hF00D; pi_l = 16'h0100; pi_r = 16'hFF00;

        // --- HPS not in MIDI mode: both get the data
        lines_stable = 0; uart_mode = 0; exp_hps_block = 0; #(1000); lines_stable = 1;
        #(300000);
        lines_stable = 0; uart_mode = 3; exp_hps_block = 1; #(1000); lines_stable = 1;

        // --- pause mutes the Pi
        pause = 1; check_audio("pause", 0); pause = 0; check_audio("after pause", 1);

        // --- mode reports: message only with Show Info = Yes
        n = info_cnt; pi_report(8'hA1, 8'h01, 8'h00); #(20000);
        check("no message with Show Info = No", info_cnt == n);
        mt32_info = 1;
        pi_report(8'hA1, 8'h01, 8'h00); #(20000);
        check("message MT-32 v2", info_cnt == n + 1 && info_last == 8'd22);
        pi_report(8'hA2, 8'h00, 8'h05); #(20000);
        check("message SoundFont 5", info_cnt == n + 2 && info_last == 8'd18);
        pi_report(8'hA1, 8'h07, 8'h00); #(20000);
        check("message unknown mode", info_cnt == n + 3 && info_last == 8'd24);
        pi_lcd(); check_overlay("Show Info = Yes", 0);

        // --- LCD
        mt32_info = 2; check_overlay("LCD-On", 1);
        mt32_info = 3; #(8000000); check_overlay("LCD-Auto, old picture", 0);
        lcd_img[3] = 8'hFF; lcd_img[4] = 8'h00;
        pi_lcd(); check_overlay("LCD-Auto after an update", 1);
        #(8000000); check_overlay("LCD-Auto later", 0);
        mt32_info = 0;

        // --- Pi present but not used
        lines_stable = 0; mt32_disable = 1; exp_hps_block = 0; exp_user_tx = 0; #(1000); lines_stable = 1;
        check_audio("Use MT32-pi = No", 0);
        lines_stable = 0; mt32_disable = 0; exp_hps_block = 1; exp_user_tx = 1; #(1000); lines_stable = 1;

        // --- Reset Hanging Notes: detected again, the Pi is told to mute
        lines_stable = 0;
        reset_req = 1; #(2000); reset_req = 0; #(2000);
        check("reset: not available", !mt32_available);
        pi_poll(ack, m, r, s); #(20000);
        check("poll after reset: A0", ack && m == 8'hA0);
        check("available again", mt32_available);

        // --- machine reset does the same
        reset = 1; #(2000); reset = 0; #(500000);
        check("machine reset: not available", !mt32_available);
        pi_poll(ack, m, r, s); #(20000);
        check("poll after machine reset: A0", ack && m == 8'hA0 && mt32_available);
        lines_stable = 1;

        // --- MIDI adapter: Pi ignored, pin 1 MIDI out, pin 0 MIDI in at 31250
        lines_stable = 0; port_mode = 1; exp_hps_block = 0; #(1000);
        check("MIDI mode: Pi gone", !mt32_available);
        lines_stable = 1;
        uart_speed = 115200; uart_mode = 0;
        #(1000000);
        n = rx_cnt; send_dongle(8'h3C); #(100000);
        check("user port RX 31250", rx_cnt == n + 1 && rx_last == 8'h3C);
        check("MIDI mode: pin 0 released", user_out[0]);
        fork
            send_uart(BIT_115, 8'h55);
        join
        #(100000);
        check("MIDI mode: HPS RX ignored", rx_cnt == n + 1);
        check_audio("MIDI mode audio", 0);

        // --- off: pins released, MIDI in from the HPS again
        lines_stable = 0; port_mode = 2; #(1000000);
        tx_noise = 0; #(1000);
        check("off: USER_OUT", user_out == 7'h7F);
        tx_noise = 1; #(200000);
        check("off: USER_OUT with MIDI running", user_out == 7'h7F);
        n = rx_cnt; send_uart(BIT_115, 8'hC3); #(100000);
        check("off: HPS RX", rx_cnt == n + 1 && rx_last == 8'hC3);
        send_dongle(8'h11); #(100000);
        check("off: user port RX ignored", rx_cnt == n + 1);

        // --- source switched in the middle of a byte: nothing until the line was idle
        n = rx_cnt;
        fork
            begin send_dongle(8'h00); send_dongle(8'h00); #(600000); send_dongle(8'h7E); end
            begin #(100000); port_mode = 1; end
        join
        #(100000);
        check("switch inside a byte", rx_cnt == n + 1 && rx_last == 8'h7E);

        // --- Pi polling in MIDI mode is not answered
        port_mode = 1; #(1000000);
        pi_poll(ack, m, r, s);
        check("MIDI mode: Pi not answered", !ack && !mt32_available);
        mt32_info = 1; n = info_cnt;
        pi_report(8'hA1, 8'h00, 8'h00); #(20000);
        check("MIDI mode: no message from the Pi", info_cnt == n);

        #(100000);
        if (errors == 0) $display("PASS midi_port_tb");
        else             $display("FAIL midi_port_tb: %0d errors", errors);
        $finish;
    end

    initial begin #(200000000); $display("FAIL midi_port_tb: timeout"); $finish; end

endmodule
