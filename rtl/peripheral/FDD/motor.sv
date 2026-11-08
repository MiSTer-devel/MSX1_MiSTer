module motor #(parameter TIMEOUTms = 16'd30000, DELAYms = 3'd3) (
    input  logic        clk,
    input  logic        msclk,  // 1ms clock
    input  logic        reset,
    input  logic        USEL,
    input  logic        MOTORn,
    output logic  [1:0] motor_run
);

    logic [15:0] motor_timeout[3:0];  // Použití logického typu místo int
    logic [2:0]  motor_delay[3:0];    // Maximální hodnota 8 ms, stačí 3 bity

    genvar i;
    generate
        for (i = 0; i < 2; i++) begin : MOTOR_I
            always_ff @(posedge clk) begin
                if (reset) begin
                    motor_timeout[i] <= 0;
                    motor_delay[i]   <= DELAYms;
                end else if (USEL == i) begin
                    if (!MOTORn) begin
                        if (motor_delay[i] != 0 && msclk) 
                            motor_delay[i] <= motor_delay[i] - 3'd1;  // Probíhá rozjezd
                        else 
                            motor_timeout[i] <= TIMEOUTms;         // Motor běží
                    end else if (motor_timeout[i] > 0 && msclk) begin
                        motor_timeout[i] <= motor_timeout[i] - 16'd1;  // Čekání na vypnutí
                    end else begin
                        motor_delay[i] <= DELAYms;                 // Reset rozjezdu po vypnutí
                    end
                end else if (motor_timeout[i] > 0 && msclk) begin
                    motor_timeout[i] <= motor_timeout[i] - 16'd1;      // Čekání na vypnutí (ostatní motory)
                end else begin
                    motor_delay[i] <= DELAYms;
                end
            end
            
            assign motor_run[i] = (motor_timeout[i] != 0);
        end
    endgenerate

endmodule