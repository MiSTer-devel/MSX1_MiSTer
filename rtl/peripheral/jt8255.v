/*  This file is part of JT8255.
    JT8255 program is free software: you can redistribute it and/or modify
    it under the terms of the MIT License

    JT8255 program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    You should have received a copy of the MIT License
    along with JT8255.  If not, see https://mit-license.org/

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 28-3-2021
 */
module jt8255(
    input               rst,
    input               clk,

    // CPU interface
    input       [1:0]   addr,
    input       [7:0]   din,
    output reg  [7:0]   dout,
    input               rdn,
    input               wrn,
    input               csn,

    // External pins to peripherals
    input       [7:0]   porta_din,
    input       [7:0]   portb_din,
    input       [7:0]   portc_din,

    output reg  [7:0]   porta_dout,
    output reg  [7:0]   portb_dout,
    output      [7:0]   portc_dout,

    input       [7:0]   porta_reset_default,
    input       [6:0]   control_reset_default
);

localparam ISINA=4, ISINB=1, ISINCL=0, ISINCH=3; // Control word bits
localparam INTRA=3, OBFA=7, ACKA=6, STBA=4, IBFA=5, // PC bits, mode 2
           INTRB=0, OBFB=1, ACKB=2, STBB=2, IBFB=1;

localparam INTEA_OBF=6, INTEA_IBF=4, INTEB=2;

reg  [6:0] ctrl;
reg  [7:0] latch_a, latch_b, latch_c;

wire       mode_b,
           isin_a, isin_b, isin_cl, isin_ch; // is input a,b,c...
wire [1:0] mode_a;

wire       write, read;
reg        last_write, last_read;

reg        inte_a_obf, inte_a_ibf, inte_b;
wire       acka, ackb, stba, stbb;

reg        last_acka, last_ackb, last_stba;
wire       last_stbb;

assign read   = !rdn && !csn;
assign write  = !wrn && !csn;
assign mode_b = ctrl[2];
assign mode_a = ctrl[6:5];

assign isin_a  = ctrl[ISINA];
assign isin_b  = ctrl[ISINB];
assign isin_cl = ctrl[ISINCL];
assign isin_ch = ctrl[ISINCH];

assign acka    = portc_din[ACKA];
assign stba    = portc_din[STBA];
assign ackb    = portc_din[ACKB];
assign stbb    = portc_din[STBB]; // this is the same as ackb
assign last_stbb = last_ackb;


// Mode control
// MSX change: sync reset, async reset with variable porta_reset_default became latches
always @(posedge clk) begin
    if( rst ) begin
        ctrl       <= control_reset_default;   // openMSX I8255::reset: all input (1Bh)
        latch_a    <= porta_reset_default;
        latch_b    <= 8'hff;
        latch_c    <= 8'hff;

        inte_a_ibf <= 0;
        inte_a_obf <= 0;
        inte_b     <= 0;

//        last_write <= 0;
        last_acka  <= 0;
        last_ackb  <= 0;
        last_stba  <= 0;
    end else begin
//        last_write <= write;
        last_acka  <= acka;
        last_ackb  <= ackb;
        last_stba  <= stba;

//        if( !write && last_write ) begin 
        if( write ) begin		  //Changed
            case( addr )
                2'd0: begin // Port A
                    if( !isin_a || mode_a[1] ) begin
                        latch_a <= din; // A is an output
                        if( mode_a!=0 ) begin
                            latch_c[OBFA] <= 0;
                            if(inte_a_obf) latch_c[INTRA] <= 0;  // interrupt pin
                        end
                    end
                end
                2'd1: begin // Port B
                    if( !isin_b ) begin
                        latch_b <= din; // B is an output
                        if( mode_b ) begin
                            latch_c[OBFB] <= 0;
                            if(inte_b) latch_c[INTRB] <= 0;  // interrupt pin
                        end
                    end                end
                2'd2: begin
                    if( mode_b )
                        inte_b <= din[INTEB];
                    else
                        latch_c[2:0] <= din[2:0];

                    if( (mode_a==0 || (mode_a[0]&&isin_a)) )
                        latch_c[7:6] <= din[7:6];

                    if( mode_a==0 || (mode_a[0]&&!isin_a) )
                        latch_c[5:4] <= din[5:4];

                    if( mode_a==0 )
                        latch_c[3] <= din[3];

                    if( mode_a[1] || (mode_a[0] && isin_a) )
                        inte_a_ibf <= din[INTEA_IBF];
                    if( mode_a[1] || (mode_a[0] && !isin_a) )
                        inte_a_obf <= din[INTEA_OBF];
                end
                2'd3: begin
                    if( din[7] ) begin
                        ctrl <= din[6:0];
                        if( !din[ISINCL] ) latch_c[3:0] <= 0;
                        if( !din[ISINCH] ) latch_c[7:4] <= 0;
                        if( !din[ISINB]  ) latch_b <= 0;
                        if( !din[ISINA]  ) latch_a <= 0;
                        inte_a_ibf <= 0;
                        inte_a_obf <= 0;
                        inte_b     <= 0;
                        if( din[2] ) begin
                            latch_c[IBFB] <= ~din[ISINB]; // start with safe IBF/OBF signals
                            latch_c[INTRB]<= ~din[ISINB];
                        end
                        if( din[6:5]!=0 ) begin
                            latch_c[IBFA] <= 0;
                            latch_c[OBFA] <= 1;
                            latch_c[INTRA]<= 0;
                        end
                    end else begin
                        latch_c[ din[3:1] ] <= din[0];
								if( din[3:1]==INTEA_OBF ) inte_a_obf <= din[0];
								if( din[3:1]==INTEA_IBF ) inte_a_ibf <= din[0];
								if( din[3:1]==INTEB ) inte_b <= din[0];
                    end
                end
            endcase
        end else begin
            // Input Buffer Full
            if( mode_b && isin_b && stbb && !last_stbb ) begin
                latch_c[IBFB] <= 1;
                if( inte_b ) latch_c[INTRB] <= 1;
            end
            if( (mode_a[1] || (mode_a[0] && isin_a)) && stba && !last_stba ) begin
                latch_c[IBFA] <= 1;
                if( inte_a_ibf ) latch_c[INTRA] <= 1;
            end

            if( mode_a!=2'd00 ) begin
					 // clears the interrupts
					 if(!inte_a_ibf && !inte_a_obf) latch_c[INTRA] <= 0; //Changed
					 // The peripheral reads
                if( (!isin_a || mode_a[1]) && acka && !last_acka ) begin
                    latch_c[INTRA] <= 1;
                    latch_c[OBFA]  <= 1;
                end
                // The CPU reads
                if( (isin_a || mode_a[1]) && read && !last_read && addr==2'd0 ) begin
                    latch_c[INTRA] <= 0;
                    latch_c[IBFA]  <= 0;
                end
            end
            if( mode_b ) begin
					 // clears the interrupts				
					 if(!inte_b) latch_c[INTRB] <= 0; //Changed				
                // The peripheral reads
                if( !isin_b && ackb && !last_ackb ) begin
                    latch_c[INTRB] <= 1;
                    latch_c[OBFB]  <= 1;
                end
                // The CPU reads
                if( isin_b && read && !last_read && addr==2'd1 ) begin
                    latch_c[INTRB] <= 0;
                    latch_c[IBFB]  <= 0;
                end
            end
        end
    end
end

// CPU interface
always @(posedge clk) begin
    if( rst ) begin
        dout      <= 8'hff;
        last_read <= 0;
    end else begin
        last_read <= read;
        if( read ) begin
            case( addr )
                2'd0: dout <= isin_a ? porta_din : latch_a;
                2'd1: dout <= isin_b ? portb_din : latch_b;
                2'd2: begin // Port C output depends on the mode
                    dout[7:4] <= isin_ch ? portc_din[7:4] : latch_c[7:4];
                    dout[3:0] <= isin_cl ? portc_din[3:0] : latch_c[3:0];
                    // Special modes
                    if( mode_b )
                        dout[2:0] <= { ackb, latch_c[1:0] };
                    if( mode_a!=0 )
                        dout[3] <= latch_c[INTRA];
                    if( (mode_a[0] && !isin_a) || mode_a[1] )
                        dout[5:4] <= { acka, latch_c[4] };
                    if( (mode_a[0] && isin_a) || mode_a[1] )
                        dout[7:6] <= { latch_c[OBFA], acka };
                end
                2'd3: dout <= { 1'b1, ctrl };
            endcase
        end
    end
end

// Output port registers
assign portc_dout = latch_c;

always @(posedge clk) begin
    porta_dout <= isin_a ? porta_din : latch_a;
    portb_dout <= isin_b ? portb_din : latch_b;
end

endmodule