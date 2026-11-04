`timescale 1ns/1ps

module tb_osd_overlay;

localparam [23:0] BG = 24'h123456;
localparam [23:0] FG = 24'hFFFFFF;

reg         src_clk = 1'b0;
reg         pixel_clk = 1'b0;
reg         reset = 1'b1;
reg  [3:0]  src_status = 4'd0;
wire [3:0]  dst_status;
reg         de = 1'b1;
reg  [9:0]  x = 10'd0;
reg  [9:0]  y = 10'd0;
reg  [23:0] background_rgb = BG;
reg  signed [7:0] brightness = 8'sd0;
reg  [1:0]  contrast = 2'b01;
reg  [2:0]  fade_level = 3'd4;
wire [23:0] osd_rgb;

always #5  src_clk = ~src_clk;
always #20 pixel_clk = ~pixel_clk;

osd_status_cdc u_cdc (
    .src_clk    (src_clk),
    .src_reset  (reset),
    .src_status (src_status),
    .dst_clk    (pixel_clk),
    .dst_reset  (reset),
    .dst_status (dst_status)
);

osd_overlay #(
    .FOREGROUND_RGB(FG),
    .OSD_X(10'd16),
    .OSD_Y(10'd16)
) u_dut (
    .pixel_clk        (pixel_clk),
    .reset            (reset),
    .de               (de),
    .x                (x),
    .y                (y),
    .background_rgb   (background_rgb),
    .image_index      (dst_status[1:0]),
    .auto_play_enable (dst_status[2]),
    .display_valid    (dst_status[3]),
    .brightness       (brightness),
    .contrast         (contrast),
    .fade_level       (fade_level),
    .osd_rgb          (osd_rgb)
);

task expect_pixel;
    input [9:0] tx;
    input [9:0] ty;
    input       tde;
    input [23:0] expected;
    input [255:0] case_name;
    begin
        x  = tx;
        y  = ty;
        de = tde;
        #1;
        if (osd_rgb !== expected) begin
            $display("FAIL %0s: x=%0d y=%0d de=%0b expected=%h actual=%h",
                     case_name, tx, ty, tde, expected, osd_rgb);
            $fatal(1);
        end
    end
endtask

task set_status_and_wait;
    input [3:0] value;
    integer timeout;
    begin
        @(negedge src_clk);
        src_status = value;
        timeout = 0;
        while ((dst_status !== value) && (timeout < 40)) begin
            @(posedge pixel_clk);
            timeout = timeout + 1;
        end
        if (dst_status !== value) begin
            $display("FAIL CDC snapshot: expected=%b actual=%b", value, dst_status);
            $fatal(1);
        end
    end
endtask

initial begin
    repeat (3) @(posedge pixel_clk);
    reset = 1'b0;
    repeat (2) @(posedge pixel_clk);

    // CASE 1: outside the OSD rectangle, active video is transparent.
    expect_pixel(10'd0, 10'd0, 1'b1, BG, "outside OSD passthrough");

    // CASE 6: display_valid=0 selects LOADING.  O at cell 1, row 0,
    // column 3 is lit; the normal N at that position is not.
    expect_pixel(10'd27, 10'd16, 1'b1, FG, "LOADING selected");

    set_status_and_wait(4'b1000); // valid, AUTO off, image index 0 => IMG:01

    // CASE 2: A, row 0, column 3 is a foreground pixel.
    expect_pixel(10'd19, 10'd16, 1'b1, FG, "character foreground");

    // CASE 3: A, row 0, column 0 is blank and must preserve background.
    expect_pixel(10'd16, 10'd16, 1'b1, BG, "character blank transparency");

    // Confirm valid mode no longer shows the LOADING O pixel selected above.
    expect_pixel(10'd27, 10'd16, 1'b1, BG, "normal title selected");

    // CASE 4: IMG:01 has a blank at digit row 0/column 2; IMG:02 lights it.
    expect_pixel(10'd58, 10'd36, 1'b1, BG, "image number 01");
    set_status_and_wait(4'b1001); // valid, AUTO off, image index 1 => IMG:02
    expect_pixel(10'd58, 10'd36, 1'b1, FG, "image number 02");

    // CASE 5: AUTO:ON leaves cell 7 blank; AUTO:OFF displays the second F.
    set_status_and_wait(4'b1101); // valid, AUTO on, image index 1
    expect_pixel(10'd73, 10'd56, 1'b1, BG, "AUTO ON");
    set_status_and_wait(4'b1001); // valid, AUTO off, image index 1
    expect_pixel(10'd73, 10'd56, 1'b1, FG, "AUTO OFF");

    // Parameter lines: BRI:-32 has no vertical '+' stroke at this point,
    // while BRI:+16 does.  The tens digit also changes from 3 to 1.
    brightness = -8'sd32;
    expect_pixel(10'd51, 10'd80, 1'b1, BG, "BRI minus sign");
    expect_pixel(10'd58, 10'd76, 1'b1, FG, "BRI -32 digits");
    brightness = 8'sd16;
    expect_pixel(10'd51, 10'd80, 1'b1, FG, "BRI plus sign update");
    expect_pixel(10'd58, 10'd76, 1'b1, BG, "BRI +16 digits update");

    // CON:075 begins with 0 (lit at row0/column2); CON:150 begins with 1
    // whose row0/column2 is blank.
    contrast = 2'b00;
    expect_pixel(10'd50, 10'd96, 1'b1, FG, "CON 075");
    contrast = 2'b11;
    expect_pixel(10'd50, 10'd96, 1'b1, BG, "CON 150 update");

    // FADE:100 uses a blank pixel in the leading 1 and a lit pixel in the
    // following 0.  FADE:075 reverses both selected pixels.
    fade_level = 3'd4;
    expect_pixel(10'd58, 10'd116, 1'b1, BG, "FADE 100 hundreds");
    expect_pixel(10'd65, 10'd118, 1'b1, FG, "FADE 100 tens");
    fade_level = 3'd3;
    expect_pixel(10'd58, 10'd116, 1'b1, FG, "FADE 075 hundreds update");
    expect_pixel(10'd65, 10'd118, 1'b1, BG, "FADE 075 tens update");

    // The supplied background represents the already-adjusted image pixel;
    // it must remain unchanged outside every OSD glyph.
    background_rgb = 24'h445566;
    expect_pixel(10'd300, 10'd200, 1'b1, 24'h445566,
                 "adjusted background passthrough");

    // CASE 7: blanking always outputs black, even over a glyph pixel.
    expect_pixel(10'd19, 10'd16, 1'b0, 24'h000000, "DE low blanking");

    $display("OSD_OVERLAY_TEST_PASS");
    $finish;
end

endmodule
