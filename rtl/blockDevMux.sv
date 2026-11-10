// Block device MUX
//
// Copyright (c) 2025 Molekula
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

// block_device_FDD[i] = hps_io VD i+1, VDNUM = 1 + 2*MSX::N_FDC
module blockDevMux #(parameter VDNUM) (
    input                     clk,
    input                     reset,

    input MSX::msx_config_t   msx_config,

    // hps sd interface
    output logic       [31:0] sd_lba[VDNUM],
    output              [5:0] sd_blk_cnt[VDNUM],
    
    output        [VDNUM-1:0] sd_rd,
    output        [VDNUM-1:0] sd_wr,
    input         [VDNUM-1:0] sd_ack,
    input              [13:0] sd_buff_addr,
    input               [7:0] sd_buff_dout,
    output              [7:0] sd_buff_din[VDNUM],
    input                     sd_buff_wr,
    // hps image interface
    input         [VDNUM-1:0] img_mounted,
    input              [63:0] img_size,
    input                     img_readonly,
    
    block_device_if.hps_mp    block_device_FDD[VDNUM-1],
    block_device_if.hps_mp    block_device_SD
);

    // FDD images: size and read-only latched per drive (img_size / img_readonly of hps_io are
    // valid only with the img_mounted pulse); img_mounted itself goes on as the 1 clk event
    // "image (re)mounted", as for the SD card. A mounted image survives a core reset.
    logic [23:0] FDD_image_size[VDNUM-1];
    logic [VDNUM-2:0] FDD_image_ro;

    initial begin
        FDD_image_size     = '{default: 24'd0};
        FDD_image_ro       = '0;
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < VDNUM-1; i++) begin
            if (img_mounted[i+1]) begin
                FDD_image_size[i] <= img_size[23:0];
                FDD_image_ro[i]   <= img_readonly;
            end
        end
    end

    genvar i;
    generate
        for (i = 0; i < VDNUM-1; i++) begin : BLOCK_DEVICE_FDD_MAPS
            assign sd_lba[i+1]                        = block_device_FDD[i].lba;
            assign sd_blk_cnt[i+1]                    = block_device_FDD[i].blk_cnt;
            assign sd_rd[i+1]                         = block_device_FDD[i].rd;
            assign sd_wr[i+1]                         = block_device_FDD[i].wr;
            assign sd_buff_din[i+1]                   = block_device_FDD[i].buff_din;

            assign block_device_FDD[i].ack          = msx_config.fdd[i] ? sd_ack[i+1] : '0;
            assign block_device_FDD[i].buff_addr    = sd_buff_addr;
            assign block_device_FDD[i].buff_dout    = sd_buff_dout;
            assign block_device_FDD[i].buff_wr      = msx_config.fdd[i] ? sd_buff_wr : '0;          
            
            assign block_device_FDD[i].img_mounted  = img_mounted[i+1];
            assign block_device_FDD[i].img_size     = msx_config.fdd[i] ? 64'(FDD_image_size[i]) : 'd0; 
            assign block_device_FDD[i].img_readonly = FDD_image_ro[i];
            
        end
    endgenerate
    
    assign sd_lba[0]                   = block_device_SD.lba;
    assign sd_blk_cnt[0]               = block_device_SD.blk_cnt;
    assign sd_rd[0]                    = block_device_SD.rd;
    assign sd_wr[0]                    = block_device_SD.wr;
    assign sd_buff_din[0]              = block_device_SD.buff_din;

    assign block_device_SD.ack         = sd_ack[0];
    assign block_device_SD.buff_addr   = sd_buff_addr;
    assign block_device_SD.buff_dout   = sd_buff_dout;
    assign block_device_SD.buff_wr     = sd_buff_wr;
    assign block_device_SD.img_mounted = img_mounted[0];          

endmodule
