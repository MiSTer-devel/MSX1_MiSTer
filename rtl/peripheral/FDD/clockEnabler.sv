module clockEnabler #(
    parameter int clkFreq = MSX::CLK_CORE_HZ,
    parameter int targetFreq = 1000000
)(
    input  logic                                 clk,
    output logic                                 en
);
    
    localparam int maxCount = clkFreq / targetFreq - 1;

    logic [$clog2(maxCount)-1:0] counter;

    always_comb begin
        en = counter == 0;
    end

    // Generování enable signálu
    always_ff @(posedge clk) begin
        if (counter > 0) begin
            counter <= counter - 1'b1;
        end else begin
            counter <= ($clog2(maxCount))'(maxCount);
        end
    end

endmodule
