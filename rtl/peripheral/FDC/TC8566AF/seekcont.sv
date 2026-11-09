// Seek control
//
// SystemVerilog port of rtl/FDC/seekcont.vhd of PC88_MiSTer revision 1d4de0f (2025-02-25)
// (https://github.com/MiSTer-devel/PC88_MiSTer). The same FDC code is published under the
// GNU General Public License version 3 in X68000_MiSTer. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module seekcont(
    input logic [1:0] uselin,
    input logic inireq,
    input logic seekreq,
    input int destin,
    input logic [3:0] tdi,
    
    output logic [3:0] iniout,
    output logic [3:0] seekout,
    output int dest0,
    output int dest1,
    output int dest2,
    output int dest3,
    output logic [3:0] tdo,
    input logic readyin,
    
    input logic [3:0] sendin,
    input logic [3:0] serrin,
    input logic [3:0] sbusyin,
    
    output logic [3:0] seek_end,
    output logic [3:0] seek_err,
    output logic readyout,
    
    output logic [3:0] seek_pend,
    output logic busy,
    output logic [1:0] uselout,
    
    input logic clk,
    input logic rstn
);

    logic [3:0] inipend;
    logic [3:0] seekpend;
    logic [1:0] curunit;
    logic       run;
    int destb0, destb1, destb2, destb3;
    
    logic [1:0] sel;
    logic       run_tmp;
    always_comb begin
        sel = 2'd0;
        run_tmp = 1'b0;
        for (int i = 3; i >= 0; i--) begin
            if (inipend[i] || seekpend[i]) begin
                sel = i[1:0];
                run_tmp = 1'b1;
            end
        end
    end


    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            destb0 <= 0;
            destb1 <= 0;
            destb2 <= 0;
            destb3 <= 0;
            dest0 <= 0;
            dest1 <= 0;
            dest2 <= 0;
            dest3 <= 0;
            inipend <= 4'b0000;
            seekpend <= 4'b0000;
            curunit <= 2'd0;
            readyout <= 0;
            tdo <= 4'b0000;
            run <= 0;
        end else begin
            iniout <= 4'b0000;
            seekout <= 4'b0000;
            seek_end <= 4'b0000;
            seek_err <= 4'b0000;

            if (inireq || seekreq) begin
                case (uselin)
                    2'b00: begin
                        inipend[0] <= inireq;
                        seekpend[0] <= seekreq;
                        destb0 <= destin;
                        tdo[0] <= tdi[0];
                    end
                    2'b01: begin
                        inipend[1] <= inireq;
                        seekpend[1] <= seekreq;
                        destb1 <= destin;
                        tdo[1] <= tdi[1];
                    end
                    2'b10: begin
                        inipend[2] <= inireq;
                        seekpend[2] <= seekreq;
                        destb2 <= destin;
                        tdo[2] <= tdi[2];
                    end
                    2'b11: begin
                        inipend[3] <= inireq;
                        seekpend[3] <= seekreq;
                        destb3 <= destin;
                        tdo[3] <= tdi[3];
                    end
                endcase
            end

            if (run) begin
                if (sendin[curunit]) begin
                    if (!seekpend[curunit] && !inipend[curunit]) begin
                        seek_end[curunit] <= 1;
                    end
                    run <= 0;
                    readyout <= readyin;
                end else if (serrin[curunit]) begin
                    seek_err[curunit] <= 1;
                    run <= 0;
                    readyout <= readyin;
                end
            end else begin
                if (run_tmp) begin
                    curunit <= sel;
                    run <= 1;
                    iniout[sel] <= inipend[sel];
                    seekout[sel] <= seekpend[sel];
                    inipend[sel] <= 0;
                    seekpend[sel] <= 0;

                    case (sel)
                        2'd0: dest0 <= destb0;
                        2'd1: dest1 <= destb1;
                        2'd2: dest2 <= destb2;
                        2'd3: dest3 <= destb3;
                    endcase
                end
            end
        end
    end

    assign busy = (inipend != 4'b0000) || (seekpend != 4'b0000) || (run);
    assign uselout = curunit;
    
    assign seek_pend = inipend | seekpend;

endmodule
