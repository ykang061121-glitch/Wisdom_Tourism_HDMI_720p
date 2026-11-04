module video_fade (
    input  wire        pixel_clk,
    input  wire        reset,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [2:0]  fade_level,
    output reg  [23:0] rgb_out
);

localparam [2:0] FADE_000 = 3'd0;
localparam [2:0] FADE_025 = 3'd1;
localparam [2:0] FADE_050 = 3'd2;
localparam [2:0] FADE_075 = 3'd3;
localparam [2:0] FADE_100 = 3'd4;

reg [7:0] red_out;
reg [7:0] green_out;
reg [7:0] blue_out;

function [7:0] scale_channel;
    input [7:0] channel_in;
    input [2:0] level;
    begin
        case (level)
            FADE_100: scale_channel = channel_in;
            FADE_075: scale_channel = channel_in - (channel_in >> 2);
            FADE_050: scale_channel = channel_in >> 1;
            FADE_025: scale_channel = channel_in >> 2;
            default:  scale_channel = 8'd0;
        endcase
    end
endfunction

always @* begin
    red_out   = scale_channel(rgb_in[23:16], fade_level);
    green_out = scale_channel(rgb_in[15:8],  fade_level);
    blue_out  = scale_channel(rgb_in[7:0],   fade_level);

    if (reset || !de || (fade_level == FADE_000))
        rgb_out = 24'd0;
    else
        rgb_out = {red_out, green_out, blue_out};
end

// The first implementation is intentionally combinational: fixed shifts and
// subtracts add no video timing latency and do not infer multipliers or DSPs.
wire unused_pixel_clk = pixel_clk;

endmodule
