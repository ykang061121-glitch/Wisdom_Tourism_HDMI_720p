// Display-only observer. The original SD dwell timer and commit controller
// have no feedback from this module. All visible changes occur in blanking.
module playback_progress_display #(parameter CONTINUOUS_COMMITS=0)(
    input wire src_clk,src_reset,
    input wire [9:0] src_progress, // {actual timer running, 0..256 units}
    input wire src_auto,
    input wire [1:0] src_interval,
    input wire [7:0] src_error,
    input wire src_commit_pulse,
    input wire video_clk,video_reset,frame_boundary,
    input wire video_commit,video_valid,video_busy,
    input wire [2:0] video_fade_level,video_state,
    output reg visible,
    output reg [8:0] display_units,
    output reg scene_start_pulse,
    output reg [1:0] display_phase
);
    localparam HIDDEN=0,GROW=1,HOLD=2,WAIT_STABLE=3;
    reg source_epoch,expired;
    always @(posedge src_clk or posedge src_reset)begin
        if(src_reset)begin source_epoch<=0;expired<=0;end
        else begin
            if(src_commit_pulse)source_epoch<=~source_epoch;
            // Retain the one-clock timer expiration until the real commit ACK.
            // A K3 change during an already-started transfer cannot erase it.
            if(src_commit_pulse || !src_auto || src_error!=0)expired<=0;
            else if(src_progress[8:0]==9'd256)expired<=1;
        end
    end
    // One coherent bundle: epoch + period + mode/error + sticky expiration +
    // actual timer data. Never sample a changing count as an asynchronous bus.
    wire [15:0] snapshot;
    osd_status_cdc #(.WIDTH(16)) mailbox(
        .src_clk(src_clk),.src_reset(src_reset),
        .src_status({source_epoch,src_interval,src_auto,(src_error!=0),expired,src_progress}),
        .dst_clk(video_clk),.dst_reset(video_reset),.dst_status(snapshot));
    reg video_epoch,await_scene,check_frame;
    reg [1:0] previous_interval;
    wire matching_scene=(snapshot[15]==video_epoch);
    wire auto_valid=snapshot[12] && !snapshot[11] && video_valid;
    // The original commit is BLACK. A scene actually starts on the first
    // later blanking boundary whose NEW fade level enables image pixels.
    // With the unchanged FRAMES_PER_STEP=2, wipe/blinds also have reveal>0.
    wire first_active=(await_scene || (CONTINUOUS_COMMITS && video_commit)) && video_valid && video_fade_level!=0 &&
                      (video_state==4 || video_state==0);
    always @(posedge video_clk or posedge video_reset)begin
        if(video_reset)begin
            video_epoch<=0;await_scene<=0;check_frame<=0;previous_interval<=2;
            visible<=0;display_units<=0;display_phase<=HIDDEN;scene_start_pulse<=0;
        end else begin
            check_frame<=frame_boundary;
            scene_start_pulse<=0;
            if(video_commit)begin video_epoch<=~video_epoch;await_scene<=1;end
            // One cycle after the original boundary: consume the FSM's updated
            // fade/commit values, still safely before the active raster.
            if(check_frame)begin
                previous_interval<=snapshot[14:13];
                if(first_active)begin await_scene<=0;scene_start_pulse<=1;end
                if(!auto_valid)begin
                    visible<=0;display_units<=0;display_phase<=HIDDEN;
                end else if(first_active)begin
                    visible<=1;display_units<=0;display_phase<=WAIT_STABLE;
                end else if(await_scene || video_commit)begin
                    // Keep the previous bar through the successful BLACK commit.
                    visible<=1;display_phase<=HOLD;
                end else if(matching_scene && snapshot[10])begin
                    visible<=1;display_units<=256;display_phase<=HOLD;
                end else if(video_busy)begin
                    // Early K2 in AUTO freezes the true partial value instead
                    // of inventing elapsed time; expiry may later promote FULL.
                    visible<=1;display_phase<=HOLD;
                end else if(!matching_scene || display_phase==HIDDEN)begin
                    visible<=1;display_units<=0;display_phase<=WAIT_STABLE;
                end else if(snapshot[14:13]!=previous_interval)begin
                    visible<=1;display_units<=0;display_phase<=WAIT_STABLE;
                end else if(snapshot[9])begin
                    visible<=1;display_units<=snapshot[8:0];display_phase<=GROW;
                end else if(display_phase!=HOLD)begin
                    visible<=1;display_units<=0;display_phase<=WAIT_STABLE;
                end
            end
        end
    end
endmodule
