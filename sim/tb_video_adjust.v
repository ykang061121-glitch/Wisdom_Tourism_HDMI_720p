`timescale 1ns/1ps

module tb_video_adjust;

reg                    pixel_clk = 1'b0;
reg                    reset = 1'b1;
reg                    de = 1'b1;
reg  [23:0]            rgb_in = 24'd0;
reg  signed [7:0]      brightness = 8'sd0;
reg  [1:0]             contrast = 2'b01;
wire [23:0]            rgb_out;

reg  [3:0]             switches_async = 4'b0110;
wire signed [7:0]      controlled_brightness;
wire [1:0]             controlled_contrast;
wire [3:0]             switches_stable;

always #5 pixel_clk = ~pixel_clk;

video_adjust u_dut (
    .pixel_clk  (pixel_clk),
    .reset      (reset),
    .de         (de),
    .rgb_in     (rgb_in),
    .brightness (brightness),
    .contrast   (contrast),
    .rgb_out    (rgb_out)
);

display_adjust_control #(
    .STABLE_CYCLES(3)
) u_control (
    .video_clk       (pixel_clk),
    .reset           (reset),
    .switches_async  (switches_async),
    .brightness      (controlled_brightness),
    .contrast        (controlled_contrast),
    .switches_stable (switches_stable)
);

task expect_rgb;
    input [23:0] input_rgb;
    input signed [7:0] input_brightness;
    input [1:0] input_contrast;
    input [23:0] expected_rgb;
    input [255:0] case_name;
    begin
        de         = 1'b1;
        rgb_in     = input_rgb;
        brightness = input_brightness;
        contrast   = input_contrast;
        #1;
        if (rgb_out !== expected_rgb) begin
            $display("FAIL %0s: in=%h brightness=%0d contrast=%b expected=%h actual=%h",
                     case_name, input_rgb, input_brightness, input_contrast,
                     expected_rgb, rgb_out);
            $fatal(1);
        end
    end
endtask

initial begin
    repeat (3) @(posedge pixel_clk);
    reset = 1'b0;
    #1;

    // CASE 1 and CASE 6: neutral brightness and unity contrast are identity.
    expect_rgb(24'h4064C8, 8'sd0, 2'b01, 24'h4064C8, "neutral identity");

    // CASE 2: positive brightness.
    expect_rgb(24'h646464, 8'sd20, 2'b01, 24'h787878, "positive brightness");

    // CASE 3: negative brightness.
    expect_rgb(24'h646464, -8'sd20, 2'b01, 24'h505050, "negative brightness");

    // CASE 4: upper saturation.
    expect_rgb(24'hFAFAFA, 8'sd20, 2'b01, 24'hFFFFFF, "upper saturation");

    // CASE 5: lower saturation.
    expect_rgb(24'h050505, -8'sd20, 2'b01, 24'h000000, "lower saturation");

    // CASE 7: gain 1.25 moves values away from 128.
    expect_rgb(24'hC84080, 8'sd0, 2'b10, 24'hDA3080, "contrast greater than one");

    // CASE 8: gain 0.75 moves values toward 128.
    expect_rgb(24'hC84080, 8'sd0, 2'b00, 24'hB65080, "contrast less than one");

    // CASE 9: three channels are adjusted and saturated independently.
    expect_rgb(24'h0A64F0, 8'sd20, 2'b01, 24'h1E78FF, "independent RGB channels");

    // CASE 10: extreme endpoints and center values.
    expect_rgb(24'h00FF80, 8'sd0, 2'b11, 24'h00FF80, "extremes 0 255 128");
    expect_rgb(24'h7F8081, 8'sd0, 2'b11, 24'h7E8081, "extremes 127 128 129");

    // DE low is always blank, independent of parameters.
    de = 1'b0;
    rgb_in = 24'hFFFFFF;
    brightness = 8'sd20;
    contrast = 2'b11;
    #1;
    if (rgb_out !== 24'h000000)
        $fatal(1, "FAIL DE low blanking: actual=%h", rgb_out);

    // Verify the hardware switch mapping and that the complete vector is only
    // committed after the configured stability interval.
    if ((controlled_brightness !== 8'sd0) || (controlled_contrast !== 2'b01))
        $fatal(1, "FAIL reset parameter defaults");

    switches_async = 4'b1100; // contrast 1.50, brightness -32
    repeat (3) @(posedge pixel_clk);
    if (switches_stable === 4'b1100)
        $fatal(1, "FAIL switch vector committed before stability interval");
    repeat (5) @(posedge pixel_clk);
    #1;
    if ((switches_stable !== 4'b1100) ||
        (controlled_brightness !== -8'sd32) ||
        (controlled_contrast !== 2'b11)) begin
        $fatal(1, "FAIL stable switch mapping: sw=%b bri=%0d con=%b",
               switches_stable, controlled_brightness, controlled_contrast);
    end

    $display("VIDEO_ADJUST_TEST_PASS");
    $finish;
end

endmodule
