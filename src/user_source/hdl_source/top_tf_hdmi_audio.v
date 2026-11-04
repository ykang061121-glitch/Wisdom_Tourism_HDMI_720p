`include "spectrum_snapshot_cdc.v"
`include "showcase_music_overlay_spectrum.v"
`include "pcm_spectrum_dft512.v"
`include "pixel_identity_delay.v"
`include "diagnostic_frame_phase.v"
`include "fixed_chinese_layout.v"
`include "fixed_chinese_row_rom.v"
`include "hdmi_diagnostic_overlay.v"

`include "debug_status.v"
`include "osd_status_cdc.v"
`include "video_active_position.v"
`include "osd_overlay.v"
`include "display_adjust_control.v"
`include "video_adjust.v"
`include "video_adjust_percent.v"
`include "video_fade.v"
`include "picture_transition.v"
`include "playback_progress_overlay.v"
`include "playback_progress_display.v"
`include "fade_transition_cdc.v"
`include "fade_transition_ctrl.v"
`include "slide_transition_ctrl.v"
`include "SD/segmented_frame_reader.v"
`include "SD/slide_frame_read_write.v"
`include "sd_sector_buffer.v"
`include "bmp_pixel_decoder.v"
`include "image_scaler.v"
`include "image_scaler_generic.v"
`include "adjustment_key_control.v"
`include "scaling_metadata_format.v"
`include "compliance_control_bridge.v"
`include "frame_completion_guard.v"
`include "audio_wave_capture.v"
`include "audio_wave_overlay.v"
`include "dynamic_subtitle_overlay.v"
`include "image_audio_cdc.v"
`include "image_melody_i2s.v"
`include "playback_interval_control.v"
`include "presentation_control.v"
`include "presentation_overlay.v"
`include "melody_status_cdc.v"
`include "scene_notice.v"
`include "showcase_music_overlay.v"
`include "showcase_ui_pipeline.v"
`include "showcase_music_overlay_fast.v"
`include "showcase_presentation_pipeline.v"

module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关
    input                       key3,           // K3：5/10/3 秒循环（B1）
    input  [3:0]                sw,             // 预设 / 字幕隐藏 / 波形隐藏

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

// Independent basic-image build. The legacy defaults of reusable modules stay VGA.
parameter ENABLE_720P = 1;
parameter BASIC_VIDEO = 0;
parameter ACTIVE_WIDTH = ENABLE_720P ? 1280 : 640;
parameter ACTIVE_HEIGHT = ENABLE_720P ? 720 : 480;
parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = ACTIVE_WIDTH*ACTIVE_HEIGHT;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data_adjusted_raw;
wire [23:0] adjusted_actual_rgb,diagnostic_bypass_rgb;
wire diagnostic_bypass_hs,diagnostic_bypass_vs,diagnostic_bypass_de;
wire [10:0] diagnostic_bypass_x,diagnostic_bypass_y;
(* keep="true", preserve="true", dont_touch="true" *) pixel_identity_delay diagnostic_bypass_m0(
 .pixel_clk(video_clk),.reset(rst_all),.hs(hs),.vs(vs),.de(de),
 .x(video_x),.y(video_y),.rgb(vout_data_raw),
 .out_hs(diagnostic_bypass_hs),.out_vs(diagnostic_bypass_vs),.out_de(diagnostic_bypass_de),
 .out_x(diagnostic_bypass_x),.out_y(diagnostic_bypass_y),.out_rgb(diagnostic_bypass_rgb));
// M2 fixed ADJUST. Both original processing paths remain instantiated.
assign vout_data_adjusted_raw = adjusted_actual_rgb;

wire [23:0] vout_data_faded_raw;
wire [23:0] vout_data;
wire [23:0] osd_rgb;
wire [23:0] showcase_rgb;
wire [9:0] playback_progress_sd;
wire [8:0] playback_progress_display_units;
wire playback_progress_display_visible;
wire showcase_hs,showcase_vs,showcase_de;
wire [10:0] showcase_x,showcase_y;
wire [9:0] music_status_audio,music_status_video;
wire [7:0] wave_sample_index;
wire signed [7:0] wave_sample_amplitude;
wire wave_sample_valid;
wire [23:0] subtitle_rgb;
wire subtitle_hs, subtitle_vs, subtitle_de;
wire [10:0] subtitle_x, subtitle_y;
wire        sd_display_valid;
wire [1:0]  osd_source_image_index;
wire        osd_source_auto_play_enable;
wire [13:0] osd_video_status;
wire [7:0]  playback_error_sd;
wire [1:0]  source_interval_code;
reg [1:0]   osd_interval_code;
wire [1:0]  osd_video_image_index;
reg         osd_video_auto_play_enable;
wire        osd_video_display_valid;
wire [10:0]  video_x;
wire [10:0]  video_y;
wire signed [7:0] display_brightness;
wire signed [7:0] preset_brightness;
wire [1:0] preset_contrast;
wire normal_k3_event,normal_k4_event;
wire adjustment_mode,adjust_target_contrast,adjust_fast;
wire resolution_meta_valid;
wire [63:0] resolution_meta_bcd;
wire [43:0] source_scaling_meta;
wire [7:0]  display_contrast;
wire [11:0] brightness_digits,contrast_digits;
wire adjusted_hs,adjusted_vs,adjusted_de;
wire [10:0] adjusted_x,adjusted_y;
wire [1:0] physical_preset_mode;
wire slide_active,slide_style;
wire [10:0] slide_shift;
wire [1:0] slide_target;
reg [2:0] slide_busy_sync;
always @(posedge sd_card_clk or posedge rst_all)
    if(rst_all)slide_busy_sync<=0;
    else slide_busy_sync<={slide_busy_sync[1:0],transition_busy};
wire [3:0]  display_switches_stable;
wire [1:0]  display_preset_mode;
wire        subtitles_visible, wave_visible;

wire [3:0]  state_code;
wire [7:0]  debug_status_code;
wire [3:0]  debug_image_number;
wire        debug_image_valid;
wire [6:0]  seg_status_hi;
wire [6:0]  seg_status_lo;
wire [6:0]  seg_image_number;
wire [6:0]  seg_zero;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        sd_card_write_ready;
wire        transition_cancel_toggle;
wire        transition_cancel_video;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire [1:0]  pending_buf_idx_sd;
wire [1:0]  pending_image_idx_sd;
wire        transition_request_toggle_sd;
wire        next_frame_ready_toggle_sd;
wire        display_swap_commit_pulse_sd;
wire        transition_done_pulse_sd;

wire        transition_request_pulse_video;
wire        next_frame_ready_video;
wire [3:0]  pending_payload_video;
wire [1:0]  transition_image_idx;
wire        transition_display_valid;
wire [2:0]  fade_level;
wire        transition_busy;
wire [2:0]  transition_state;
wire        swap_commit_pulse_video;
wire        transition_done_pulse_video;
reg         video_read_req_d;
wire        frame_start_pulse;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
// M1a: read-only tap of the exact registered PCM/valid sent to HDMI.
// No feedback or video-layer change. Keep the coherent internal snapshot so
// the real transform remains inspectable in the physical netlist before OSD.
wire spectrum_snapshot_valid,spectrum_busy,spectrum_overrun;
wire [127:0] spectrum_frame_levels;
spectrum_snapshot_cdc spectrum_display_snapshot_m0(
 .src_clk(video_clk),.src_reset(rst_all),.src_snapshot_valid(spectrum_snapshot_valid),
 .src_levels(spectrum_snapshot_levels),.src_ready(),
 .video_clk(video_clk),.video_reset(rst_all),.frame_boundary(frame_start_pulse),
 .frame_levels(spectrum_frame_levels),.frame_commit(),.received_pulse());

(*keep="true"*) wire [127:0] spectrum_snapshot_levels;
(*keep="true",preserve="true",dont_touch="true"*) reg [127:0] spectrum_analysis_snapshot;
(*keep_hierarchy="true"*) pcm_spectrum_dft512 spectrum_transform_m0(
 .clk(video_clk),.reset(rst_all),.sample_valid(audio_valid),.pcm_sample(audio_left_data),
 .snapshot_valid(spectrum_snapshot_valid),.snapshot_levels(spectrum_snapshot_levels),
 .snapshot_power(),.busy(spectrum_busy),.overrun(spectrum_overrun));
always @(posedge video_clk or posedge rst_all)begin
 if(rst_all)spectrum_analysis_snapshot<=0;
 else if(spectrum_snapshot_valid)spectrum_analysis_snapshot<=spectrum_snapshot_levels;
end

wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
wire rst_all;
assign rst_all = ~rst_n | ~audio_pll_lock;

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0)
);

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .ALLOW_720P(ENABLE_720P),.OUTPUT_WIDTH(ACTIVE_WIDTH),.OUTPUT_HEIGHT(ACTIVE_HEIGHT),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd4),
    .DEFAULT_INTERVAL_CODE(2'd2), // reset dwell = 5 seconds
    .PREFETCH_ENABLE(1),.GENERIC_SCALE(1),.SCALE_MODE(0),.KEY_EVENTS(1),.GUARD_VIDEO_BUSY(1)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_all),
    .key_next          (key1),
    .key_auto          (key2),
    .key_interval      (key3),
    .key_interval_event(normal_k3_event),.key_auto_event(normal_k4_event),
    .video_busy_observed(slide_busy_sync[2]),
    .osd_scaling_meta(source_scaling_meta),
    .osd_interval_code (source_interval_code),
    .playback_progress (playback_progress_sd),
    .playback_error    (playback_error_sd),
    .state_code        (state_code),
    .debug_status_code (debug_status_code),
    .debug_image_number(debug_image_number),
    .debug_image_valid (debug_image_valid),
    .osd_image_index   (osd_source_image_index),
    .osd_auto_play_enable(osd_source_auto_play_enable),
    .bmp_width         (ACTIVE_WIDTH),
    .bmp_height        (ACTIVE_HEIGHT),
    .display_valid     (sd_display_valid),

    .write_finish_toggle(frame_write_toggle_mem),
    .display_swap_commit_pulse(display_swap_commit_pulse_sd),
    .transition_done_pulse(transition_done_pulse_sd),
    .write_buf_idx     (write_buf_idx),
    .pending_buf_idx   (pending_buf_idx_sd),
    .pending_image_idx (pending_image_idx_sd),
    .transition_request_toggle(transition_request_toggle_sd),
    .next_frame_ready_toggle(next_frame_ready_toggle_sd),

    .write_req         (sd_card_write_req),
    .cancel            (1'b0),
    .transition_cancel_toggle(transition_cancel_toggle),
    .write_req_ack     (sd_card_write_req_ack),
    .write_ready       (sd_card_write_ready),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_status_hi_decoder(
    .bin_data          (debug_status_code[7:4]),
    .seg_data          (seg_status_hi)
);

seg_decoder seg_status_lo_decoder(
    .bin_data          (debug_status_code[3:0]),
    .seg_data          (seg_status_lo)
);

seg_decoder seg_image_decoder(
    .bin_data          (debug_image_number),
    .seg_data          (seg_image_number)
);

seg_decoder seg_zero_decoder(
    .bin_data          (4'd0),
    .seg_data          (seg_zero)
);

seg_scan #(
    .SCAN_FREQ         (200),
    .CLK_FREQ          (100_000_000)
) seg_scan_m0(
    .clk               (sd_card_clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        (debug_image_valid ? {1'b1,seg_image_number} : 8'hff),
    .seg_data_1        (debug_image_valid ? {1'b1,seg_zero} : 8'hff),
    .seg_data_2        (debug_image_valid ? {1'b1,seg_zero} : 8'hff),
    .seg_data_3        (debug_image_valid ? {1'b1,seg_zero} : 8'hff),
    .seg_data_4        ({1'b1,seg_status_lo}),
    .seg_data_5        ({1'b1,seg_status_hi})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data #(.VIDEO_720P(ENABLE_720P)) video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

// video_timing_data raises read_req once per frame at the raw VSYNC falling
// edge.  Its rising edge is the frame boundary used for all fade updates and
// for the black-frame buffer commit.
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all)
        video_read_req_d <= 1'b0;
    else
        video_read_req_d <= video_read_req;
end

assign frame_start_pulse = video_read_req & ~video_read_req_d;

fade_transition_cdc fade_transition_cdc_m0 (
    .src_cancel_toggle (transition_cancel_toggle),
    .dst_cancel_pulse  (transition_cancel_video),
    .src_clk                (sd_card_clk),
    .src_reset              (rst_all),
    .src_request_toggle     (transition_request_toggle_sd),
    .src_ready_toggle       (next_frame_ready_toggle_sd),
    .src_pending_payload    ({pending_image_idx_sd, pending_buf_idx_sd}),
    .src_commit_pulse       (display_swap_commit_pulse_sd),
    .src_transition_done_pulse(transition_done_pulse_sd),
    .dst_clk                (video_clk),
    .dst_reset              (rst_all),
    .dst_request_pulse      (transition_request_pulse_video),
    .dst_next_frame_ready   (next_frame_ready_video),
    .dst_pending_payload    (pending_payload_video),
    .dst_commit_pulse       (swap_commit_pulse_video),
    .dst_transition_done_pulse(transition_done_pulse_video)
);

slide_transition_ctrl #(
    .FRAMES_PER_STEP (2)
) fade_transition_ctrl_m0 (
    .transition_cancel_pulse(transition_cancel_video),
    .video_clk               (video_clk),
    .reset                   (rst_all),
    .frame_start_pulse       (frame_start_pulse),
    .transition_request_pulse(transition_request_pulse_video),
    .next_frame_ready        (next_frame_ready_video),
    .frame_complete(diagnostic_de && diagnostic_x==11'd1279 && diagnostic_y==11'd719),
    .slide_active(slide_active),.slide_shift(slide_shift),
    .slide_target(slide_target),.active_style(slide_style),
    .pending_buf_idx         (pending_payload_video[1:0]),
    .pending_image_idx       (pending_payload_video[3:2]),
    .display_buf_idx         (disp_buf_idx),
    .display_image_idx       (transition_image_idx),
    .display_valid           (transition_display_valid),
    .fade_level              (fade_level),
    .transition_busy         (transition_busy),
    .transition_state        (transition_state),
    .swap_commit_pulse       (swap_commit_pulse_video),
    .transition_done_pulse   (transition_done_pulse_video)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 背景图片先做亮度/对比度调整，再进入 OSD。首图提交前仍保持黑屏。
presentation_control #(
    .STABLE_CYCLES (250000) // about 3.37ms at 74.25MHz + blanking commit
) presentation_control_m0 (
    .video_clk       (video_clk),
    .reset           (rst_all),
    .frame_boundary  (frame_start_pulse),
    .switches_async  (sw),
    .brightness      (preset_brightness),
    .contrast        (preset_contrast),
    .switches_active (display_switches_stable),
    .preset_mode     (physical_preset_mode),
    .subtitles_visible(subtitles_visible),
    .wave_visible    (wave_visible)
);

compliance_control_bridge compliance_control_m0(
    .sd_clk(sd_card_clk),.video_clk(video_clk),.reset(rst_all),
    .frame_boundary(frame_start_pulse),.key3_n(key3),.key4_n(key2),
    .switches_async(sw[1:0]),.scaling_meta_sd(source_scaling_meta),
    .image_sd(osd_source_image_index),.image_video(transition_image_idx),
    .preset_brightness(preset_brightness),.preset_contrast(preset_contrast),
    .normal_key3(normal_k3_event),.normal_key4(normal_k4_event),
    .brightness(display_brightness),.contrast(display_contrast),
    .preset_mode(display_preset_mode),.brightness_digits(brightness_digits),.contrast_digits(contrast_digits),
    .adjust_mode(adjustment_mode),.target_contrast(adjust_target_contrast),.fast_step(adjust_fast),
    .meta_valid(resolution_meta_valid),.meta_bcd(resolution_meta_bcd));

video_adjust_percent video_adjust_m0 (
    .pixel_clk  (video_clk),
    .reset      (rst_all),
    .de         (de),
    .rgb_in     (vout_data_raw),
    .hs(hs),.vs(vs),.x(video_x),.y(video_y),
    .out_hs(adjusted_hs),.out_vs(adjusted_vs),.out_de(adjusted_de),.out_x(adjusted_x),.out_y(adjusted_y),
    .brightness (display_brightness),
    .contrast_percent(display_contrast),
    .rgb_out    (adjusted_actual_rgb)
);

picture_transition #(.COORD_BITS(11),.ACTIVE_WIDTH(ACTIVE_WIDTH)) picture_transition_m0 (
    .pixel_clk (video_clk),
    .reset     (rst_all),
    .de        (adjusted_de),
    .rgb_in    (vout_data_adjusted_raw),
    .fade_level(fade_level),
    .frame_boundary(frame_start_pulse),.x(adjusted_x),.y(adjusted_y),
    .transition_state(transition_state),.pending_image_index(pending_payload_video[3:2]),
    .scene_commit(swap_commit_pulse_video),.display_valid(transition_display_valid),
    .effect_mode(),.reveal_step(),
    .rgb_out   (vout_data_faded_raw)
);

assign vout_data = transition_display_valid ? vout_data_faded_raw : 24'd0;

// Atomic, stable status snapshot from the SD control clock into video_clk.
osd_status_cdc #(.WIDTH(14)) osd_status_cdc_m0 (
    .src_clk    (sd_card_clk),
    .src_reset  (rst_all),
    .src_status ({playback_error_sd,source_interval_code,sd_display_valid,osd_source_auto_play_enable,osd_source_image_index}),
    .dst_clk    (video_clk),
    .dst_reset  (rst_all),
    .dst_status (osd_video_status)
);

// Settings from SD are coherent mailbox snapshots, then latched for a full
// video frame. Do not cross the live multi-bit interval code directly.
always @(posedge video_clk or posedge rst_all) begin
    if(rst_all) begin osd_interval_code<=2;osd_video_auto_play_enable<=0;end
    else if(frame_start_pulse) begin
        osd_interval_code<=osd_video_status[5:4];
        osd_video_auto_play_enable<=osd_video_status[2];
    end
end
assign osd_video_display_valid    = transition_display_valid;
assign osd_video_image_index      = transition_image_idx;

video_active_position #(.COORD_BITS(11)) video_active_position_m0 (
    .pixel_clk (video_clk),
    .reset     (rst_all),
    .vs        (vs),
    .de        (de),
    .x         (video_x),
    .y         (video_y)
);

// PCM is tapped after the existing I2S receiver: exactly the parallel samples
// and valid event sent to HDMI, already in video_clk. No audio path feedback.
audio_wave_capture audio_wave_capture_m0 (
    .pixel_clk (video_clk), .reset (rst_all),
    .audio_valid (audio_valid), .audio_left (audio_left_data),
    .frame_boundary (frame_start_pulse), .video_de (de),
    .read_index (wave_sample_index), .read_amplitude (wave_sample_amplitude),
    .read_valid (wave_sample_valid), .snapshot_valid (), .snapshot_commit ()
);

showcase_presentation_pipeline #(.SPECTRUM_ENABLE(1),.COORD_BITS(11),.VIDEO_720P(ENABLE_720P),.TOURISM_TEXT(1),.COMPLIANCE_UI(1),.PERCENT_CONTRAST(1)) showcase_presentation_m0 (
    .brightness_digits(brightness_digits),.contrast_digits(contrast_digits),
    .scaling_meta_valid(resolution_meta_valid),.scaling_meta_bcd(resolution_meta_bcd),
    .waiting_for_scene(playback_progress_display_visible && playback_progress_display_units==9'd256),
    .adjust_mode(adjustment_mode),.adjust_target_contrast(adjust_target_contrast),.adjust_fast(adjust_fast),
    .pixel_clk (video_clk), .reset (rst_all),
    .frame_boundary(frame_start_pulse),
    .subtitles_visible(subtitles_visible),.visual_visible(wave_visible),
    .audio_status(music_status_video),
    .spectrum_levels(spectrum_frame_levels),
    .display_commit(swap_commit_pulse_video),.display_valid(transition_display_valid),
    .image_index(transition_image_idx),.auto_play_enable(osd_video_auto_play_enable),
    .interval_code(osd_interval_code),.preset_mode(display_preset_mode),
    .error_status(osd_video_status[13:6]),
    .brightness(display_brightness),.contrast(display_contrast),.fade_level(fade_level),
    .hs (adjusted_hs), .vs (adjusted_vs), .de (adjusted_de), .x (adjusted_x), .y (adjusted_y),
    .background_rgb (vout_data), .sample_amplitude (wave_sample_amplitude),
    .sample_valid (wave_sample_valid), .sample_index (wave_sample_index),
    .out_hs(showcase_hs), .out_vs(showcase_vs),
    .out_de(showcase_de), .out_x(showcase_x), .out_y(showcase_y),
    .output_rgb(showcase_rgb)
);

// Observe actual dwell expiry, retain FULL through loading/BLACK, and reset
// only when the committed scene first enables image pixels. No timer feedback.
playback_progress_display #(.CONTINUOUS_COMMITS(1)) playback_progress_display_m0 (
    .src_clk(sd_card_clk),.src_reset(rst_all),.src_progress(playback_progress_sd),
    .src_auto(osd_source_auto_play_enable),.src_interval(source_interval_code),
    .src_error(playback_error_sd),.src_commit_pulse(display_swap_commit_pulse_sd),
    .video_clk(video_clk),.video_reset(rst_all),.frame_boundary(frame_start_pulse),
    .video_commit(swap_commit_pulse_video),.video_valid(transition_display_valid),
    .video_busy(transition_busy),.video_fade_level(fade_level),.video_state(transition_state),
    .visible(playback_progress_display_visible),.display_units(playback_progress_display_units),
    .scene_start_pulse(),.display_phase());
playback_progress_overlay #(.COORD_BITS(11),.VIDEO_720P(ENABLE_720P)) playback_progress_overlay_m0 (
    .reset(rst_all),.de(showcase_de),.x(showcase_x),.y(showcase_y),
    .visible(playback_progress_display_visible),
    .progress_units(playback_progress_display_units),
    .background_rgb(showcase_rgb),.output_rgb(osd_rgb));

slide_frame_read_write #(
    .READ_FIFO_ADDR_BITS(ENABLE_720P ? 10 : 9),
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (ACTIVE_WIDTH),
    .FRAME_HEIGHT     (ACTIVE_HEIGHT)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_slide_shift(slide_active?slide_shift:11'd0),
    .read_next_bank(slide_target[0]),.read_next_ready(next_frame_ready_video),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (disp_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_ready       (sd_card_write_ready),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// Observe only the video-domain COMMITTED display identity. No key, mode,
// pending-load index or audio acknowledgement feeds back into video control.
wire audio_selection_update, audio_selection_valid;
wire [1:0] audio_selection_image;
image_audio_cdc image_audio_cdc_m0 (
    .video_clk(video_clk), .video_reset(rst_all),
    .display_valid(transition_display_valid), .display_image(transition_image_idx),
    .audio_clk(audio_mclk), .audio_reset(rst_all),
    .selection_update(audio_selection_update), .selection_valid(audio_selection_valid),
    .selection_image(audio_selection_image));

// ===================== 音频：已显示图片对应的 ROM 旋律 =====================
image_melody_i2s image_melody_i2s_m0 (
    .I_mclk      (audio_mclk),
    .I_rst       (rst_all),
    .selection_update(audio_selection_update),
    .selection_valid(audio_selection_valid),
    .selection_image(audio_selection_image),
    .active_valid(),
    .active_image(),
    .song_start(),
    .playback_status(music_status_audio),
    .O_i2s_BCLK  (audio_i2s_bclk),
    .O_i2s_LRCK  (audio_i2s_lrck),
    .O_i2s_DOUT  (audio_i2s_dout)
);

melody_status_cdc melody_status_cdc_m0(.audio_clk(audio_mclk),.video_clk(video_clk),
    .reset(rst_all),.audio_status(music_status_audio),.video_status(music_status_video));

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);


wire [1:0] diagnostic_phase;
wire diagnostic_hs,diagnostic_vs,diagnostic_de;
wire [10:0] diagnostic_x,diagnostic_y;
wire [23:0] diagnostic_rgb;
(* keep="true", preserve="true", dont_touch="true" *) diagnostic_frame_phase #(.HOLD_FRAMES(180)) diagnostic_phase_m0(
 .pixel_clk(video_clk),.reset(rst_all),.frame_boundary(frame_start_pulse),
 .enable(transition_display_valid),.phase(diagnostic_phase));
hdmi_diagnostic_overlay #(.PATTERNS(0),.SHOW_DIAGNOSTIC_LABEL(0),.SHOW_FIXED_CHINESE(1)) diagnostic_output_m0(
 .pixel_clk(video_clk),.reset(rst_all),
 .hs(showcase_hs),.vs(showcase_vs),.de(showcase_de),.x(showcase_x),.y(showcase_y),
 .rgb(osd_rgb),.phase(2'd0),
 .frame_boundary(frame_start_pulse),.scene_index(transition_image_idx),.chinese_enable(subtitles_visible),
 .out_hs(diagnostic_hs),.out_vs(diagnostic_vs),.out_de(diagnostic_de),
 .out_x(diagnostic_x),.out_y(diagnostic_y),.out_rgb(diagnostic_rgb));

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 #(.ACTIVE_WIDTH(ACTIVE_WIDTH)) u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (diagnostic_vs),
    .I_de          (diagnostic_de),
    .I_rgb         (diagnostic_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL ( ENABLE_720P?1650:800 ),
    .HSA ( ENABLE_720P?40:96 ),
    .HFP ( ENABLE_720P?110:16 ),
    .HBP ( ENABLE_720P?220:48 ),
    .HACTIVE ( ACTIVE_WIDTH ),
    .VTOTAL ( ENABLE_720P?750:525 ),
    .VSA ( ENABLE_720P?5:2 ),
    .VFP ( ENABLE_720P?5:10 ),
    .VBP ( ENABLE_720P?20:33 ),
    .VACTIVE ( ACTIVE_HEIGHT ),
    .VIDEO_VIC ( ENABLE_720P?4:1 ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule

