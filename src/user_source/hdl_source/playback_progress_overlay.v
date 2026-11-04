// Combinational: same RGB/HS/VS/DE/x/y pixel, no extra pipeline register.
module playback_progress_overlay #(parameter COORD_BITS=10, parameter VIDEO_720P=0)(
    input wire reset,de,visible,
    input wire [COORD_BITS-1:0] x,y,
    input wire [8:0] progress_units,
    input wire [23:0] background_rgb,
    output wire [23:0] output_rgb
);
    // 608/256=19/8. Explicit shifts/adds avoid multiplier/DSP inference.
    localparam BAR_WIDTH=VIDEO_720P?1248:608;
    localparam BAR_Y=VIDEO_720P?715:475;
    // 1248/256=39/8; 608/256=19/8. Constant shifts only, no DSP.
    wire [13:0] extent_sum=VIDEO_720P ?
        (({5'd0,progress_units}<<5)+({5'd0,progress_units}<<2)+({5'd0,progress_units}<<1)+progress_units):
        (({5'd0,progress_units}<<4)+({5'd0,progress_units}<<1)+progress_units);
    wire [10:0] extent=(progress_units>=256)?BAR_WIDTH:extent_sum[13:3];
    assign output_rgb=reset || !de ? 24'd0:
        ((visible && y>=BAR_Y && y<=BAR_Y+2 && x>=16 && x<16+BAR_WIDTH &&
          (x-10'd16)<extent)?24'h38E8DC:background_rgb);
endmodule
