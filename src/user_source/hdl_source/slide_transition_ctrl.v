module slide_transition_ctrl #(
    parameter integer FRAMES_PER_STEP = 2
)(
    input  wire       video_clk,
    input  wire       reset,
    input  wire       frame_start_pulse,
    input  wire       transition_request_pulse,
    input  wire       transition_cancel_pulse,
    input  wire       next_frame_ready,
    input  wire       frame_complete,
    input  wire [1:0] pending_buf_idx,
    input  wire [1:0] pending_image_idx,

    output reg  [1:0] display_buf_idx,
    output reg  [1:0] display_image_idx,
    output reg        display_valid,
    output reg  [2:0] fade_level,
    output reg        transition_busy,
    output reg  [2:0] transition_state,
    output reg        swap_commit_pulse,
    output reg        transition_done_pulse,
    output wire       slide_active,
    output reg [10:0] slide_shift,
    output reg [1:0]  slide_target,
    output reg        active_style
);

localparam [2:0] ST_IDLE       = 3'd0;
localparam [2:0] ST_WAIT_READY = 3'd1;
localparam [2:0] ST_FADE_OUT   = 3'd2;
localparam [2:0] ST_BLACK_SWAP = 3'd3;
localparam [2:0] ST_FADE_IN    = 3'd4;
localparam [2:0] ST_SLIDE      = 3'd5;

localparam [2:0] FADE_000 = 3'd0;
localparam [2:0] FADE_100 = 3'd4;

reg [15:0] frame_hold_count;
reg next_style,frame_complete_seen,slide_started,slide_post,cancel_pending;
assign slide_active=(transition_state==ST_SLIDE);

always @(posedge video_clk or posedge reset) begin
    if (reset) begin
        display_buf_idx      <= 2'd0;
        display_image_idx    <= 2'd0;
        display_valid        <= 1'b0;
        fade_level           <= FADE_000;
        transition_busy      <= 1'b0;
        transition_state     <= ST_IDLE;
        frame_hold_count     <= 16'd0;
        swap_commit_pulse    <= 1'b0;
        transition_done_pulse<= 1'b0;
        slide_shift<=0;slide_target<=0;active_style<=0;next_style<=0;
        frame_complete_seen<=0;slide_started<=0;slide_post<=0;cancel_pending<=0;
    end else begin
        swap_commit_pulse <= 1'b0;
        transition_done_pulse <= 1'b0;
        if(frame_complete)frame_complete_seen<=1;
        if(frame_start_pulse)frame_complete_seen<=0;
        if(transition_cancel_pulse && slide_active)cancel_pending<=1;

        if ((transition_cancel_pulse && !slide_active) ||
            (slide_active && frame_start_pulse && (cancel_pending||transition_cancel_pulse))) begin
            // Failed loads keep the old buffer. No commit is generated.
            transition_busy <= 0;
            transition_state <= ST_IDLE;
            fade_level <= display_valid ? FADE_100 : FADE_000;
            frame_hold_count <= 0;
            slide_shift<=0;slide_started<=0;slide_post<=0;cancel_pending<=0;
        end else case (transition_state)
            ST_IDLE: begin
                transition_busy  <= 1'b0;
                frame_hold_count <= 16'd0;
                fade_level       <= display_valid ? FADE_100 : FADE_000;
                if (transition_request_pulse) begin
                    transition_busy  <= 1'b1;
                    transition_state <= ST_WAIT_READY;
                end
            end

            ST_WAIT_READY: begin
                transition_busy <= 1'b1;
                // Do not fade the old picture until the complete new frame is
                // known to be in SDRAM.  This avoids an unbounded black wait.
                if (next_frame_ready) begin
                    frame_hold_count <= 16'd0;
                    active_style<=display_valid?next_style:1'b0;
                    slide_target<=pending_buf_idx;
                    if(display_valid && next_style)begin
                        fade_level<=FADE_100;slide_shift<=0;slide_started<=0;slide_post<=0;
                        transition_state<=ST_SLIDE;
                    end else if (display_valid) begin
                        fade_level       <= FADE_100;
                        transition_state <= ST_FADE_OUT;
                    end else begin
                        fade_level       <= FADE_000;
                        transition_state <= ST_BLACK_SWAP;
                    end
                end
            end

            ST_FADE_OUT: begin
                transition_busy <= 1'b1;
                if (frame_start_pulse) begin
                    if (frame_hold_count == FRAMES_PER_STEP - 1) begin
                        frame_hold_count <= 16'd0;
                        if (fade_level == 3'd1) begin
                            fade_level       <= FADE_000;
                            transition_state <= ST_BLACK_SWAP;
                        end else begin
                            fade_level <= fade_level - 3'd1;
                        end
                    end else begin
                        frame_hold_count <= frame_hold_count + 16'd1;
                    end
                end
            end

            ST_BLACK_SWAP: begin
                transition_busy <= 1'b1;
                fade_level      <= FADE_000;
                // All four safety conditions are local and explicit here:
                // ready, black, BLACK_SWAP state, and a video frame boundary.
                if (frame_start_pulse && next_frame_ready &&
                    (fade_level == FADE_000)) begin
                    display_buf_idx   <= pending_buf_idx;
                    display_image_idx <= pending_image_idx;
                    display_valid     <= 1'b1;
                    swap_commit_pulse <= 1'b1;
                    if(display_valid)next_style<=1; // first post-boot success was FADE
                    frame_hold_count  <= 16'd0;
                    transition_state  <= ST_FADE_IN;
                end
            end

            ST_FADE_IN: begin
                transition_busy <= 1'b1;
                if(slide_post && frame_start_pulse)begin
                    slide_post<=0;transition_busy<=0;transition_state<=ST_IDLE;transition_done_pulse<=1;
                end else if (frame_start_pulse) begin
                    if (frame_hold_count == FRAMES_PER_STEP - 1) begin
                        frame_hold_count <= 16'd0;
                        if (fade_level == 3'd3) begin
                            fade_level       <= FADE_100;
                            transition_busy  <= 1'b0;
                            transition_state <= ST_IDLE;
                            transition_done_pulse <= 1'b1;
                        end else begin
                            fade_level <= fade_level + 3'd1;
                        end
                    end else begin
                        frame_hold_count <= frame_hold_count + 16'd1;
                    end
                end
            end

            ST_SLIDE:begin
                transition_busy<=1;fade_level<=FADE_100;
                if(frame_start_pulse)begin
                    if(!slide_started)begin
                        // The ready toggle can be visible one video clock before
                        // the mailbox payload register is captured. At this first
                        // blanking boundary the held payload is already settled.
                        // Freeze the target before any nonzero-shift read request.
                        slide_target<=pending_buf_idx;
                        slide_started<=1;slide_shift<=0;
                    end
                    else if(frame_complete_seen)begin
                        if(slide_shift==1280)begin
                            // A complete all-new active raster already passed.
                            // Commit identity only here; release source ownership
                            // via DONE on the following boundary, never same pulse.
                            display_buf_idx<=slide_target;
                            display_image_idx<=pending_image_idx;
                            swap_commit_pulse<=1;next_style<=0;
                            slide_shift<=0;slide_post<=1;transition_state<=ST_FADE_IN;
                        end else slide_shift<=slide_shift+11'd40;
                    end
                end
            end

            default: begin
                display_buf_idx   <= 2'd0;
                display_image_idx <= 2'd0;
                display_valid     <= 1'b0;
                fade_level        <= FADE_000;
                transition_busy   <= 1'b0;
                transition_state  <= ST_IDLE;
                frame_hold_count  <= 16'd0;
            end
        endcase
    end
end

endmodule
