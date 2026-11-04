`ifndef SPECTRUM_SNAPSHOT_CDC_V
`define SPECTRUM_SNAPSHOT_CDC_V
// Coherent bundled-data mailbox, followed by a video-frame envelope.
// Both resets MUST be asserted together; each may be released on its own clock.
// The display enable intentionally is not an input: hidden spectra keep running.
module spectrum_snapshot_cdc #(
    parameter integer DECAY_PER_FRAME = 8,
    parameter integer STALE_FRAMES = 6
)(
    input  wire         src_clk,
    input  wire         src_reset,
    input  wire         src_snapshot_valid,
    input  wire [127:0] src_levels,
    output wire         src_ready,
    input  wire         video_clk,
    input  wire         video_reset,
    input  wire         frame_boundary,
    output reg  [127:0] frame_levels,
    output reg          frame_commit,
    output reg          received_pulse
);
    reg [127:0] src_hold;
    reg src_request_toggle;
    (* ASYNC_REG = "TRUE" *) reg [1:0] src_ack_sync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] dst_request_sync;
    reg [127:0] dst_data_sample0, dst_data_sample1;
    reg [127:0] pending_levels;
    reg dst_ack_toggle;
    localparam integer AGE_BITS = (STALE_FRAMES < 2) ? 1 : $clog2(STALE_FRAMES+1);
    reg [AGE_BITS-1:0] stale_age;
    wire dst_capture = dst_request_sync[2] != dst_ack_toggle;
    wire stale = stale_age >= STALE_FRAMES;
    assign src_ready = src_request_toggle == src_ack_sync[1];

    // Request and held data are launched together. Only the toggle crosses
    // synchronizers; the 128-bit payload cannot change before the ACK returns.
    // A valid pulse while !src_ready is dropped, never partly accepted.
    always @(posedge src_clk or posedge src_reset) begin
        if (src_reset) begin
            src_hold <= 128'd0;
            src_request_toggle <= 1'b0;
            src_ack_sync <= 2'b00;
        end else begin
            src_ack_sync <= {src_ack_sync[0], dst_ack_toggle};
            if (src_snapshot_valid && src_ready) begin
                src_hold <= src_levels;
                src_request_toggle <= ~src_request_toggle;
            end
        end
    end

    // Two data sampling registers plus THREE request synchronizer stages give
    // the stable bundle a complete extra destination cycle before capture.
    // ACK is returned only after the coherent local pending copy is made.
    // pending_levels can change mid-frame; frame_levels only changes at the
    // existing blanking boundary. A capture coincident with that boundary is
    // intentionally shown on the next frame (old pending value wins).
    integer band;
    reg [7:0] current_level, target_level;
    always @(posedge video_clk or posedge video_reset) begin
        if (video_reset) begin
            dst_data_sample0 <= 128'd0;
            dst_data_sample1 <= 128'd0;
            dst_request_sync <= 3'b000;
            pending_levels <= 128'd0;
            dst_ack_toggle <= 1'b0;
            frame_levels <= 128'd0;
            frame_commit <= 1'b0;
            received_pulse <= 1'b0;
            stale_age <= STALE_FRAMES;
            current_level = 8'd0;
            target_level = 8'd0;
        end else begin
            dst_data_sample0 <= src_hold;
            dst_data_sample1 <= dst_data_sample0;
            dst_request_sync <= {dst_request_sync[1:0], src_request_toggle};
            frame_commit <= frame_boundary;
            received_pulse <= dst_capture;
            if (dst_capture) begin
                pending_levels <= dst_data_sample1;
                dst_ack_toggle <= dst_request_sync[2];
                stale_age <= 0;
            end else if (frame_boundary && !stale) begin
                stale_age <= stale_age + 1'b1;
            end
            if (frame_boundary) begin
                for (band=0; band<16; band=band+1) begin
                    current_level = frame_levels[band*8 +: 8];
                    target_level = stale ? 8'd0 : pending_levels[band*8 +: 8];
                    if (target_level >= current_level)
                        frame_levels[band*8 +: 8] <= target_level;
                    else if ((current_level-target_level) <= DECAY_PER_FRAME)
                        frame_levels[band*8 +: 8] <= target_level;
                    else
                        frame_levels[band*8 +: 8] <= current_level - DECAY_PER_FRAME;
                end
            end
        end
    end
endmodule
`endif
