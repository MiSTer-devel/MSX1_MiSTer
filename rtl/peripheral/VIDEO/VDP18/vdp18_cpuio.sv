//-------------------------------------------------------------------------------
//
// Synthesizable model of TI's TMS9918A, TMS9928A, TMS9929A.
//
// $Id: vdp18_cpuio.vhd,v 1.17 2006/06/18 10:47:01 arnim Exp $
//
// CPU I/O Interface Module
//
//-------------------------------------------------------------------------------
//
// Copyright (c) 2006, Arnim Laeuger (arnim.laeuger@gmx.net)
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
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
// Please report bugs to the author, but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.
//
//-------------------------------------------------------------------------------
module vdp18_cpuio (
  input  logic        clk_i,
  input  logic        clk_en_10m7_i,
  input  logic        clk_en_acc_i,
  input  logic        reset_i,
  input  logic        rd_i,
  input  logic        wr_i,
  input  logic        mode_i,
  input  logic [7:0]  cd_i,
  output logic [7:0]  cd_o,
  output logic        cd_oe_o,
  input  access_t     access_type_i,
  output opmode_t     opmode_o,
  output logic        bitmap_o,     // M3: bitmap addressing, also in text/multicolor
  output logic        illegal_o,    // M1+M2: fixed image
  output logic        vram_we_o,
  output logic [13:0] vram_a_o,
  output logic [7:0]  vram_d_o,
  input  logic [7:0]  vram_d_i,
  input  logic        spr_coll_i,
  input  logic        spr_5th_i,
  input  logic [4:0]  spr_5th_num_i,
  output logic        reg_ev_o,
  output logic        reg_16k_o,
  output logic        reg_blank_o,
  output logic        reg_size1_o,
  output logic        reg_mag1_o,
  output logic [3:0]  reg_ntb_o,
  output logic [7:0]  reg_ctb_o,
  output logic [2:0]  reg_pgb_o,
  output logic [6:0]  reg_satb_o,
  output logic [2:0]  reg_spgb_o,
  output logic [3:0]  reg_col1_o,
  output logic [3:0]  reg_col0_o,
  input  logic        irq_i,
  output logic        int_n_o
);

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_RD_MODE0, ST_WR_MODE0,
    ST_RD_MODE1,
    ST_WR_MODE1_1ST, ST_WR_MODE1_1ST_IDLE,
    ST_WR_MODE1_2ND_VREAD, ST_WR_MODE1_2ND_VWRITE,
    ST_WR_MODE1_2ND_RWRITE
  } state_t;
  
  typedef enum logic [2:0] {
    TM_NONE, 
	 TM_RD_MODE0, 
	 TM_WR_MODE0, 
	 TM_RD_MODE1, 
	 TM_WR_MODE1 
  } transfer_mode_t;

  state_t state_s, state_q;

  logic [7:0] buffer_q;
  logic [13:0] addr_q;
  logic incr_addr_s, load_addr_s;
  logic wrbuf_cpu_s;
  logic sched_rdvram_s, rdvram_sched_q, rdvram_q;
  logic abort_wrvram_s, sched_wrvram_s, wrvram_sched_q, wrvram_q;
  logic write_tmp_s;
  logic [7:0] tmp_q;
  logic write_reg_s;

  typedef logic [7:0] ctrl_reg_t [8];
  ctrl_reg_t ctrl_reg_q;

  logic [7:0] status_reg_s;
  logic destr_rd_status_s;
  logic sprite_5th_q;
  logic [4:0] sprite_5th_num_q;
  logic sprite_coll_q;
  logic int_n_q;

  typedef enum logic {
    RDMUX_STATUS, RDMUX_READAHEAD
  } read_mux_t;

  read_mux_t read_mux_s;
  transfer_mode_t transfer_mode_v;

  logic incr_addr_v;
  
  always_ff @(posedge clk_i or posedge reset_i) begin
    
	 incr_addr_v  = incr_addr_s;
	 
	 if (reset_i) begin
      state_q <= ST_IDLE;
      buffer_q <= '0;
      addr_q <= '0;
      rdvram_sched_q <= 0;
      rdvram_q <= 0;
      wrvram_sched_q <= 0;
      wrvram_q <= 0;
    end else if (clk_en_10m7_i) begin
      state_q <= state_s;
      if (wrbuf_cpu_s) begin
        buffer_q <= cd_i;
        rdvram_sched_q <= 0;
        rdvram_q <= 0;
      end else if (clk_en_acc_i && rdvram_q && access_type_i == AC_CPU) begin
        buffer_q <= vram_d_i;
        rdvram_q <= 0;
        incr_addr_v = 1;
      end

      if (sched_rdvram_s) begin
        wrvram_sched_q <= 0;
        wrvram_q <= 0;
        rdvram_sched_q <= 1;
      end

      if (sched_wrvram_s) begin
        wrvram_sched_q <= 1;
      end

      if (abort_wrvram_s) begin
        wrvram_q <= 0;
      end

      if (rdvram_sched_q && clk_en_acc_i) begin
        rdvram_sched_q <= 0;
        rdvram_q <= 1;
      end

      if (wrvram_sched_q && clk_en_acc_i) begin
        wrvram_sched_q <= 0;
        wrvram_q <= 1;
      end

      if (load_addr_s) begin
        addr_q[7:0] <= unsigned'(tmp_q);
        addr_q[13:8] <= unsigned'(cd_i[5:0]);
      end else if (incr_addr_v) begin
        addr_q <= addr_q + 1'd1;
      end
    end
  end

  always_comb begin
    abort_wrvram_s = 0;
    incr_addr_s = 0;
    vram_we_o = 0;

    if (wrvram_q && access_type_i == AC_CPU) begin
      vram_we_o = 1;
      if (clk_en_acc_i) begin
        abort_wrvram_s = 1;
        incr_addr_s = 1;
      end
    end
  end

  always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin
      tmp_q <= '0;
      ctrl_reg_q <= '{default: '0};
      sprite_coll_q <= 0;
      sprite_5th_q <= 0;
      sprite_5th_num_q <= '0;
      int_n_q <= 1;
    end else if (clk_en_10m7_i) begin
      if (write_tmp_s) begin
        tmp_q <= cd_i;
      end

      if (write_reg_s) begin
        ctrl_reg_q[cd_i[2:0]] <= tmp_q;
      end

      if (!sprite_5th_q) begin
        sprite_5th_q <= spr_5th_i && int_n_q;   // only while F = 0 (TI 2.3.3)
        sprite_5th_num_q <= spr_5th_num_i;
      end else if (destr_rd_status_s) begin
        sprite_5th_q <= 0;
      end

      if (spr_coll_i) begin
        sprite_coll_q <= 1;
      end else if (destr_rd_status_s) begin
        sprite_coll_q <= 0;
      end

      if (irq_i) begin
        int_n_q <= 0;
      end else if (destr_rd_status_s) begin
        int_n_q <= 1;
      end
    end
  end

  always_comb begin
    state_s = state_q;
    sched_rdvram_s = 0;
    sched_wrvram_s = 0;
    wrbuf_cpu_s = 0;
    write_tmp_s = 0;
    write_reg_s = 0;
    load_addr_s = 0;
    read_mux_s = RDMUX_STATUS;
    destr_rd_status_s = 0;
		
    transfer_mode_v = TM_NONE;

    if (mode_i == 0) begin
      if (rd_i) transfer_mode_v = TM_RD_MODE0;
      if (wr_i) transfer_mode_v = TM_WR_MODE0;
    end else begin
      if (rd_i) transfer_mode_v = TM_RD_MODE1;
      if (wr_i) transfer_mode_v = TM_WR_MODE1;
    end

    case (state_q)
      ST_IDLE: begin
        case (transfer_mode_v)
          TM_RD_MODE0: state_s = ST_RD_MODE0;
          TM_WR_MODE0: state_s = ST_WR_MODE0;
          TM_RD_MODE1: state_s = ST_RD_MODE1;
          TM_WR_MODE1: state_s = ST_WR_MODE1_1ST;
          default: ;
        endcase
      end

      ST_RD_MODE0: begin
        read_mux_s = RDMUX_READAHEAD;
        if (transfer_mode_v == TM_NONE) begin
          state_s = ST_IDLE;
          sched_rdvram_s = 1;
        end
      end

      ST_WR_MODE0: begin
        wrbuf_cpu_s = 1;
        if (transfer_mode_v == TM_NONE) begin
          state_s = ST_IDLE;
          sched_wrvram_s = 1;
        end
      end

      ST_RD_MODE1: begin
        read_mux_s = RDMUX_STATUS;
        if (transfer_mode_v == TM_NONE) begin
          destr_rd_status_s = 1;
          state_s = ST_IDLE;
        end
      end

      ST_WR_MODE1_1ST: begin
        write_tmp_s = 1;
        if (transfer_mode_v == TM_NONE) begin
          state_s = ST_WR_MODE1_1ST_IDLE;
        end
      end

      ST_WR_MODE1_1ST_IDLE: begin
        case (transfer_mode_v)
          TM_RD_MODE0: state_s = ST_RD_MODE0;
          TM_WR_MODE0: state_s = ST_WR_MODE0;
          TM_RD_MODE1: state_s = ST_RD_MODE1;
          TM_WR_MODE1: begin
            case (cd_i[7:6])
              2'b00: state_s = ST_WR_MODE1_2ND_VREAD;
              2'b01: state_s = ST_WR_MODE1_2ND_VWRITE;
              2'b10, 2'b11: state_s = ST_WR_MODE1_2ND_RWRITE;
              default: ;
            endcase
          end
          default: ;
        endcase
      end

      ST_WR_MODE1_2ND_VREAD: begin
        load_addr_s = 1;
        if (transfer_mode_v == TM_NONE) begin
          sched_rdvram_s = 1;
          state_s = ST_IDLE;
        end
      end

      ST_WR_MODE1_2ND_VWRITE: begin
        load_addr_s = 1;
        if (transfer_mode_v == TM_NONE) begin
          state_s = ST_IDLE;
        end
      end

      ST_WR_MODE1_2ND_RWRITE: begin
        write_reg_s = 1;
        if (transfer_mode_v == TM_NONE) begin
          state_s = ST_IDLE;
        end
      end

      default: ;
    endcase
  end

  // M3 only changes addressing, so the undocumented modes reuse the text and
  // multicolor engines (doc/sordm5-opravy.md, V2).
  wire m1 = ctrl_reg_q[1][4];
  wire m2 = ctrl_reg_q[1][3];
  wire m3 = ctrl_reg_q[0][1];

  always_comb begin
    if (m1)      opmode_o = OPMODE_TEXTM;    // text, bitmap text, illegal
    else if (m2) opmode_o = OPMODE_MULTIC;   // multicolor, bitmap multicolor
    else if (m3) opmode_o = OPMODE_GRAPH2;
    else         opmode_o = OPMODE_GRAPH1;
  end

  assign bitmap_o  = m3;
  assign illegal_o = m1 & m2;

  assign status_reg_s = {!int_n_q, sprite_5th_q, sprite_coll_q, sprite_5th_num_q};
  assign vram_a_o = addr_q;
  assign vram_d_o = buffer_q;
  assign cd_o = (read_mux_s == RDMUX_READAHEAD) ? buffer_q : status_reg_s;
  assign cd_oe_o = rd_i ? 1'b1 : 1'b0;
  assign reg_ev_o = ctrl_reg_q[0][0];
  assign reg_16k_o = ctrl_reg_q[1][7];
  assign reg_blank_o = !ctrl_reg_q[1][6];
  assign reg_size1_o = ctrl_reg_q[1][1];
  assign reg_mag1_o = ctrl_reg_q[1][0];
  assign reg_ntb_o = ctrl_reg_q[2][3:0];
  assign reg_ctb_o = ctrl_reg_q[3];
  assign reg_pgb_o = ctrl_reg_q[4][2:0];
  assign reg_satb_o = ctrl_reg_q[5][6:0];
  assign reg_spgb_o = ctrl_reg_q[6][2:0];
  assign reg_col1_o = ctrl_reg_q[7][7:4];
  assign reg_col0_o = ctrl_reg_q[7][3:0];
  assign int_n_o = int_n_q || !ctrl_reg_q[1][5];

endmodule
