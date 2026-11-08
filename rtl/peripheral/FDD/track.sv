// Head position of the two drives: a STEP pulse (falling edge) moves the head of the selected
// drive in the SDIR direction (1 = in). The stop is past the last track of a disk, as in a real
// drive (openMSX RealDrive: 85).
module track #(parameter int MAX_TRACK = 85)
(
    input  logic        clk,
    input  logic        reset,
    input  logic        USEL,
    input  logic        STEPn,
    input  logic        SDIRn,
    output logic  [6:0] track           // head position of the selected drive
);
    logic [6:0] head[2];
    logic       last_STEPn;

    always_ff @(posedge clk) begin
        last_STEPn <= STEPn;
        if (reset) begin
            head <= '{7'd0, 7'd0};
        end else if (!STEPn && last_STEPn) begin
            if (SDIRn) begin
                if (head[USEL] < 7'(MAX_TRACK)) head[USEL] <= head[USEL] + 7'd1;
            end else begin
                if (head[USEL] != 7'd0) head[USEL] <= head[USEL] - 7'd1;
            end
        end
    end

    assign track = head[USEL];

endmodule
