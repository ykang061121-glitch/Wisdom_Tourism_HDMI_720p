`timescale 1ns/1ps

module tb_fade_transition;

localparam [2:0] ST_IDLE       = 3'd0;
localparam [2:0] ST_WAIT_READY = 3'd1;
localparam [2:0] ST_FADE_OUT   = 3'd2;
localparam [2:0] ST_BLACK_SWAP = 3'd3;
localparam [2:0] ST_FADE_IN    = 3'd4;

reg        src_clk = 1'b0;
reg        video_clk = 1'b0;
reg        reset = 1'b1;
reg        src_request_toggle = 1'b0;
reg        src_ready_toggle = 1'b0;
reg [3:0]  src_pending_payload = 4'd0;
reg        frame_start_pulse = 1'b0;

wire       src_commit_pulse;
wire       src_transition_done_pulse;
wire       dst_request_pulse;
wire       dst_next_frame_ready;
wire [3:0] dst_pending_payload;
wire [1:0] display_buf_idx;
wire [1:0] display_image_idx;
wire       display_valid;
wire [2:0] fade_level;
wire       transition_busy;
wire [2:0] transition_state;
wire       swap_commit_pulse;
wire       transition_done_pulse;

integer swap_count = 0;
integer commit_ack_count = 0;
integer done_ack_count = 0;

always #7 src_clk = ~src_clk;
always #5 video_clk = ~video_clk;

fade_transition_cdc u_cdc (
    .src_cancel_toggle(1'b0), .dst_cancel_pulse(),
    .src_clk             (src_clk),
    .src_reset           (reset),
    .src_request_toggle  (src_request_toggle),
    .src_ready_toggle    (src_ready_toggle),
    .src_pending_payload (src_pending_payload),
    .src_commit_pulse    (src_commit_pulse),
    .src_transition_done_pulse(src_transition_done_pulse),
    .dst_clk             (video_clk),
    .dst_reset           (reset),
    .dst_request_pulse   (dst_request_pulse),
    .dst_next_frame_ready(dst_next_frame_ready),
    .dst_pending_payload (dst_pending_payload),
    .dst_commit_pulse    (swap_commit_pulse),
    .dst_transition_done_pulse(transition_done_pulse)
);

fade_transition_ctrl #(
    .FRAMES_PER_STEP(2)
) u_ctrl (
    .video_clk               (video_clk),
    .reset                   (reset),
    .frame_start_pulse       (frame_start_pulse),
    .transition_request_pulse(dst_request_pulse),
    .transition_cancel_pulse(1'b0),
    .next_frame_ready        (dst_next_frame_ready),
    .pending_buf_idx         (dst_pending_payload[1:0]),
    .pending_image_idx       (dst_pending_payload[3:2]),
    .display_buf_idx         (display_buf_idx),
    .display_image_idx       (display_image_idx),
    .display_valid           (display_valid),
    .fade_level              (fade_level),
    .transition_busy         (transition_busy),
    .transition_state        (transition_state),
    .swap_commit_pulse       (swap_commit_pulse),
    .transition_done_pulse   (transition_done_pulse)
);

always @(negedge video_clk) begin
    if (!reset && swap_commit_pulse) begin
        swap_count = swap_count + 1;
        if (fade_level !== 3'd0)
            $fatal(1, "BUFFER_SWAP_WHILE_NONBLACK level=%0d", fade_level);
    end
end

always @(posedge src_clk) begin
    if (!reset && src_commit_pulse)
        commit_ack_count = commit_ack_count + 1;
    if (!reset && src_transition_done_pulse)
        done_ack_count = done_ack_count + 1;
end

task wait_state;
    input [2:0] expected;
    integer timeout;
    begin
        timeout = 0;
        while ((transition_state !== expected) && (timeout < 100)) begin
            @(posedge video_clk);
            timeout = timeout + 1;
        end
        #1;
        if (transition_state !== expected)
            $fatal(1, "FAIL wait state expected=%0d actual=%0d", expected, transition_state);
    end
endtask

task pulse_frame;
    begin
        @(negedge video_clk);
        frame_start_pulse = 1'b1;
        @(negedge video_clk);
        frame_start_pulse = 1'b0;
        #1;
    end
endtask

task send_request;
    begin
        @(negedge src_clk);
        src_request_toggle = ~src_request_toggle;
        wait_state(ST_WAIT_READY);
    end
endtask

task publish_ready;
    input [1:0] image_idx;
    input [1:0] buffer_idx;
    integer timeout;
    begin
        @(negedge src_clk);
        src_pending_payload = {image_idx, buffer_idx};
        src_ready_toggle = ~src_ready_toggle;
        timeout = 0;
        while (!dst_next_frame_ready && (timeout < 100)) begin
            @(posedge video_clk);
            timeout = timeout + 1;
        end
        #1;
        if (!dst_next_frame_ready)
            $fatal(1, "FAIL ready CDC timeout");
        if (dst_pending_payload !== {image_idx, buffer_idx})
            $fatal(1, "FAIL bundled payload expected=%b actual=%b",
                   {image_idx, buffer_idx}, dst_pending_payload);
    end
endtask

task expect_level;
    input [2:0] expected;
    input [255:0] case_name;
    begin
        if (fade_level !== expected)
            $fatal(1, "FAIL %0s expected level=%0d actual=%0d",
                   case_name, expected, fade_level);
    end
endtask

task advance_one_fade_step;
    input [2:0] old_level;
    input [2:0] new_level;
    begin
        pulse_frame;
        expect_level(old_level, "level changed before FRAMES_PER_STEP");
        // Also prove no pixel-clock-only update between frame boundaries.
        repeat (3) @(posedge video_clk);
        #1;
        expect_level(old_level, "level changed outside frame boundary");
        pulse_frame;
        expect_level(new_level, "level did not change at frame boundary");
    end
endtask

task wait_commit_ack;
    input integer expected_count;
    integer timeout;
    begin
        timeout = 0;
        while ((commit_ack_count < expected_count) && (timeout < 100)) begin
            @(posedge src_clk);
            timeout = timeout + 1;
        end
        if (commit_ack_count != expected_count)
            $fatal(1, "FAIL commit ack expected=%0d actual=%0d",
                   expected_count, commit_ack_count);
    end
endtask

task finish_fade_in;
    input integer expected_done_count;
    integer timeout;
    begin
        wait_state(ST_FADE_IN);
        advance_one_fade_step(3'd0, 3'd1);
        advance_one_fade_step(3'd1, 3'd2);
        advance_one_fade_step(3'd2, 3'd3);
        advance_one_fade_step(3'd3, 3'd4);
        wait_state(ST_IDLE);
        if (transition_busy)
            $fatal(1, "FAIL busy remained set after fade in");
        timeout = 0;
        while ((done_ack_count < expected_done_count) && (timeout < 100)) begin
            @(posedge src_clk);
            timeout = timeout + 1;
        end
        if (done_ack_count != expected_done_count)
            $fatal(1, "FAIL transition done CDC expected=%0d actual=%0d",
                   expected_done_count, done_ack_count);
    end
endtask

initial begin
    repeat (4) @(posedge video_clk);
    reset = 1'b0;
    repeat (4) @(posedge video_clk);

    // Initialize BUF0 through the same black-frame commit path used on power-up.
    send_request;
    publish_ready(2'd0, 2'd0);
    wait_state(ST_BLACK_SWAP);
    if (swap_count != 0)
        $fatal(1, "FAIL initial write changed display buffer before commit");
    pulse_frame;
    if ((display_buf_idx !== 2'd0) || (display_image_idx !== 2'd0) ||
        !display_valid || (swap_count != 1))
        $fatal(1, "FAIL initial BUF0 commit");
    wait_commit_ack(1);
    finish_fade_in(1);
    expect_level(3'd4, "initial display must be 100 percent");

    // CASE A/D: manual request, but a late load must leave the old image at 100%.
    send_request;
    repeat (4) begin
        pulse_frame;
        expect_level(3'd4, "faded before next frame ready");
    end
    if ((display_buf_idx !== 2'd0) || (swap_count != 1))
        $fatal(1, "FAIL display changed while waiting for ready");

    publish_ready(2'd1, 2'd1);
    wait_state(ST_FADE_OUT);
    advance_one_fade_step(3'd4, 3'd3);

    // CASE C: an extra request while busy reaches the same controller input and
    // is deliberately ignored; it must not schedule another swap.
    @(negedge src_clk);
    src_request_toggle = ~src_request_toggle;

    advance_one_fade_step(3'd3, 3'd2);
    advance_one_fade_step(3'd2, 3'd1);
    advance_one_fade_step(3'd1, 3'd0);
    wait_state(ST_BLACK_SWAP);
    if ((display_buf_idx !== 2'd0) || (swap_count != 1))
        $fatal(1, "FAIL write completion caused immediate swap");
    pulse_frame;
    if ((display_buf_idx !== 2'd1) || (display_image_idx !== 2'd1) ||
        (swap_count != 2))
        $fatal(1, "FAIL BUF0 to BUF1 swap");
    wait_commit_ack(2);
    finish_fade_in(2);
    repeat (4) pulse_frame;
    if (swap_count != 2)
        $fatal(1, "FAIL busy request caused a second swap");

    // CASE B: an automatic request uses the identical request input and path.
    send_request;
    publish_ready(2'd2, 2'd0);
    wait_state(ST_FADE_OUT);
    advance_one_fade_step(3'd4, 3'd3);
    advance_one_fade_step(3'd3, 3'd2);
    advance_one_fade_step(3'd2, 3'd1);
    advance_one_fade_step(3'd1, 3'd0);
    wait_state(ST_BLACK_SWAP);
    pulse_frame;
    if ((display_buf_idx !== 2'd0) || (display_image_idx !== 2'd2) ||
        (swap_count != 3))
        $fatal(1, "FAIL BUF1 to BUF0 auto swap");
    wait_commit_ack(3);
    finish_fade_in(3);

    if ((swap_count != 3) || (commit_ack_count != 3) || (done_ack_count != 3))
        $fatal(1, "FAIL event counts swaps=%0d commits=%0d done=%0d",
               swap_count, commit_ack_count, done_ack_count);

    $display("FADE_TRANSITION_TEST_PASS");
    $finish;
end

endmodule
