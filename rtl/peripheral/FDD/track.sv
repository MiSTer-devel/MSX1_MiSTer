module track #(DELAYms = 3'd3, MAX_TRACKS = 80, ID = 0)
(
    input  logic        clk,
    input  logic        msclk,  //clk at 1ms
    input  logic        reset,
    input  logic        USEL,
    input  logic        READYn,
    input  logic        STEPn,
    input  logic        SDIRn,
    input  logic        SIDEn,
    input  logic        MOTORn,
    output logic        TRACK0n,
    output logic  [6:0] track,
    
    block_device_if.device_mp block_device[2],

    input  logic        disk_mounted,
    input  logic        disk_readonly,
    input  logic        disk_sides,

    output logic        track_ready,            // Track je nacten z SD
    input  logic [12:0] buffer_addr,
    output logic  [7:0] buffer_q
);

    logic [2:0] track_delay;       // MAX 8 ms
    logic [6:0] reg_track[2];
    logic last_STEPn;

    always_ff @(posedge clk) begin
        if (reset) begin
            reg_track <= '{7'd0, 7'd0};
            track_delay <= '0;
        end else begin
            last_STEPn <= STEPn;
            
            if (msclk && track_delay > 0) begin
                track_delay <= track_delay - 3'd1;
            end

            if (!STEPn && last_STEPn && track_delay == 0) begin
                if (SDIRn) begin
                    if (reg_track[USEL] < MAX_TRACKS) begin
                        reg_track[USEL] <= reg_track[USEL] + 7'd1;
                        track_delay <= DELAYms;
                    end
                end else begin
                    if (reg_track[USEL] > 0) begin
                        reg_track[USEL] <= reg_track[USEL] - 7'd1;
                        track_delay <= DELAYms;
                    end
                end
            end           
        end
    end

    assign track   = reg_track[USEL];
    assign TRACK0n = reg_track[USEL] != 0; //|| MOTORn; TODO

    track_buffer #(.ID(ID)) track_buffer (
        .clk(clk),
        .reset(reset),

        .track(track),
        .side(~SIDEn),
        .USEL(USEL),        

        .ready(track_ready),

        .block_device(block_device),

        .buffer_addr(buffer_addr),
        .buffer_q(buffer_q),

        .disk_mounted(disk_mounted),
        .disk_readonly(disk_readonly),
        .disk_sides(disk_sides)
    );

endmodule
