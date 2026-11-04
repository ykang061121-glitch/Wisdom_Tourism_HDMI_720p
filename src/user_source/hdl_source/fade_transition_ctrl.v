module fade_transition_ctrl #(
    parameter integer FRAMES_PER_STEP = 2
)(
    input  wire       video_clk,
    input  wire       reset,
    input  wire       frame_start_pulse,
    input  wire       transition_request_pulse,
    input  wire       transition_cancel_pulse,
    input  wire       next_frame_ready,
    input  wire [1:0] pending_buf_idx,
    input  wire [1:0] pending_image_idx,

    output reg  [1:0] display_buf_idx,
    output reg  [1:0] display_image_idx,
    output reg        display_valid,
    output reg  [2:0] fade_level,
    output reg        transition_busy,
    output reg  [2:0] transition_state,
    output reg        swap_commit_pulse,
    output reg        transition_done_pulse
);

localparam [2:0] ST_IDLE       = 3'd0;
localparam [2:0] ST_WAIT_READY = 3'd1;
localparam [2:0] ST_FADE_OUT   = 3'd2;
localparam [2:0] ST_BLACK_SWAP = 3'd3;
localparam [2:0] ST_FADE_IN    = 3'd4;

localparam [2:0] FADE_000 = 3'd0;
localparam [2:0] FADE_100 = 3'd4;

reg [15:0] frame_hold_count;

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
    end else begin
        swap_commit_pulse <= 1'b0;
        transition_done_pulse <= 1'b0;

        if (transition_cancel_pulse) begin
            // Failed loads keep the old buffer. No commit is generated.
            transition_busy <= 0;
            transition_state <= ST_IDLE;
            fade_level <= display_valid ? FADE_100 : FADE_000;
            frame_hold_count <= 0;
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
                    if (display_valid) begin
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
                    frame_hold_count  <= 16'd0;
                    transition_state  <= ST_FADE_IN;
                end
            end

            ST_FADE_IN: begin
                transition_busy <= 1'b1;
                if (frame_start_pulse) begin
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
