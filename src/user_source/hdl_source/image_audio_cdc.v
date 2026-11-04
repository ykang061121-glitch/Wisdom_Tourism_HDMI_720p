// Bundled-data mailbox: source payload is immutable until the destination
// captures it and the acknowledgement returns. Only toggle bits are synced.
// Both domains share system reset. Busy updates coalesce to latest status.
module image_audio_cdc (
    input wire video_clk, video_reset,
    input wire display_valid,
    input wire [1:0] display_image,
    input wire audio_clk, audio_reset,
    output reg selection_update,
    output reg selection_valid,
    output reg [1:0] selection_image
);
    reg [2:0] held_status, sent_status;
    reg request_toggle, ack_toggle, capture_wait;
    reg [1:0] ack_sync, request_sync;
    wire [2:0] wanted_status = display_valid ? {1'b1,display_image} : 3'b000;
    wire busy = request_toggle != ack_sync[1];
    always @(posedge video_clk or posedge video_reset) begin
        if (video_reset) begin
            held_status<=0; sent_status<=0; request_toggle<=0; ack_sync<=0;
        end else begin
            ack_sync<={ack_sync[0],ack_toggle};
            if (!busy && wanted_status!=sent_status) begin
                held_status<=wanted_status;
                sent_status<=wanted_status;
                request_toggle<=~request_toggle;
            end
        end
    end
    always @(posedge audio_clk or posedge audio_reset) begin
        if (audio_reset) begin
            request_sync<=0; ack_toggle<=0; capture_wait<=0;
            selection_update<=0; selection_valid<=0; selection_image<=0;
        end else begin
            request_sync<={request_sync[0],request_toggle};
            selection_update<=0;
            if (!capture_wait && request_sync[1]!=ack_toggle)
                capture_wait<=1;
            else if (capture_wait) begin
                // One extra settling cycle AFTER the two toggle stages.
                {selection_valid,selection_image}<=held_status;
                selection_update<=1;
                ack_toggle<=request_sync[1];
                capture_wait<=0;
            end
        end
    end
endmodule
