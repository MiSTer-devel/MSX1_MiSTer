// TV80 Registers, technology independent
//
// Version : 0250 (+k05) (+m01)
//
// Copyright (c) 2002 Daniel Wallner (jesus@opencores.org)
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
// The latest version of this file can be found at:
//  http://www.opencores.org/cvsweb.shtml/t80/
//
// Limitations :
//
// File history :
//
//  0242 : Initial release
//  0244 : Changed to single register file
//  0250 : Version alignment by KdL 2017.10.23
//
//  +k01 : Version alignment by KdL 2010.10.25
//  +k02 : Version alignment by KdL 2018.05.14
//  +k03 : Version alignment by KdL 2019.05.20
//  +k04 : Separation of T800 from T80 by KdL 2021.02.01, then reverted on 2023.05.15
//  +k05 : Version alignment by KdL 2023.05.15
//
//  +m01 : Revrite to systemVerilog by Molekula 2025.01.26, original: https://github.com/gnogni/ocm-pld-dev.git 95aa5e2179f28c0d8028e17203909804ce6ff66b
//  +m02 : Savestate ports DOR / DIRSet / DIR as T80_Reg.vhd of the MiSTer T80 (T80(c) version 350, Sorgelig)

module TV80_Reg (
    input           Clk,
    input           CEN,
    input           WEH,
    input           WEL,
    input     [2:0] AddrA,
    input     [2:0] AddrB,
    input     [2:0] AddrC,
    input     [7:0] DIH,
    input     [7:0] DIL,
    output    [7:0] DOAH,
    output    [7:0] DOAL,
    output    [7:0] DOBH,
    output    [7:0] DOBL,
    output    [7:0] DOCH,
    output    [7:0] DOCL,
    output  [127:0] DOR,            // all pairs, physical order: [16n+15:16n] = pair n (H:L)
    input           DIRSet,         // load all pairs from DIR (works without CEN)
    input   [127:0] DIR
);

    typedef logic [7:0] Register_Image[8];
    Register_Image RegsH, RegsL;

    always_ff @( posedge Clk ) begin
        if ( DIRSet ) begin
            for (int n = 0; n < 8; n++) begin
                RegsL[n] <= DIR[16*n +: 8];
                RegsH[n] <= DIR[16*n + 8 +: 8];
            end
        end else if ( CEN ) begin
            if ( WEH ) begin
                RegsH[AddrA] <= DIH;
            end
            if ( WEL ) begin
                RegsL[AddrA] <= DIL;
            end
        end
    end

    genvar g;
    generate
        for (g = 0; g < 8; g++) begin : dor_pairs
            assign DOR[16*g +: 16] = {RegsH[g], RegsL[g]};
        end
    endgenerate

    assign DOAH = RegsH[AddrA];
    assign DOAL = RegsL[AddrA];
    assign DOBH = RegsH[AddrB];
    assign DOBL = RegsL[AddrB];
    assign DOCH = RegsH[AddrC];
    assign DOCL = RegsL[AddrC];

endmodule
