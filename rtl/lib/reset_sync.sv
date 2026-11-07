// Reset synchronizer: asynchronous assert, synchronous release after STAGES clk edges.
// Asserts even while clk is stopped (e.g. PLL in reset), releases cleanly in the domain.
module reset_sync #(parameter STAGES = 2) (
    input  clk,
    input  arst,        // asynchronous, active high
    output rst          // synchronous release, active high
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [STAGES-1:0] sync = '1;

    always_ff @(posedge clk or posedge arst) begin
        if (arst) sync <= '1;
        else      sync <= {sync[STAGES-2:0], 1'b0};
    end

    assign rst = sync[STAGES-1];
endmodule
