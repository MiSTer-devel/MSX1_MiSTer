// flash ROM
//
// Copyright (c) 2024-2026 Molekula
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

// AMD command set flash, 8 MB, bottom boot (8 x 8 kB + 127 x 64 kB sectors), byte mode.
//   chip 0: M29W640GB (MFRSD), chip 1: S29GL064S (ASCII16-X)
// One engine for all cartridges; its state belongs to the cartridge that wrote last.
// The content is the system memory of the cartridge: array reads go around this module
// (data_valid = 0), programming and erasing write the memory through sdram_*.
// See doc/mappery.md for what is not implemented.
module flash (
    input                 clk,
    input                 clk_sdram,
    input                 reset,
    flash_bus_if.flash_mp flash_bus,
    input                 sdram_ready,
    input                 sdram_done,
    output   logic [26:0] sdram_addr,
    output   logic  [7:0] sdram_din,
    output   logic        sdram_req,
    output                debug_erase
);

    localparam int          SECTORS      = 135;
    localparam int          ERASE_WINDOW = MSX::CLK_CORE_HZ / 20000;        // 50 us for more sectors
    localparam int          WIN_W        = $clog2(ERASE_WINDOW + 1);

    typedef enum logic [1:0] {MODE_READ, MODE_AUTOSELECT, MODE_CFI, MODE_ERASE} mode_t;
    typedef enum logic [2:0] {SEQ_IDLE, SEQ_UNLOCK, SEQ_CMD, SEQ_ERASE_AA, SEQ_ERASE_55,
                              SEQ_ERASE_CMD, SEQ_DATA} seq_t;

    mode_t mode = MODE_READ;
    seq_t  seq  = SEQ_IDLE;
    logic [2:0] data_left;                      // bytes of the program command to come

    initial sdram_req = 1'b0;

    // ------------------------------------------------------------------ bus decode
    wire  [7:0] din       = flash_bus.data_to_flash;
    wire [22:0] addr      = flash_bus.addr;
    wire  [1:0] bus_owner = {flash_bus.chip, flash_bus.id};
    wire        a555      = addr[11:1] == 11'h555;                  // word address, byte mode
    wire        a2aa      = addr[11:1] == 11'h2AA;
    wire        a_cfi     = flash_bus.chip ? addr[8:1] == 8'h55 : addr[11:1] == 11'h055;
    wire [23:0] area_end  = {1'b0, flash_bus.area_lo} + flash_bus.area_size;
    wire        in_area   = addr >= flash_bus.area_lo && {1'b0, addr} < area_end;

    function automatic logic [7:0] sector_of(input logic [22:0] a);
        return a[22:16] == 7'd0 ? {5'd0, a[15:13]} : {1'b0, a[22:16]} + 8'd7;
    endfunction

    logic       we_q = 1'b0;
    logic [1:0] owner = 2'd0;
    wire        wr_stb  = flash_bus.we & ~we_q;
    wire        foreign = bus_owner != owner;

    // ------------------------------------------------------------------ memory writes
    // Program bytes wait in a small queue; an erase fills its sectors with FF behind it.
    logic [34:0] fifo[4];                       // {system address, data}
    logic  [1:0] fifo_wp = 2'd0, fifo_rp = 2'd0;
    logic  [2:0] fifo_cnt = 3'd0;
    logic [26:0] fill_addr;
    logic [16:0] fill_left = 17'd0;

    logic [26:0] l_base;                        // of the erase command
    logic [22:0] l_lo;
    logic [23:0] l_end;

    logic [SECTORS-1:0] pend = '0;              // sectors of the running erase
    logic               erase_run;              // 0 = still accepting sectors
    logic   [WIN_W-1:0] win_cnt;
    logic         [7:0] scan;

    wire  [7:0] scan_64k  = scan - 8'd7;
    wire [22:0] sec_start = scan < 8'd8 ? {7'd0, scan[2:0], 13'd0} : {scan_64k[6:0], 16'd0};
    wire [23:0] sec_end   = {1'b0, sec_start} + (scan < 8'd8 ? 24'h002000 : 24'h010000);
    wire [23:0] clip_lo   = sec_start > l_lo ? {1'b0, sec_start} : {1'b0, l_lo};
    wire [23:0] clip_hi   = sec_end < l_end ? sec_end : l_end;
    wire [23:0] clip_len  = clip_hi - clip_lo;

    wire busy = mode == MODE_ERASE || fifo_cnt != 3'd0 || sdram_req;

    // ------------------------------------------------------------------ status of a running operation
    logic dq7, tgl6 = 1'b0, tgl2 = 1'b0;
    logic rd_q = 1'b0, rd_busy, rd_pend;
    wire  rd = flash_bus.ce & ~flash_bus.we;

    always_ff @(posedge clk) begin
        logic       push, pop;
        logic [2:0] left;
        mode_t      m;
        seq_t       s;

        push = 1'b0;
        pop  = 1'b0;
        we_q <= flash_bus.we;

        // DQ6 / DQ2 toggle with every read of the status
        rd_q <= rd;
        if (rd) begin
            rd_busy <= ~foreign & busy;
            rd_pend <= ~foreign & mode == MODE_ERASE & pend[sector_of(addr)];
        end
        if (rd_q & ~rd) begin
            if (rd_busy) tgl6 <= ~tgl6;
            if (rd_pend) tgl2 <= ~tgl2;
        end

        // ---------------------------------------------------------------- erase
        // (before the commands: a sector added in the last clock of the window still restarts it)
        if (mode == MODE_ERASE) begin
            if (~erase_run) begin
                if (win_cnt == WIN_W'(ERASE_WINDOW)) erase_run <= 1'b1;
                else                                 win_cnt   <= win_cnt + 1'b1;
            end else if (fill_left == 17'd0 && ~sdram_req) begin
                if (scan == 8'd135) begin
                    mode <= MODE_READ;
                    pend <= '0;
                end else begin
                    if (pend[scan] && clip_hi > clip_lo) begin          // part of the sector in the area
                        fill_addr <= 27'(clip_lo) - l_base;
                        fill_left <= clip_len[16:0];
                    end
                    scan <= scan + 8'd1;
                end
            end
        end

        // ---------------------------------------------------------------- commands
        if (wr_stb) begin
            if (mode == MODE_ERASE) begin
                // only more sectors, within the window after the last one
                if (~foreign && ~erase_run && din == 8'h30) begin
                    pend[sector_of(addr)] <= 1'b1;
                    win_cnt               <= '0;
                    erase_run             <= 1'b0;
                end
            end else if (~(foreign && busy)) begin
                m = mode;
                s = seq;
                if (foreign) begin                  // another cartridge starts from the read mode
                    m = MODE_READ;
                    s = SEQ_IDLE;
                end
                owner <= bus_owner;
                mode  <= m;
                seq   <= SEQ_IDLE;                  // a write that does not fit ends the sequence
                case (s)
                    SEQ_IDLE:
                        if (din == 8'hF0)                                       mode <= MODE_READ;
                        else if (din == 8'hFF && m == MODE_CFI && flash_bus.chip) mode <= MODE_READ;
                        else if (din == 8'h98 && a_cfi && m != MODE_CFI)        mode <= MODE_CFI;
                        else if (din == 8'hAA && a555)                          seq  <= SEQ_UNLOCK;
                        else if (m == MODE_READ && ~flash_bus.chip && a555 && (din == 8'h50 || din == 8'h56)) begin
                            seq       <= SEQ_DATA;              // double / quadruple byte program
                            data_left <= din == 8'h50 ? 3'd2 : 3'd4;
                        end
                    SEQ_UNLOCK:
                        if (din == 8'h55 && a2aa) seq <= SEQ_CMD;
                    SEQ_CMD:
                        if (a555) begin
                            if (din == 8'hF0) mode <= MODE_READ;
                            else if (m == MODE_READ) begin
                                if (din == 8'h90) mode <= MODE_AUTOSELECT;
                                if (din == 8'h80) seq  <= SEQ_ERASE_AA;
                                if (din == 8'hA0) begin
                                    seq       <= SEQ_DATA;
                                    data_left <= 3'd1;
                                end
                            end
                        end
                    SEQ_ERASE_AA:
                        if (din == 8'hAA && a555) seq <= SEQ_ERASE_55;
                    SEQ_ERASE_55:
                        if (din == 8'h55 && a2aa) seq <= SEQ_ERASE_CMD;
                    SEQ_ERASE_CMD:
                        if (din == 8'h30 || din == 8'h10) begin
                            mode      <= MODE_ERASE;
                            erase_run <= din == 8'h10;          // chip erase starts at once
                            win_cnt   <= '0;
                            scan      <= '0;
                            l_base    <= flash_bus.base_addr;
                            l_lo      <= flash_bus.area_lo;
                            l_end     <= area_end;
                            if (din == 8'h10) pend <= '1;
                            else begin
                                pend                  <= '0;
                                pend[sector_of(addr)] <= 1'b1;
                            end
                        end
                    SEQ_DATA: begin
                        // data of a program command: taken by position, never decoded
                        push = in_area;
                        dq7 <= ~din[7];
                        if (data_left != 3'd1) begin
                            seq       <= SEQ_DATA;
                            data_left <= data_left - 3'd1;
                        end
                    end
                    default: ;
                endcase
            end
        end

        // ---------------------------------------------------------------- memory writer
        // One byte per request; the request is held until done and then dropped for a clock.
        if (sdram_req) begin
            if (sdram_done) sdram_req <= 1'b0;
        end else if (sdram_ready && ~sdram_done) begin
            if (fifo_cnt != 3'd0) begin
                {sdram_addr, sdram_din} <= fifo[fifo_rp];
                sdram_req               <= 1'b1;
                fifo_rp                 <= fifo_rp + 2'd1;
                pop = 1'b1;
            end else if (fill_left != 17'd0) begin
                sdram_addr <= fill_addr;
                sdram_din  <= 8'hFF;
                sdram_req  <= 1'b1;
                fill_addr  <= fill_addr + 27'd1;
                fill_left  <= fill_left - 17'd1;
            end
        end

        left = pop ? fifo_cnt - 3'd1 : fifo_cnt;
        if (push && left != 3'd4) begin
            fifo[fifo_wp] <= {27'(addr) - flash_bus.base_addr, din};
            fifo_wp       <= fifo_wp + 2'd1;
            left = left + 3'd1;
        end
        fifo_cnt <= left;

        // Machine reset (also held during an upload): nothing more is written
        if (reset) begin
            mode      <= MODE_READ;
            seq       <= SEQ_IDLE;
            pend      <= '0;
            fill_left <= '0;
            fifo_cnt  <= '0;
            fifo_wp   <= '0;
            fifo_rp   <= '0;
        end
    end

    // ------------------------------------------------------------------ read data
    // Autoselect and CFI are 16 bit words; the byte address selects the word and its half.
    function automatic logic [7:0] autoselect(input logic chip, input logic [22:0] a);
        if (chip) begin                                 // S29GL064S: low byte on both halves
            case (a[4:1])
                4'h0:    return 8'h01;                  // manufacturer
                4'h1:    return 8'h7E;                  // device
                4'h2:    return a[7] ? 8'hFF : 8'h00;   // sector protection: none
                4'h3:    return 8'h0A;
                4'hE:    return 8'h10;
                4'hF:    return 8'h00;
                default: return 8'hFF;
            endcase
        end else begin                                  // M29W640GB: odd bytes are 0
            if (a[0]) return 8'h00;
            case (a[7:1])
                7'h00:   return 8'h20;
                7'h01:   return 8'h7E;
                7'h03:   return 8'h08;
                7'h0E:   return 8'h10;
                default: return 8'h00;                  // 02: sector protection: none
            endcase
        end
    endfunction

    function automatic logic [15:0] cfi(input logic chip, input logic [22:0] a);
        logic [7:0] w;
        w = chip ? {1'b0, a[7:1]} : a[8:1];
        if (w < 8'h10) begin
            if (chip) begin                             // autoselect words
                case (w[3:0])
                    4'h0:    return 16'h0001;
                    4'h1:    return 16'h227E;
                    4'h3:    return 16'hFF0A;
                    4'hE:    return 16'h2210;
                    4'hF:    return 16'h2200;
                    default: return 16'hFFFF;
                endcase
            end else begin
                case (w[3:0])
                    4'h0:    return 16'h0020;
                    4'h1:    return 16'h227E;
                    4'h2:    return 16'h2210;
                    4'h3:    return 16'h2200;
                    default: return 16'hFFFF;
                endcase
            end
        end
        case (w)
            8'h10: return 16'h0051;                     // "QRY"
            8'h11: return 16'h0052;
            8'h12: return 16'h0059;
            8'h13: return 16'h0002;                     // AMD command set
            8'h14: return 16'h0000;
            8'h15: return 16'h0040;                     // primary table
            8'h16, 8'h17, 8'h18, 8'h19, 8'h1A: return 16'h0000;
            8'h1B: return 16'h0027;                     // Vcc 2.7 - 3.6 V
            8'h1C: return 16'h0036;
            8'h1D: return chip ? 16'h0000 : 16'h00B5;   // Vpp
            8'h1E: return chip ? 16'h0000 : 16'h00C5;
            8'h1F: return chip ? 16'h0008 : 16'h0004;   // typical timeouts, 2^n
            8'h20: return chip ? 16'h0008 : 16'h0000;
            8'h21: return chip ? 16'h0009 : 16'h000A;
            8'h22: return chip ? 16'h0010 : 16'h0000;
            8'h23: return chip ? 16'h0003 : 16'h0004;   // maximal timeouts, 2^n times typical
            8'h24: return chip ? 16'h0003 : 16'h0000;
            8'h25: return chip ? 16'h0001 : 16'h0003;
            8'h26: return 16'h0000;
            8'h27: return 16'h0017;                     // 2^23 bytes
            8'h28: return 16'h0002;                     // x8 / x16
            8'h29: return 16'h0000;
            8'h2A: return chip ? 16'h0008 : 16'h0005;   // write buffer, 2^n bytes
            8'h2B: return 16'h0000;
            8'h2C: return 16'h0002;                     // two erase regions
            8'h2D: return 16'h0007;                     // 8 sectors
            8'h2E: return 16'h0000;
            8'h2F: return 16'h0020;                     // of 8 kB
            8'h30: return 16'h0000;
            8'h31: return 16'h007E;                     // 127 sectors
            8'h32: return 16'h0000;
            8'h33: return 16'h0000;                     // of 64 kB
            8'h34: return 16'h0001;
            8'h35, 8'h36, 8'h37, 8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C: return 16'h0000;
            8'h40: return 16'h0050;                     // "PRI"
            8'h41: return 16'h0052;
            8'h42: return 16'h0049;
            8'h43: return 16'h0031;                     // version 1.3
            8'h44: return 16'h0033;
            8'h45: return chip ? 16'h0020 : 16'h0000;
            8'h46: return 16'h0002;
            8'h47: return chip ? 16'h0001 : 16'h0004;
            8'h48: return chip ? 16'h0000 : 16'h0001;
            8'h49: return chip ? 16'h0008 : 16'h0004;
            8'h4A: return 16'h0000;
            8'h4B: return 16'h0000;
            8'h4C: return chip ? 16'h0002 : 16'h0001;
            8'h4D: return 16'h00B5;
            8'h4E: return 16'h00C5;
            8'h4F: return 16'h0002;                     // bottom boot
            8'h50: return 16'h0001;
            default: return 16'hFFFF;
        endcase
    endfunction

    wire [15:0] cfi_word = cfi(owner[1], addr);
    wire  [7:0] status   = mode == MODE_ERASE ? {1'b0, tgl6, 2'b00, erase_run, tgl2, 2'b00}
                                              : {dq7,  tgl6, 6'b000000};

    assign flash_bus.data_valid      = rd & ~foreign & (busy | mode != MODE_READ);
    assign flash_bus.data_from_flash = ~flash_bus.data_valid   ? 8'hFF :
                                       busy                    ? status :
                                       mode == MODE_AUTOSELECT ? autoselect(owner[1], addr) :
                                       addr[0]                 ? cfi_word[15:8] : cfi_word[7:0];

    assign debug_erase = mode == MODE_ERASE;

endmodule
