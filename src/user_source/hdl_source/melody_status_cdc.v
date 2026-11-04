// Read-only audio -> video mailbox. Payload is serializer-aligned playback
// state, immutable until capture/ack. Both domains share system reset.
module melody_status_cdc(
    input wire audio_clk,video_clk,reset,
    input wire [9:0] audio_status,
    output reg [9:0] video_status
);
    reg [9:0] held_status,sent_status;
    reg request_toggle,ack_toggle,capture_wait;
    reg [1:0] ack_sync,request_sync;
    always @(posedge audio_clk or posedge reset) begin
        if(reset)begin held_status<=0;sent_status<=0;request_toggle<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],ack_toggle};
            if(request_toggle==ack_sync[1] && audio_status!=sent_status)begin
                held_status<=audio_status;sent_status<=audio_status;request_toggle<=~request_toggle;
            end
        end
    end
    always @(posedge video_clk or posedge reset)begin
        if(reset)begin request_sync<=0;ack_toggle<=0;capture_wait<=0;video_status<=0;end
        else begin
            request_sync<={request_sync[0],request_toggle};
            if(!capture_wait && request_sync[1]!=ack_toggle)capture_wait<=1;
            else if(capture_wait)begin
                video_status<=held_status;ack_toggle<=request_sync[1];capture_wait<=0;
            end
        end
    end
endmodule


