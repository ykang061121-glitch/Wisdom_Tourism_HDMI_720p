
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      音频 PLL     -> u_audio_pll
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/candidate/pll_inst.clkc[1]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/candidate/pll_inst.clkc[2]}]
rename_clock -name {audio_mclk}  -source [get_ports {clk}] -master_clock {clk} [get_pins {u_audio_pll/pll_inst.clkc[2]}]

# ------------------------------------------------------------
# 4. HDMI pixel/serializer clocks are related, not exclusive.
#    video_pll_m0 drives both clocks concurrently (25 MHz / 125 MHz, 0 deg).
#    lane_lvds_10_1 transfers I_data_in and S_odd_even between these domains.
#    Keep the derive_clocks relationship so STA checks all 31 routed endpoints.
#    No false path or multicycle exception is added.
# ------------------------------------------------------------

# ------------------------------------------------------------
# 5. 音频 I2S 发生器/接收器跨域
#
#    audio_mclk 域里生成 I2S，video_clk 域里做三拍同步采样。
#    这类路径不是普通同步时序路径，直接切掉更合理。
# ------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks {audio_mclk}] \
    -group [get_clocks {video_clk} hdmi_5x_clk sd_card_clk ext_mem_clk]

# ------------------------------------------------------------
# 6. 可选：如果你的 frame_read_write 内部异步 FIFO 已经完全处理好了跨域，
#    且报告里总出现 video_clk / sd_card_clk / ext_mem_clk 之间的大量伪违例，
#    可以打开下面这组异步分组。
#
#    建议先不要开，先看报告；
#    只有确认这些跨域都只经过 FIFO / 同步器时再开。
# ------------------------------------------------------------
# set_clock_groups -asynchronous \
#     -group [get_clocks {sd_card_clk}] \
#     -group [get_clocks {ext_mem_clk}] \
#     -group [get_clocks {video_clk}] \
#     -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------

# Round2 experimental CDC constraints, exact first sampling boundaries only.
# No clock-group cut. See ../../../../cdc_exact.sdc and review for proof.
set_false_path -from [get_clocks video_clk] -to [get_regs {osd_status_cdc_m0/src_ack_sync[0]}]
set_false_path -from [get_clocks video_clk] -to [get_regs {playback_progress_display_m0/mailbox/src_ack_sync[0]}]
set_false_path -from [get_clocks video_clk] -to [get_regs {fade_transition_cdc_m0/commit_sync[0]}]
set_false_path -from [get_clocks video_clk] -to [get_regs {fade_transition_cdc_m0/done_sync[0]}]
set_false_path -from [get_clocks video_clk] -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/req_sync[0]}]
set_false_path -from [get_clocks ext_mem_clk] -to [get_regs {video_timing_data_m0/read_ack_sync[0]}]
set_false_path -from [get_clocks sd_card_clk] -to [get_regs {osd_status_cdc_m0/dst_request_sync[0]}]
set_false_path -from [get_clocks sd_card_clk] -to [get_regs {playback_progress_display_m0/mailbox/dst_request_sync[0]}]
set_false_path -from [get_clocks sd_card_clk] -to [get_regs {fade_transition_cdc_m0/request_sync[0]}]
set_false_path -from [get_clocks sd_card_clk] -to [get_regs {fade_transition_cdc_m0/ready_sync[0]}]
set_false_path -from [get_clocks sd_card_clk] -to [get_regs {fade_transition_cdc_m0/cancel_sync[0]}]
set_max_delay -datapath_only -from [get_regs {osd_status_cdc_m0/src_hold[*]}] -to [get_regs {osd_status_cdc_m0/dst_data_sync0[*]}] 8.000
set_max_delay -datapath_only -from [get_regs {playback_progress_display_m0/mailbox/src_hold[*]}] -to [get_regs {playback_progress_display_m0/mailbox/dst_data_sync0[*]}] 8.000
set_max_delay -datapath_only -from [get_clocks sd_card_clk] -to [get_regs {fade_transition_cdc_m0/dst_pending_payload[*]}] 8.000
set_max_delay -datapath_only -from [get_clocks video_clk] -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/meta0[*]}] 4.000

# New held-data mailbox uses the SAME 3-stage request/2-stage data protocol as
# the audited OSD mailbox. Only its two control FIRST sampling FFs are exempt.
# All live bundled bits remain bounded to 8ns and subsequent stages are timed.
set_false_path -from [get_clocks video_clk] -to [get_regs {compliance_control_m0/mailbox/src_ack_sync[0]}]
set_false_path -from [get_clocks sd_card_clk] -to [get_regs {compliance_control_m0/mailbox/dst_request_sync[0]}]
set_max_delay -datapath_only -from [get_regs {compliance_control_m0/mailbox/src_hold[*]}] -to [get_regs {compliance_control_m0/mailbox/dst_data_sync0[*]}] 8.000


# M4 only: held transition_busy is observed through THREE SD-domain FFs.
# Exempt only first metastability sampling boundary; stages 1/2 are timed.
set_false_path -from [get_clocks video_clk] -to [get_regs {slide_busy_sync[0]}]
