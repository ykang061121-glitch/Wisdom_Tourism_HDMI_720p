// Image layer only. No output from this observer controls buffer commit.
// The existing controller remains FRAMES_PER_STEP=2 (8 frames per half).
module picture_transition #(
    parameter COORD_BITS=10,
    parameter integer ACTIVE_WIDTH=640
)(
    input wire pixel_clk,reset,frame_boundary,de,
    input wire [COORD_BITS-1:0] x,y,
    input wire [23:0] rgb_in,
    input wire [2:0] fade_level,transition_state,
    input wire [1:0] pending_image_index,
    input wire scene_commit,display_valid,
    output reg [23:0] rgb_out,
    output reg [1:0] effect_mode,
    output reg [3:0] reveal_step
);
    reg [2:0] previous_state;
    reg next_effect,scene_seen,await_visible,committed_switch,check_frame;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin
            previous_state<=0;effect_mode<=0;reveal_step<=0;
            next_effect<=0;scene_seen<=0;await_visible<=0;committed_switch<=0;check_frame<=0;
        end
        else begin
            previous_state<=transition_state;
            check_frame<=frame_boundary;
            // The existing commit is BLACK, not yet a visible scene. First
            // boot does not count. A failed/cancelled pre-commit load cannot
            // touch this success token or advance the alternating sequence.
            if(scene_commit)begin
                scene_seen<=1;await_visible<=1;committed_switch<=scene_seen;
            end
            if(check_frame && await_visible && display_valid && fade_level!=0 &&
               (transition_state==4 || transition_state==0))begin
                await_visible<=0;
                if(committed_switch)next_effect<=~effect_mode[0];
            end
            // Entering OUT is one clock AFTER the CDC payload capture. At
            // this point the old picture is still fully visible (level=4).
            if(transition_state==2 && previous_state!=2)begin
                effect_mode<={1'b0,next_effect}; // independent of scene number
                reveal_step<=frame_boundary?7:8;
            end else if(transition_state==3)reveal_step<=0;
            else if(frame_boundary && transition_state==2 && reveal_step!=0)
                reveal_step<=reveal_step-1'b1;
            else if(frame_boundary && transition_state==4 && reveal_step<8)
                reveal_step<=reveal_step+1'b1;
            else if(transition_state==0 || transition_state==1)reveal_step<=8;
        end
    end
    wire [23:0] faded;
    video_fade original_fade(.pixel_clk(pixel_clk),.reset(reset),.de(de),
        .rgb_in(rgb_in),.fade_level(fade_level),.rgb_out(faded));
    wire [13:0] wipe_product=reveal_step*ACTIVE_WIDTH;
    wire [10:0] wipe_edge=wipe_product>>3; // constant /8, no runtime divider
    always @* begin
        rgb_out=rgb_in;
        if(effect_mode==0)rgb_out=faded;
        else if(transition_state==2 || transition_state==3 || transition_state==4)begin
            if(effect_mode==1 && !(x<wipe_edge))rgb_out=0;
        end
        // Independent hard guard: every mode is fully black at the original
        // FSM's level=0. Added masks can never expose a nonblack swap pixel.
        if(reset || !de || fade_level==0 || transition_state==3)rgb_out=0;
    end
endmodule
