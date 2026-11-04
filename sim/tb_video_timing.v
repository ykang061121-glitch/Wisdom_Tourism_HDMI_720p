`timescale 1ns/1ps

module tb_video_timing;
    localparam integer H_ACTIVE = 640;
    localparam integer H_TOTAL  = 800;
    localparam integer H_SYNC   = 96;
    localparam integer V_ACTIVE = 480;
    localparam integer V_TOTAL  = 525;
    localparam integer V_SYNC   = 2;

    reg clk = 1'b0;
    reg rst = 1'b1;
    wire hs;
    wire vs;
    wire de;
    wire read_req;

    integer errors = 0;
    integer cycles_since_hs = 0;
    integer hs_low_clocks = 0;
    integer line_de_clocks = 0;
    integer lines_since_vs = 0;
    integer frame_de_clocks = 0;
    integer frame_active_lines = 0;
    integer vs_low_clocks = 0;
    integer frames_checked = 0;
    integer have_hs = 0;
    integer have_vs = 0;
    integer prev_hs = 1;
    integer prev_vs = 1;
    integer monitor_enable = 0;

    always #20 clk = ~clk; // 25 MHz pixel clock

    video_timing_data dut (
        .video_clk(clk),
        .rst(rst),
        .read_req(read_req),
        .read_req_ack(1'b0),
        .hs(hs),
        .vs(vs),
        .de(de)
    );

    task fail;
        input [8*120-1:0] message;
        begin
            errors = errors + 1;
            $error("%0s", message);
        end
    endtask

    always @(posedge clk) begin
        if (!rst && monitor_enable) begin
            #1;
            cycles_since_hs = cycles_since_hs + 1;

            if ((prev_hs == 1) && (hs === 1'b0)) begin
                if (have_hs) begin
                    if (cycles_since_hs != H_TOTAL)
                        fail("line length is not 800 pixel clocks");
                    if (hs_low_clocks != H_SYNC)
                        fail("HSYNC low pulse is not 96 pixel clocks");
                    if ((line_de_clocks != 0) && (line_de_clocks != H_ACTIVE))
                        fail("DE width on a line is neither 0 nor 640");
                    if (line_de_clocks == H_ACTIVE)
                        frame_active_lines = frame_active_lines + 1;
                end
                have_hs = 1;
                cycles_since_hs = 0;
                hs_low_clocks = 1;
                line_de_clocks = 0;
                if (have_vs)
                    lines_since_vs = lines_since_vs + 1;
            end else begin
                if (hs === 1'b0)
                    hs_low_clocks = hs_low_clocks + 1;
                if (de === 1'b1)
                    line_de_clocks = line_de_clocks + 1;
            end

            if (de === 1'b1) begin
                frame_de_clocks = frame_de_clocks + 1;
            end

            if ((prev_vs == 1) && (vs === 1'b0)) begin
                if (have_vs) begin
                    if (lines_since_vs != V_TOTAL)
                        fail("frame length is not 525 lines");
                    if (frame_de_clocks != H_ACTIVE * V_ACTIVE)
                        fail("frame DE area is not 640x480");
                    if (frame_active_lines != V_ACTIVE)
                        fail("active-line count is not 480");
                    frames_checked = frames_checked + 1;
                    $display("VIDEO_FRAME_%0d_OK", frames_checked);
                end
                have_vs = 1;
                lines_since_vs = 0;
                frame_de_clocks = 0;
                frame_active_lines = 0;
            end
            if ((prev_vs == 0) && (vs === 1'b1)) begin
                if (have_vs && (vs_low_clocks != V_SYNC * H_TOTAL))
                    fail("VSYNC low pulse is not 2 lines");
                vs_low_clocks = 0;
            end else if (vs === 1'b0) begin
                vs_low_clocks = vs_low_clocks + 1;
            end

            prev_hs = hs;
            prev_vs = vs;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst = 1'b0;

        // Ignore reset-pipeline transients. Start only after both delayed timing
        // outputs have reached a known blanking state.
        wait (vs === 1'b1 && hs === 1'b1);
        @(posedge clk);
        #2;
        prev_hs = hs;
        prev_vs = vs;
        cycles_since_hs = 0;
        hs_low_clocks = 0;
        line_de_clocks = 0;
        lines_since_vs = 0;
        frame_de_clocks = 0;
        frame_active_lines = 0;
        vs_low_clocks = 0;
        have_hs = 0;
        have_vs = 0;
        monitor_enable = 1;

        wait (frames_checked == 3);
        if (vs !== 1'b0 && vs !== 1'b1)
            fail("VSYNC contains X/Z");
        if (hs !== 1'b0 && hs !== 1'b1)
            fail("HSYNC contains X/Z");
        if (V_SYNC * H_TOTAL != 1600)
            fail("internal test constant error");

        // The measured VS low width is checked separately over one steady frame.
        if (errors == 0) begin
            $display("VIDEO_TIMING_TEST_PASS");
            $finish;
        end else begin
            $fatal(1, "VIDEO_TIMING_TEST_FAIL errors=%0d", errors);
        end
    end

    initial begin
        #200000000;
        $fatal(1, "VIDEO_TIMING_TEST_TIMEOUT");
    end
endmodule
