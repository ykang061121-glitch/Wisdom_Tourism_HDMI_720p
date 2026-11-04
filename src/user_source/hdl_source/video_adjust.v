module video_adjust (
    input  wire                    pixel_clk,
    input  wire                    reset,
    input  wire                    de,
    input  wire [23:0]             rgb_in,
    input  wire signed [7:0]       brightness,
    input  wire [1:0]              contrast,
    output reg  [23:0]             rgb_out
);

// contrast encoding:
//   00 = 0.75 = 3/4
//   01 = 1.00 = 4/4
//   10 = 1.25 = 5/4
//   11 = 1.50 = 6/4
// All arithmetic is signed and deliberately uses shifts/adds so no multiplier
// or DSP is required.
// floor((c-128)/4) == (c>>2)-32 even when c<128. Factor the
// center correction into one shared bias instead of subtracting/adding 128
// in every channel. Scaled is 0..382; matching result is -192..445.
reg signed [9:0] control_bias;
always @* begin
    case(contrast)
        0:control_bias=$signed({{2{brightness[7]}},brightness})+10'sd32;
        1:control_bias=$signed({{2{brightness[7]}},brightness});
        2:control_bias=$signed({{2{brightness[7]}},brightness})-10'sd32;
        3:control_bias=$signed({{2{brightness[7]}},brightness})-10'sd64;
    endcase
end
function [7:0] adjust_channel;
    input [7:0]        channel_in;
    input signed [9:0] brightness_in;
    input [1:0]        contrast_in;
    reg [8:0]         scaled;
    reg signed [9:0]   adjusted;
    begin
        case (contrast_in)
            2'b00: scaled = {1'b0,channel_in} - {3'b000,channel_in[7:2]};
            2'b01: scaled = {1'b0,channel_in};
            2'b10: scaled = {1'b0,channel_in} + {3'b000,channel_in[7:2]};
            default: scaled = {1'b0,channel_in} + {2'b00,channel_in[7:1]};
        endcase

        adjusted = $signed({1'b0,scaled}) + brightness_in;

        if (adjusted[9])
            adjust_channel = 8'd0;
        else if (adjusted[8])
            adjust_channel = 8'd255;
        else
            adjust_channel = adjusted[7:0];
    end
endfunction

always @* begin
    if (reset || !de) begin
        rgb_out = 24'd0;
    end else begin
        rgb_out[23:16] = adjust_channel(rgb_in[23:16], control_bias, contrast);
        rgb_out[15:8]  = adjust_channel(rgb_in[15:8],  control_bias, contrast);
        rgb_out[7:0]   = adjust_channel(rgb_in[7:0],   control_bias, contrast);
    end
end

// The transform is combinational to preserve the existing HS/VS/DE alignment.
// pixel_clk remains part of the interface to make the pixel-domain contract
// explicit and to allow a future registered implementation without changing
// the top-level connection.
wire unused_pixel_clk = pixel_clk;

endmodule
