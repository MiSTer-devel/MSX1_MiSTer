// Original megasd.vhd SD/MMC card interface
// Copyright (c) 2006 Kazuhiro Tsujikawa (ESE Artists' factory)
// Taken from OCM-PLD by KdL as used in MSX_MiSTer (https://github.com/MiSTer-devel/MSX_MiSTer).
//
// Rewrite and modify 2024-2025 Molekula
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//


module mapper_eseRam (
    cpu_bus_if.device_mp        cpu_bus,       
    output MSX::mapper_out_t out,           
    input  MSX::block_info_t block_info,
    ext_sd_card_if.device_mp    ext_SD_card_bus,
    input                       megaSD_enable,
    output                      mmc_on,         // MegaSD window mapped (OCM mmcena)
    output                      mmc_wait        // CPU wait: SPI still busy with the previous byte
);
  
    wire cs;

    assign cs = block_info.typ == MAPPER_ESE_RAM & cpu_bus.mreq && (cpu_bus.rd || cpu_bus.wr);

    logic [7:0] bank[4];

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            bank <= '{8'h00, 8'h00, 8'h00, 8'h00};
        end else begin
            if (cs && cpu_bus.wr && cpu_bus.req && cpu_bus.addr[15:13] == 3'b011) begin
                bank[cpu_bus.addr[12:11]] <= cpu_bus.data;               
            end
        end
    end

    logic  [6:0] bank_base;
    logic        ram_wr;  
    always_comb begin
        ram_wr = 1'b0;
        bank_base = '1;
        case (cpu_bus.addr[14:13])
            2'b00 : begin
                bank_base = bank[2][6:0];
                ram_wr    = bank[2][7] && cpu_bus.wr;
            end
            2'b01 : begin
                bank_base = bank[3][6:0];
                ram_wr    = bank[3][7] && cpu_bus.wr;
            end
            2'b10 : begin
                bank_base = bank[0][6:0];
                ram_wr    = bank[0][7] && cpu_bus.wr;
            end
            2'b11 : begin
                bank_base =  bank[1][6:0];
            end
        endcase
    end
    
    wire mmc_enable, mmc_read;
    assign mmc_on = bank[0][7:6] == 2'b01;
    wire [26:0] ram_addr;   
    
    assign mmc_enable = bank[0][7:6] == 2'b01 && cpu_bus.addr[15:13] == 3'b010 && megaSD_enable;
    assign ram_addr   = {7'b0, bank_base, cpu_bus.addr[12:0]};                   
    
    assign out.ram_cs = cs && ((cpu_bus.rd && ~mmc_enable) || ram_wr);   // only in own slot
    assign out.addr   = cs ? ram_addr : {27{1'b1}};
    assign out.rnw    = cs ? ~ram_wr : 1'b1;
    assign out.data   = cs && mmc_enable ? ext_SD_card_bus.data_from_SD : '1;

    // SD card: one SPI transfer per CPU access of 4000-57FFh (5800-5FFFh = mode register).
    // An access arriving while the previous byte is still shifted waits (OCM MmcAct).
    logic mmc_cs, mmc_mod, mmc_pend;
    wire  mmc_data  = cs && mmc_enable && cpu_bus.addr[12:11] != 2'b11 && ~mmc_mod;
    wire  mmc_want  = (mmc_data && cpu_bus.req) || mmc_pend;
    wire  mmc_start = mmc_want && ~ext_SD_card_bus.busy && ~ext_SD_card_bus.rx;   // rx: busy not visible yet
    assign mmc_wait = mmc_want && ~mmc_start;

    always_ff @(posedge cpu_bus.clk) begin
        ext_SD_card_bus.rx         <= '0;
        ext_SD_card_bus.tx         <= '0;
        ext_SD_card_bus.data_to_SD <= '1;

        if (cpu_bus.reset) begin
            mmc_mod  <= '0;
            mmc_cs   <= '1;
            mmc_pend <= '0;
        end else begin
            if (cs && mmc_enable && cpu_bus.addr[12:11] == 2'b11 && cpu_bus.wr && cpu_bus.req)
                mmc_mod <= cpu_bus.data[0];
            if (mmc_start) begin
                mmc_pend           <= 1'b0;
                ext_SD_card_bus.rx <= 1'b1;
                mmc_cs             <= cpu_bus.addr[12];
                if (cpu_bus.wr) begin
                    ext_SD_card_bus.tx         <= 1'b1;
                    ext_SD_card_bus.data_to_SD <= cpu_bus.data;
                end
            end else if (mmc_want)
                mmc_pend <= 1'b1;
        end
    end

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;

endmodule
