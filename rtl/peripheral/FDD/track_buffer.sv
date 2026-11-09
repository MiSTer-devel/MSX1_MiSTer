// Track buffer: keeps the sectors of the track under the head (drive, cylinder, head) and
// reloads them from the drive's image (HPS block device) when the head moves to another
// track or the image is (re)mounted. One load at a time; a load in progress is finished
// and then the current track is loaded. 'ready' only when the buffer holds that track.
module track_buffer #(parameter ID = 0)
(
    input  logic        clk,
    input  logic        reset,
    block_device_if.device_mp block_device[2],
    input  logic        want,           // a recorded track is under the head
    input  logic        drive,
    input  logic  [6:0] track,
    input  logic        head,
    input  logic        disk_ds,        // image geometry of the selected drive
    input  logic  [4:0] spt,
    input  logic  [1:0] changed,        // image of drive i (re)mounted (1 clk)
    input  logic [12:0] buffer_addr,
    output logic  [7:0] buffer_q,
    output logic        ready
);
    logic [6:0] buf_track;
    logic       buf_drive, buf_head;
    logic       buf_valid, stale, busy, acked;
    logic [1:0] rd;
    logic [31:0] rd_lba;
    logic  [5:0] rd_cnt;

    wire  ack   = buf_drive ? block_device[1].ack : block_device[0].ack;
    wire  match = buf_valid && !stale && {buf_drive, buf_track, buf_head} == {drive, track, head};
    assign ready = want && match;

    wire  [7:0] trk_side = disk_ds ? {track, head} : {1'b0, track};     // track * sides + head
    wire [12:0] lba      = {5'd0, trk_side} * {8'd0, spt};

    always_ff @(posedge clk) begin
        if (reset) begin
            buf_valid <= 1'b0;
            stale     <= 1'b0;
            busy      <= 1'b0;
            acked     <= 1'b0;
            rd        <= '0;
        end else begin
            if (!busy) begin
                if (want && !match) begin
                    {buf_drive, buf_track, buf_head} <= {drive, track, head};
                    buf_valid <= 1'b0;
                    stale     <= 1'b0;
                    busy      <= 1'b1;
                    acked     <= 1'b0;
                    rd[drive] <= 1'b1;
                    rd_lba    <= {19'd0, lba};
                    rd_cnt    <= {1'b0, spt - 5'd1};
                end
            end else begin
                if (ack) begin
                    acked <= 1'b1;
                    rd    <= '0;
                end else if (acked) begin               // transfer finished
                    busy      <= 1'b0;
                    buf_valid <= 1'b1;
                end
            end
            if (changed[buf_drive]) stale <= 1'b1;     // also during a load: reload after it
        end
    end

    assign block_device[0].rd      = rd[0];
    assign block_device[1].rd      = rd[1];
    assign block_device[0].lba     = rd_lba;
    assign block_device[1].lba     = rd_lba;
    assign block_device[0].blk_cnt = rd_cnt;
    assign block_device[1].blk_cnt = rd_cnt;
    assign block_device[0].wr = 1'b0;   // write not implemented yet
    assign block_device[1].wr = 1'b0;

    // HPS writes the sectors through port A; buff_wr is shared by all virtual disks,
    // only the transfer acknowledged for this drive may write.
    wire [13:0] sd_addr = buf_drive ? block_device[1].buff_addr : block_device[0].buff_addr;
    wire  [7:0] sd_data = buf_drive ? block_device[1].buff_dout : block_device[0].buff_dout;
    wire        sd_wr   = buf_drive ? block_device[1].buff_wr && block_device[1].ack
                                    : block_device[0].buff_wr && block_device[0].ack;
    wire  [7:0] q_a;
    assign block_device[0].buff_din = q_a;
    assign block_device[1].buff_din = q_a;

    dpram #(.addr_width(13), .mem_name(ID)) track_dpram (
        .clock(clk),
        .address_a(sd_addr[12:0]),
        .data_a(sd_data),
        .wren_a(sd_wr),
        .q_a(q_a),
        .address_b(buffer_addr),
        .wren_b(1'b0),
        .data_b(8'h00),
        .q_b(buffer_q)
    );

endmodule
