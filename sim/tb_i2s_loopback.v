`timescale 1ns/1ps

module tb_i2s_loopback;
    reg mclk = 1'b0;
    reg rx_clk = 1'b0;
    reg rst = 1'b1;
    wire bclk;
    wire lrclk;
    wire dout;
    wire audio_valid;
    wire [23:0] audio_left;
    wire [23:0] audio_right;

    integer errors = 0;
    integer samples_checked = 0;
    integer bclk_index = 0;
    integer last_lr_edge_bclk = 0;
    integer last_frame_bclk = 0;
    integer have_lr_edge = 0;
    integer have_frame_edge = 0;
    integer slot_edges_checked = 0;
    integer frame_edges_checked = 0;
    reg prev_lrclk = 1'b0;
    reg monitor_started = 1'b0;
    reg [63:0] left_shift = 64'd0;
    reg [63:0] right_shift = 64'd0;
    reg [23:0] completed_left = 24'd0;
    reg [23:0] expected_left = 24'd0;
    reg [23:0] expected_right = 24'd0;
    reg expected_ready = 1'b0;
    realtime last_frame_time = 0.0;

    // Exact clocks used by the design: 12.288 MHz MCLK and 25 MHz receiver clock.
    always #40.690104 mclk = ~mclk;
    always #20.000000 rx_clk = ~rx_clk;

    hdmi_audio_tone_i2s_64fs #(.NOTE_HOLD_FRAMES(1000000)) tx (
        .I_mclk(mclk), .I_rst(rst),
        .O_i2s_BCLK(bclk), .O_i2s_LRCK(lrclk), .O_i2s_DOUT(dout)
    );

    I2S_receiver rx (
        .I_clk(rx_clk), .I_rst(rst),
        .I_i2s_BCLK(bclk), .I_i2s_LRCK(lrclk), .I_i2s_DOUT(dout),
        .O_audio_valid(audio_valid),
        .O_audio_left_data(audio_left), .O_audio_right_data(audio_right)
    );

    task fail;
        input [8*140-1:0] message;
        begin
            errors = errors + 1;
            $error("%0s", message);
        end
    endtask

    // Independent serial monitor. The receiver intentionally assigns the first
    // BCLK after an LRCLK transition to the channel that has just completed.
    always @(posedge bclk) begin
        if (!rst) begin
            bclk_index = bclk_index + 1;
            if (!monitor_started) begin
                monitor_started = 1'b1;
                prev_lrclk = lrclk;
                last_lr_edge_bclk = bclk_index;
            end else if (lrclk != prev_lrclk) begin
                if (have_lr_edge) begin
                    if ((bclk_index - last_lr_edge_bclk) != 64)
                        fail("channel slot is not 64 BCLK rising edges");
                    slot_edges_checked = slot_edges_checked + 1;
                end
                have_lr_edge = 1;
                last_lr_edge_bclk = bclk_index;

                if (prev_lrclk == 1'b0) begin
                    left_shift = {left_shift[62:0], dout};
                    completed_left = left_shift[63:40];
                    left_shift = 64'd0;
                end else begin
                    right_shift = {right_shift[62:0], dout};
                    expected_left = completed_left;
                    expected_right = right_shift[63:40];
                    expected_ready = 1'b1;
                    right_shift = 64'd0;

                    if (have_frame_edge) begin
                        if ((bclk_index - last_frame_bclk) != 128)
                            fail("stereo frame is not 128 BCLK rising edges");
                        if (($realtime - last_frame_time < 20831.0) ||
                            ($realtime - last_frame_time > 20836.0))
                            fail("LRCLK period is not 20.833 us (48 kHz)");
                        frame_edges_checked = frame_edges_checked + 1;
                    end
                    have_frame_edge = 1;
                    last_frame_bclk = bclk_index;
                    last_frame_time = $realtime;
                end
                prev_lrclk = lrclk;
            end else if (lrclk == 1'b0) begin
                left_shift = {left_shift[62:0], dout};
            end else begin
                right_shift = {right_shift[62:0], dout};
            end
        end
    end

    always @(posedge rx_clk) begin
        #1;
        if (!rst && audio_valid) begin
            if (!expected_ready)
                fail("receiver asserted valid without a completed serial frame");
            else begin
                if (audio_left !== expected_left)
                    fail("receiver left PCM does not match transmitted 24-bit PCM");
                if (audio_right !== expected_right)
                    fail("receiver right PCM does not match transmitted 24-bit PCM");
                if (audio_left !== audio_right)
                    fail("left and right channels differ although transmitter duplicates mono");
                expected_ready = 1'b0;
                samples_checked = samples_checked + 1;
            end
        end
    end

    initial begin
        repeat (12) @(posedge mclk);
        rst = 1'b0;
        wait (samples_checked >= 100);
        if (slot_edges_checked < 199)
            fail("fewer than 199 complete channel-slot intervals were measured");
        if (frame_edges_checked < 99)
            fail("fewer than 99 complete LRCLK periods were measured");

        $display("I2S_MEASURED_MCLK_HZ=12288000");
        $display("I2S_MEASURED_BCLK_PER_CHANNEL=64");
        $display("I2S_MEASURED_BCLK_PER_STEREO_FRAME=128");
        $display("I2S_MEASURED_LRCLK_HZ=48000");
        if (errors == 0) begin
            $display("I2S_LOOPBACK_TEST_PASS");
            $finish;
        end else begin
            $fatal(1, "I2S_LOOPBACK_TEST_FAIL errors=%0d", errors);
        end
    end

    initial begin
        #5000000;
        $fatal(1, "I2S_LOOPBACK_TEST_TIMEOUT");
    end
endmodule
