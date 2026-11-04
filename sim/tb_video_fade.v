`timescale 1ns/1ps

module tb_video_fade;

reg         pixel_clk = 1'b0;
reg         reset = 1'b1;
reg         de = 1'b1;
reg  [23:0] rgb_in = 24'd0;
reg  [2:0]  fade_level = 3'd4;
wire [23:0] rgb_out;

always #5 pixel_clk = ~pixel_clk;

video_fade u_dut (
    .pixel_clk (pixel_clk),
    .reset     (reset),
    .de        (de),
    .rgb_in    (rgb_in),
    .fade_level(fade_level),
    .rgb_out   (rgb_out)
);

task expect_fade;
    input [23:0] input_rgb;
    input [2:0]  level;
    input [23:0] expected_rgb;
    input [255:0] case_name;
    begin
        de = 1'b1;
        rgb_in = input_rgb;
        fade_level = level;
        #1;
        if (rgb_out !== expected_rgb) begin
            $display("FAIL %0s: in=%h level=%0d expected=%h actual=%h",
                     case_name, input_rgb, level, expected_rgb, rgb_out);
            $fatal(1);
        end
    end
endtask

initial begin
    repeat (3) @(posedge pixel_clk);
    reset = 1'b0;
    #1;

    expect_fade(24'hC86401, 3'd4, 24'hC86401, "100 percent");
    expect_fade(24'hC8C8C8, 3'd3, 24'h969696, "75 percent 200 to 150");
    expect_fade(24'hC8C8C8, 3'd2, 24'h646464, "50 percent 200 to 100");
    expect_fade(24'hC8C8C8, 3'd1, 24'h323232, "25 percent 200 to 50");
    expect_fade(24'hC86432, 3'd0, 24'h000000, "zero percent");

    // Independent RGB channels and truncating fixed-shift boundary behavior.
    expect_fade(24'h01FEFF, 3'd3, 24'h01BFC0, "RGB independent 75 percent");
    expect_fade(24'h0001FE, 3'd2, 24'h00007F, "boundaries 0 1 254");
    expect_fade(24'hFF017F, 3'd1, 24'h3F001F, "boundaries 255 1 127");

    de = 1'b0;
    rgb_in = 24'hFFFFFF;
    fade_level = 3'd4;
    #1;
    if (rgb_out !== 24'h000000)
        $fatal(1, "FAIL DE low blanking: actual=%h", rgb_out);

    $display("VIDEO_FADE_TEST_PASS");
    $finish;
end

endmodule
