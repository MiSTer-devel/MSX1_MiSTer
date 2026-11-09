// WD279x FDC
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

module wd279x #(parameter WD279_57=1, parameter sysCLK)
(
	input  logic        clk,         // sys clock
	input  logic        MRn,	      // master reset
	input  logic        CSn,		  // i/o enable
	input  logic        REn,         // i/o read
	input  logic        WEn,         // i/o write
	input  logic  [1:0] A,           // i/o port addr
	input  logic  [7:0] DIN,         // i/o data in
	output logic  [7:0] DOUT,  		// i/o data out
	output logic        DRQ,  		// DMA request
	output logic        INTRQ,

	output logic 		STEPn,
	output logic 		SDIRn,
	input  logic 		INDEXn,
	input  logic 		TRK00n,
	input  logic        READYn,
	input  logic        WPROTn,
	output logic        HLD,
	output logic        SSO,
	input  logic        RAWRDn,
	input  logic        DDENn,
	output logic        WG,          // write gate
	output logic        WD           // write data (1 clk pulse per flux transition)
);

	localparam A_COMMAND         = 0;
	localparam A_STATUS          = 0;
	localparam A_TRACK           = 1;
	localparam A_SECTOR          = 2;
	localparam A_DATA            = 3;

	logic [7:0] reg_cmd, reg_track, reg_sector, reg_data, status;
	logic       command_start;
	logic       busy;
	logic       INTRQ_ACK;

	assign busy = command_start | status[0];
	assign INTRQ = INTRQ_I | INTRQ_II | INTRQ_III | INTRQ_IV;
	assign status = status_command_type_I | status_command_type_II | status_command_type_III | status_command_type_IV;
	assign HLD = HLD_I | HLD_II | HLD_III;

	// WD2795/7: bit 1 of the type II and III commands is U, the side select output SSO (the 2793
	// compares the side instead and has no SSO), bit 3 is L, the sector length flag: L = 0 makes
	// N 0..3 = 256, 512, 1024, 128 bytes instead of 128 << N
	wire type_II_III = reg_cmd[7:6] == 2'b10 || (reg_cmd[7:6] == 2'b11 && reg_cmd[5:4] != 2'b01);
	always_ff @(posedge clk) begin
		if (~MRn)                                               SSO <= 1'b0;
		else if (WD279_57 != 0 && command_start && type_II_III) SSO <= reg_cmd[1];
	end
	wire [1:0] len_add = (WD279_57 != 0 && !reg_cmd[3]) ? 2'd1 : 2'd0;
	always_comb begin
		DOUT = '1;
		INTRQ_ACK = 0;
		if (!(REn || CSn))
			case (A)
				A_DATA:   DOUT = reg_data;
				A_STATUS: begin DOUT = status; INTRQ_ACK = 1; end
				A_SECTOR: DOUT = reg_sector;
				A_TRACK:  DOUT = reg_track;
			endcase
	end

	logic last_REn, last_WEn, write_rq, read_rq;
	always_ff @(posedge clk) begin
		last_REn <= REn;
		last_WEn <= WEn;
	end

	assign write_rq = ~CSn && last_WEn && ~WEn;
	assign read_rq  = ~CSn && last_REn && ~REn;


	//Command register
	always_ff @(posedge clk) begin
		command_start <= 0;
		if (~MRn)	begin
			reg_cmd <= 8'h03;
			command_start <= 1;
		end else begin
			if (write_rq && A == A_COMMAND) begin
				if (!busy || DIN[7:4] == 4'hD) begin
					//$display("SET CMD %X", DIN);
					reg_cmd <= DIN;
					command_start <= 1;
				end
			end
		end
	end

	//Track register
	always_ff @(posedge clk) begin
		if (~MRn)	begin
			reg_track <= 0;
		end	else begin
			if (write_rq && A == A_TRACK && !busy ) begin
				reg_track <= DIN;
				//$display("SET TRACK %X", DIN);
			end
			if (reg_track_write)
				reg_track <= reg_track_out;
		end
	end

	//Sector register
	always_ff @(posedge clk) begin
		if (~MRn)	begin
			reg_sector <= 1;
		end	else begin
			if (write_rq && A == A_SECTOR && !busy ) begin
				reg_sector <= DIN;
				//$display("SET SECTOR %X", DIN);
			end
			if (reg_sector_write)
				reg_sector <= reg_sector_out;
			if (sector_write_III)
				reg_sector <= sector_out_III;		// Read Address: the track byte of the ID
		end
	end

	// Data register and DRQ: any CPU access of the data register clears DRQ, so does a new
	// command (openMSX; a command ended by Lost Data or Force Interrupt leaves it set); a read
	// command sets it with every byte from the disk, a write command when it can take the next byte
	always_ff @(posedge clk) begin
		if (~MRn)	begin
			reg_data <= 0;
			DRQ <= 0;
		end	else begin
			if (write_rq && A == A_DATA) begin
				reg_data <= DIN;
				DRQ <= 0;
			end
			if (read_rq && A == A_DATA) DRQ <= 0;
			if (command_start) DRQ <= 0;

			if (reg_data_write_I) begin
				reg_data <= reg_data_out_I;
			end

			if (enable_write_reg_data_II && fdd_rx) begin
				reg_data <= fdd_data;
				DRQ <= 1;
			end
			if (data_write_III) begin
				reg_data <= data_out_III;
				DRQ <= 1;
			end
			if (drq_set_II || drq_set_III) DRQ <= 1;
		end
	end

logic [7:0] reg_track_out;
logic       reg_track_write;
logic [7:0] reg_data_out_I;
logic       reg_data_write_I;
logic [7:0] status_command_type_I;
logic       INTRQ_I;
logic 		HLD_I;
wd279x_command_I command_I (
	.clk(clk),
	.msclk(msclk),
	.interrupt(interrupt),
	.MRn(MRn),
	.command(reg_cmd),
	.command_start(command_start),
	.status(status_command_type_I),
	.reg_data(reg_data),
	.reg_data_out(reg_data_out_I),
	.reg_data_write(reg_data_write_I),
	.track(reg_track_write ? reg_track_out : reg_track),
	.track_out(reg_track_out),
	.track_write(reg_track_write),
	.IDAM_valid(IDAM_valid),
	.IDAM_data(IDAM_data),
	.STEPn(STEPn),
	.SDIRn(SDIRn),
	.INDEXn(INDEXn),
	.READYn(READYn),
	.WPROTn(WPROTn),
	.TRK00n(TRK00n),
	.HLD(HLD_I),
	.INTRQ(INTRQ_I),
	.INTRQ_ACK(INTRQ_ACK)
);

logic [7:0] reg_sector_out;
logic       reg_sector_write;
logic [7:0] status_command_type_II;
logic       INTRQ_II;
logic       enable_write_reg_data_II;
logic       drq_set_II;
logic       HLD_II;
logic       wg_II, tx_wr_II, tx_a1_II, tx_mark_II, tx_crc_II;
logic [7:0] tx_data_II;
wd279x_command_II #(.WD279_57(WD279_57)) command_II (
	.clk(clk),
	.msclk(msclk),
	.interrupt(interrupt),
	.MRn(MRn),
	.command(reg_cmd),
	.command_start(command_start),
	.status(status_command_type_II),
	.track(reg_track),
	.sector(reg_sector_write ? reg_sector_out : reg_sector),
	.sector_out(reg_sector_out),
	.sector_write(reg_sector_write),
	.INDEXn(INDEXn),
	.READYn(READYn),
	.WPROTn(WPROTn),
	.DDENn(DDENn),
	.len_add(len_add),
	.HLD(HLD_II),
	.INTRQ(INTRQ_II),
	.INTRQ_ACK(INTRQ_ACK),
	.DRQ(DRQ),
	.drq_set(drq_set_II),
	.enable_write_reg_data(enable_write_reg_data_II),
	.IDAM_valid(IDAM_valid),
	.IDAM_data(IDAM_data),
	.DAM_valid(DAM_valid),
	.DAM_deleted(DAM_deleted),
	.DAM_CRC_valid(DAM_CRC_valid),
	.data_rx(fdd_rx),
	.reg_data(reg_data),
	.tx_req(tx_req),
	.tx_idle(tx_idle),
	.byte_tick(byte_tick),
	.wg(wg_II),
	.tx_wr(tx_wr_II),
	.tx_a1(tx_a1_II),
	.tx_mark(tx_mark_II),
	.tx_crc(tx_crc_II),
	.tx_data(tx_data_II)
);

logic [7:0] status_command_type_III;
logic       INTRQ_III, HLD_III, drq_set_III, data_write_III, sector_write_III;
logic [7:0] data_out_III, sector_out_III;
logic       wg_III, tx_wr_III, tx_a1_III, tx_c2_III, tx_mark_III, tx_crc_III;
logic [7:0] tx_data_III;
wd279x_command_III command_III (
	.clk(clk),
	.msclk(msclk),
	.interrupt(interrupt),
	.MRn(MRn),
	.command_start(command_start),
	.command(reg_cmd),
	.status(status_command_type_III),
	.INTRQ(INTRQ_III),
	.INTRQ_ACK(INTRQ_ACK),
	.DRQ(DRQ),
	.drq_set(drq_set_III),
	.data_out(data_out_III),
	.data_write(data_write_III),
	.sector_out(sector_out_III),
	.sector_write(sector_write_III),
	.INDEXn(INDEXn),
	.READYn(READYn),
	.WPROTn(WPROTn),
	.DDENn(DDENn),
	.HLD(HLD_III),
	.IDAM_data(IDAM_data),
	.IDAM_done(IDAM_done),
	.IDAM_crc_ok(IDAM_crc_ok),
	.fdd_data(fdd_data),
	.fdd_rx(fdd_rx),
	.reg_data(reg_data),
	.tx_req(tx_req),
	.wg(wg_III),
	.tx_wr(tx_wr_III),
	.tx_a1(tx_a1_III),
	.tx_c2(tx_c2_III),
	.tx_mark(tx_mark_III),
	.tx_crc(tx_crc_III),
	.tx_data(tx_data_III),
	.byte_tick(byte_tick)
);

logic       INTRQ_IV;
logic       interrupt;
logic [7:0] status_command_type_IV;
wd279x_command_IV  command_IV (
	.clk(clk),
	.interrupt(interrupt),
	.MRn(MRn),
	.command(reg_cmd),
	.command_start(command_start),
	.status(status_command_type_IV),
	.INTRQ(INTRQ_IV),
	.INTRQ_ACK(INTRQ_ACK),
	.INDEXn(INDEXn),
	.READYn(READYn),
	.WPROTn(WPROTn),
	.TRK00n(TRK00n),
	.HLD(HLD)
);


logic  [7:0] IDAM_data[6];
logic  [7:0] fdd_data;
logic        fdd_rx;
logic        IDAM_valid;
logic        IDAM_done;
logic        IDAM_crc_ok;
logic        DAM_valid;
logic        DAM_deleted;
logic        DAM_CRC_valid;

wd279x_demodulator #(.sysCLK(sysCLK)) demodulator (
	.clk(clk),
	.MRn(MRn),
	.INDEXn(INDEXn),
	.DDENn(DDENn),
	.RAWRDn(RAWRDn),
	.len_add(len_add),
	.IDAM_data(IDAM_data),
    .fdd_data(fdd_data),
    .fdd_rx(fdd_rx),
    .IDAM_valid(IDAM_valid),
    .IDAM_done(IDAM_done),
    .IDAM_crc_ok(IDAM_crc_ok),
	.DAM_valid(DAM_valid),
	.DAM_deleted(DAM_deleted),
    .DAM_CRC_valid(DAM_CRC_valid)
);

// One command writes at a time: type II (Write Sector) or type III (Write Track)
logic tx_req, tx_idle, byte_tick;
wd279x_modulator #(.sysCLK(sysCLK)) modulator (
	.clk(clk),
	.MRn(MRn),
	.DDENn(DDENn),
	.wg(wg_II | wg_III),
	.tx_wr(tx_wr_II | tx_wr_III),
	.tx_a1(tx_a1_II | tx_a1_III),
	.tx_c2(tx_c2_III),
	.tx_mark(tx_mark_II | tx_mark_III),
	.tx_crc(tx_crc_II | tx_crc_III),
	.tx_data(wg_III ? tx_data_III : tx_data_II),
	.tx_req(tx_req),
	.tx_idle(tx_idle),
	.byte_tick(byte_tick),
	.WG(WG),
	.WD(WD)
);

logic msclk;
clockEnabler #(.clkFreq(sysCLK), .targetFreq(1000)) FDD_MS(
	.clk(clk),
	.en(msclk)
);

endmodule

