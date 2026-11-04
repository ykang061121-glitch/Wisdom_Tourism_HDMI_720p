// Experimental latency: music 1 + subtitles 2 + UI 5 = 8 cycles.
// Switches and audio snapshot change only in blanking. No main-chain feedback.
module showcase_presentation_pipeline_frozen #(
    parameter COORD_BITS=10,
    parameter SPECTRUM_ENABLE=0,
    parameter VIDEO_720P=0,
    parameter COMPLIANCE_UI=0,
    parameter PERCENT_CONTRAST=0,
    parameter integer FRAMES_PER_PIXEL=2,
    parameter integer GROUP_FRAMES=180,
    parameter integer NOTICE_FRAMES=72,
    parameter integer HINT_FRAMES=72,
    parameter integer TOURISM_TEXT=0
)(
    input wire pixel_clk,reset,frame_boundary,hs,vs,de,
    input wire [COORD_BITS-1:0] x,y,
    input wire [23:0] background_rgb,
    input wire subtitles_visible,visual_visible,
    input wire signed [7:0] sample_amplitude,
    input wire sample_valid,
    output wire [7:0] sample_index,
    input wire [9:0] audio_status,
    input wire [127:0] spectrum_levels,
    input wire [7:0] error_status,
    input wire display_commit,display_valid,auto_play_enable,
    input wire [1:0] image_index,interval_code,preset_mode,
    input wire signed [7:0] brightness,
    input wire [7:0] contrast,
    input wire [11:0] brightness_digits,contrast_digits,
    input wire [2:0] fade_level,
    input wire scaling_meta_valid,adjust_mode,adjust_target_contrast,adjust_fast,
    input wire waiting_for_scene,
    input wire [63:0] scaling_meta_bcd,
    output wire out_hs,out_vs,out_de,
    output wire [COORD_BITS-1:0] out_x,out_y,
    output wire [23:0] output_rgb
);
    reg [9:0] music_frame_status;
    reg [7:0] error_frame_status;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)music_frame_status<=0;
        else if(frame_boundary)music_frame_status<=audio_status;
    end
    // Coherent source mailbox -> blanking-only UI snapshot. No playback
    // feedback and no added RGB/HS/VS/DE pipeline stage.
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)error_frame_status<=0;
        else if(frame_boundary)error_frame_status<=error_status;
    end
    wire notice_visible;
    wire [1:0] notice_index;
    scene_notice #(.NOTICE_FRAMES(NOTICE_FRAMES)) notice(
        .pixel_clk(pixel_clk),.reset(reset),.frame_boundary(frame_boundary),
        .display_commit(display_commit),.display_valid(display_valid),.display_image(image_index),
        .visible(notice_visible),.scene_index(notice_index));
    wire wh,wv,wd,sh,sv,sd;
    wire [COORD_BITS-1:0] wx,wy,sx,sy;
    wire [23:0] music_rgb,subtitle_rgb;
    wire [23:0] subtitle_base=music_rgb;
    reg [23:0] bypass_s1,bypass_s2;
    reg visible_d,visible_s1,visible_s2,boundary_d;
    generate if(SPECTRUM_ENABLE)begin:spectrum_layer
    showcase_music_overlay_spectrum #(.COORD_BITS(COORD_BITS),.VIDEO_720P(VIDEO_720P)) music(
        .pixel_clk(pixel_clk),.reset(reset),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),
        .background_rgb(background_rgb),.visible(visual_visible),.music_status(music_frame_status),
        .spectrum_levels(spectrum_levels),.sample_amplitude(sample_amplitude),.sample_valid(sample_valid),.sample_index(sample_index),
        .out_hs(wh),.out_vs(wv),.out_de(wd),.out_x(wx),.out_y(wy),.output_rgb(music_rgb));
    end else begin:legacy_layer
    showcase_music_overlay_fast #(.COORD_BITS(COORD_BITS),.VIDEO_720P(VIDEO_720P)) music(
        .pixel_clk(pixel_clk),.reset(reset),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),
        .background_rgb(background_rgb),.visible(visual_visible),.music_status(music_frame_status),
        .sample_amplitude(sample_amplitude),.sample_valid(sample_valid),.sample_index(sample_index),
        .out_hs(wh),.out_vs(wv),.out_de(wd),.out_x(wx),.out_y(wy),.output_rgb(music_rgb));
    end endgenerate
    // UI-only feedback, sampled AFTER the blanking boundary where the
    // existing controls atomically commit. The first observation just primes.
    // Simultaneous changes: VIS > SUB > preset > AUTO > interval, latest wins.
    localparam integer HINT_BITS=(HINT_FRAMES<=1)?1:$clog2(HINT_FRAMES+1);
    reg [HINT_BITS-1:0] hint_remaining;
    reg [6:0] previous_settings;
    reg settings_primed,check_settings,check_settings_second;
    reg [2:0] hint_kind;
    reg [HINT_BITS-1:0] param_remaining;
    reg [16:0] previous_parameters;
    wire [16:0] parameters={adjust_mode,brightness,contrast};
    wire [6:0] settings={visual_visible,subtitles_visible,preset_mode,auto_play_enable,interval_code};
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin
            hint_remaining<=0;previous_settings<=0;settings_primed<=0;check_settings<=0;hint_kind<=0;
            check_settings_second<=0;
            param_remaining<=0;previous_parameters<=0;
        end else begin
            check_settings<=frame_boundary;
            check_settings_second<=check_settings;
            // The percent-control bridge commits at boundary+1. Observe at
            // boundary+2, still blanking, so base label and actual RGB agree.
            if(PERCENT_CONTRAST?check_settings_second:check_settings)begin
                previous_settings<=settings;settings_primed<=1;
                previous_parameters<=parameters;
                if(PERCENT_CONTRAST && settings_primed && parameters!=previous_parameters)param_remaining<=HINT_FRAMES;
                else if(param_remaining!=0)param_remaining<=param_remaining-1'b1;
                if(settings_primed && settings!=previous_settings)begin
                    hint_remaining<=HINT_FRAMES;
                    if(settings[6]!=previous_settings[6])hint_kind<=5;
                    else if(settings[5]!=previous_settings[5])hint_kind<=4;
                    else if(settings[4:3]!=previous_settings[4:3])hint_kind<=3;
                    else if(settings[2]!=previous_settings[2])hint_kind<=2;
                    else hint_kind<=1;
                end else if(hint_remaining!=0)hint_remaining<=hint_remaining-1'b1;
            end
        end
    end
    dynamic_subtitle_overlay #(.COORD_BITS(COORD_BITS),.FRAMES_PER_PIXEL(FRAMES_PER_PIXEL),.GROUP_FRAMES(GROUP_FRAMES),
        .SCROLL_Y(VIDEO_720P?696:456),.LINE1_Y(VIDEO_720P?625:386),.LINE2_Y(VIDEO_720P?649:410),
        .WINDOW_RIGHT(VIDEO_720P?1263:623),.FIXED_LEFT(VIDEO_720P?24:16),
        .SHADOW_ENABLE(1),.TOURISM_TEXT(TOURISM_TEXT)) subtitles(
        .pixel_clk(pixel_clk),.reset(reset),.frame_boundary(boundary_d),
        .hs(wh),.vs(wv),.de(wd),.x(wx),.y(wy),.background_rgb(subtitle_base),.scene_image(image_index),
        .out_hs(sh),.out_vs(sv),.out_de(sd),.out_x(sx),.out_y(sy),
        .subtitle_rgb(subtitle_rgb),.scroll_offset(),.scroll_message(),.subtitle_group());
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin visible_d<=1;visible_s1<=1;visible_s2<=1;boundary_d<=0;bypass_s1<=0;bypass_s2<=0;end
        else begin
            visible_d<=subtitles_visible;visible_s1<=visible_d;visible_s2<=visible_s1;
            boundary_d<=frame_boundary;bypass_s1<=music_rgb;bypass_s2<=bypass_s1;
        end
    end
    // Existing SD mailbox updates can arrive during active video. The UI
    // consumes the already-observed frame snapshot, not those live wires.
    // Before the first frame, retain the original startup/music visibility.
    wire [6:0] ui_settings=settings_primed?previous_settings:settings;
    showcase_ui_pipeline_frozen #(.COORD_BITS(COORD_BITS),.VIDEO_720P(VIDEO_720P),.COMPLIANCE_UI(COMPLIANCE_UI),.PERCENT_CONTRAST(PERCENT_CONTRAST)) ui(.pixel_clk(pixel_clk),.reset(reset),.hs(sh),.vs(sv),.de(sd),.x(sx),.y(sy),
        .brightness_digits(brightness_digits),.contrast_digits(contrast_digits),.param_hint_visible(param_remaining!=0),
        .scaling_meta_valid(scaling_meta_valid),.scaling_meta_bcd(scaling_meta_bcd),
        .waiting_for_scene(waiting_for_scene),
        .adjust_mode(adjust_mode),.adjust_target_contrast(adjust_target_contrast),.adjust_fast(adjust_fast),
        .background_rgb(visible_s2?subtitle_rgb:bypass_s2),
        .display_valid(display_valid),.image_index(image_index),.auto_play_enable(ui_settings[2]),
        .interval_code(ui_settings[1:0]),.preset_mode(ui_settings[4:3]),.brightness(brightness),.contrast(contrast),
        .fade_level(fade_level),.subtitles_visible(ui_settings[5]),.visual_visible(ui_settings[6]),
        .music_status(music_frame_status),.hint_visible(hint_remaining!=0),.hint_kind(hint_kind),
        .error_status(error_frame_status),
        .notice_visible(notice_visible),.notice_index(notice_index),
        .out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),.out_x(out_x),.out_y(out_y),.output_rgb(output_rgb));
endmodule


