module opll
(
   input clk,
   input cen,
   input rst,
   input [7:0] din,
   input addr,
   input [2:0] wr,
   input [2:0] cs,
   output signed [15:0] sound
);

/*verilator tracing_off*/

assign sound = (cs[0] ? sound_OPL_A   : 16'd0) +
               (cs[1] ? sound_OPL_B   : 16'd0) +
               (cs[2] ? sound_OPL_int : 16'd0) ;

wire signed [15:0] sound_OPL_int, sound_OPL_A, sound_OPL_B;

IKAOPLL #(
    .FULLY_SYNCHRONOUS          (1                          ),
    .FAST_RESET                 (1                          ),
    .ALTPATCH_CONFIG_MODE       (0                          ),
    .USE_PIPELINED_MULTIPLIER   (1                          )
) ika_opll_opll_A (
    .i_XIN_EMUCLK               (clk                        ),
    .o_XOUT                     (                           ),

    .i_phiM_PCEN_n              (~cen                       ),

    .i_IC_n                     (~rst                       ),

    .i_ALTPATCH_EN              (1'b0                       ),

    .i_CS_n                     (~cs[0]                     ),
    .i_WR_n                     (~wr[0]                     ),
    .i_A0                       (addr                       ),

    .i_D                        (din                        ),
    .o_D                        (                           ),
    .o_D_OE                     (                           ),

    .o_DAC_EN_MO                (                           ),
    .o_DAC_EN_RO                (                           ),
    .o_IMP_NOFLUC_SIGN          (                           ),
    .o_IMP_NOFLUC_MAG           (                           ),
    .o_IMP_FLUC_SIGNED_MO       (                           ),
    .o_IMP_FLUC_SIGNED_RO       (                           ),
    .i_ACC_SIGNED_MOVOL         (5'sd9                      ),
    .i_ACC_SIGNED_ROVOL         (5'sd15                     ),
    .o_ACC_SIGNED_STRB          (                           ),
    .o_ACC_SIGNED               (sound_OPL_A                )
);

IKAOPLL #(
    .FULLY_SYNCHRONOUS          (1                          ),
    .FAST_RESET                 (1                          ),
    .ALTPATCH_CONFIG_MODE       (0                          ),
    .USE_PIPELINED_MULTIPLIER   (1                          )
) ika_opll_opll_B (
    .i_XIN_EMUCLK               (clk                        ),
    .o_XOUT                     (                           ),

    .i_phiM_PCEN_n              (~cen                       ),

    .i_IC_n                     (~rst                       ),

    .i_ALTPATCH_EN              (1'b0                       ),

    .i_CS_n                     (~cs[1]                     ),
    .i_WR_n                     (~wr[1]                     ),
    .i_A0                       (addr                       ),

    .i_D                        (din                        ),
    .o_D                        (                           ),
    .o_D_OE                     (                           ),

    .o_DAC_EN_MO                (                           ),
    .o_DAC_EN_RO                (                           ),
    .o_IMP_NOFLUC_SIGN          (                           ),
    .o_IMP_NOFLUC_MAG           (                           ),
    .o_IMP_FLUC_SIGNED_MO       (                           ),
    .o_IMP_FLUC_SIGNED_RO       (                           ),
    .i_ACC_SIGNED_MOVOL         (5'sd9                      ),
    .i_ACC_SIGNED_ROVOL         (5'sd15                     ),
    .o_ACC_SIGNED_STRB          (                           ),
    .o_ACC_SIGNED               (sound_OPL_B                )
);


IKAOPLL #(
    .FULLY_SYNCHRONOUS          (1                          ),
    .FAST_RESET                 (1                          ),
    .ALTPATCH_CONFIG_MODE       (0                          ),
    .USE_PIPELINED_MULTIPLIER   (1                          )
) ika_opll_int (
    .i_XIN_EMUCLK               (clk                        ),
    .o_XOUT                     (                           ),

    .i_phiM_PCEN_n              (~cen                       ),

    .i_IC_n                     (~rst                       ),

    .i_ALTPATCH_EN              (1'b0                       ),

    .i_CS_n                     (~cs[2]                     ),
    .i_WR_n                     (~wr[2]                     ),
    .i_A0                       (addr                       ),

    .i_D                        (din                        ),
    .o_D                        (                           ),
    .o_D_OE                     (                           ),

    .o_DAC_EN_MO                (                           ),
    .o_DAC_EN_RO                (                           ),
    .o_IMP_NOFLUC_SIGN          (                           ),
    .o_IMP_NOFLUC_MAG           (                           ),
    .o_IMP_FLUC_SIGNED_MO       (                           ),
    .o_IMP_FLUC_SIGNED_RO       (                           ),
    .i_ACC_SIGNED_MOVOL         (5'sd9                      ),
    .i_ACC_SIGNED_ROVOL         (5'sd15                     ),
    .o_ACC_SIGNED_STRB          (                           ),
    .o_ACC_SIGNED               (sound_OPL_int              )
);



endmodule