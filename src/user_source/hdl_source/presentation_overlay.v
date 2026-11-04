// Keep BOTH existing layer engines running. Bypass only the final visible
// effect, carrying the same 1+2 pixel pipeline latency even while hidden.
module presentation_overlay #(
    parameter integer FRAMES_PER_PIXEL=2,
    parameter integer GROUP_FRAMES=180
)(
    input wire pixel_clk,reset,frame_boundary,
    input wire hs,vs,de,
    input wire [9:0] x,y,
    input wire [23:0] background_rgb,
    input wire subtitles_visible,wave_visible,
    input wire signed [7:0] sample_amplitude,
    input wire sample_valid,
    output wire [7:0] sample_index,
    output wire out_hs,out_vs,out_de,
    output wire [9:0] out_x,out_y,
    output wire [23:0] output_rgb
);
    wire wh,wv,wd;
    wire [9:0] wx,wy;
    wire [23:0] wave_rgb,subtitle_rgb;
    reg [23:0] background_d,subtitle_background_s1,subtitle_background_s2;
    reg wave_visible_d,subtitles_visible_d,subtitles_visible_s1,subtitles_visible_s2,boundary_d;
    wire [23:0] visible_wave=wave_visible_d?wave_rgb:background_d;
    audio_wave_overlay wave_layer(
        .pixel_clk(pixel_clk),.reset(reset),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),
        .background_rgb(background_rgb),.sample_amplitude(sample_amplitude),
        .sample_valid(sample_valid),.sample_index(sample_index),
        .out_hs(wh),.out_vs(wv),.out_de(wd),.out_x(wx),.out_y(wy),.wave_rgb(wave_rgb));
    dynamic_subtitle_overlay #(.FRAMES_PER_PIXEL(FRAMES_PER_PIXEL),.GROUP_FRAMES(GROUP_FRAMES)) subtitles(
        .pixel_clk(pixel_clk),.reset(reset),.frame_boundary(boundary_d),
        .hs(wh),.vs(wv),.de(wd),.x(wx),.y(wy),.background_rgb(visible_wave),
        .out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),.out_x(out_x),.out_y(out_y),
        .subtitle_rgb(subtitle_rgb),.scroll_offset(),.scroll_message(),.subtitle_group());
    always @(posedge pixel_clk or posedge reset) begin
        if(reset) begin
            background_d<=0;wave_visible_d<=1;subtitles_visible_d<=1;boundary_d<=0;
            subtitle_background_s1<=0;subtitle_background_s2<=0;
            subtitles_visible_s1<=1;subtitles_visible_s2<=1;
        end else begin
            background_d<=background_rgb;wave_visible_d<=wave_visible;
            subtitles_visible_d<=subtitles_visible;
            boundary_d<=frame_boundary;
            subtitle_background_s1<=visible_wave;
            subtitle_background_s2<=subtitle_background_s1;
            subtitles_visible_s1<=subtitles_visible_d;
            subtitles_visible_s2<=subtitles_visible_s1;
        end
    end
    assign output_rgb=(reset || !out_de)?24'd0:
                      (subtitles_visible_s2?subtitle_rgb:subtitle_background_s2);
endmodule
