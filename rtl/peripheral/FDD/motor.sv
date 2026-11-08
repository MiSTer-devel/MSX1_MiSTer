// Spindle motors of the two drives. MOTORn applies to the selected drive; the motor runs
// SPINUP_MS after it is switched on and keeps running OFF_MS after it is switched off
// (openMSX motor_off_timeout_ms, 0 for most interfaces).
module motor #(parameter int SPINUP_MS = 3, parameter int OFF_MS = 0)
(
    input  logic        clk,
    input  logic        msclk,          // 1 ms enable
    input  logic        reset,
    input  logic        USEL,
    input  logic        MOTORn,
    output logic  [1:0] motor_run
);
    logic  [2:0] spin[2];
    logic [15:0] hold[2];

    genvar i;
    generate
        for (i = 0; i < 2; i++) begin : MOTOR_I
            always_ff @(posedge clk) begin
                if (reset) begin
                    spin[i] <= '0;
                    hold[i] <= '0;
                end else if (USEL == i && !MOTORn) begin
                    hold[i] <= 16'(OFF_MS);
                    if (msclk && spin[i] != 3'(SPINUP_MS)) spin[i] <= spin[i] + 3'd1;
                end else if (hold[i] != '0) begin
                    if (msclk) hold[i] <= hold[i] - 16'd1;
                end else begin
                    spin[i] <= '0;
                end
            end
            assign motor_run[i] = spin[i] == 3'(SPINUP_MS);
        end
    endgenerate

endmodule
