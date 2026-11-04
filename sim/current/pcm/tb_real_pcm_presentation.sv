`timescale 1ns/1ps
// Focused production-component test. Background is a declared test color;
// screenshot acceptance uses the separate real-RAW full-chain driver.
module tb_real_pcm_presentation;
 reg clk=0,mclk=0,reset=1;
 always #6.734 clk=~clk;always #40.666666667 mclk=~mclk;
 reg boundary=0,hs=0,vs=0,de=0;
 reg[10:0]x=0,y=0;
 wire selection_update,selection_valid;wire[1:0]selection_image;
 wire bclk,lrck,dout,pcm_valid;wire[23:0]pcm_left,pcm_right;
 wire[9:0]music_audio,music_video;
 image_audio_cdc selection(.video_clk(clk),.video_reset(reset),.display_valid(1'b1),.display_image(2'd0),
  .audio_clk(mclk),.audio_reset(reset),.selection_update(selection_update),.selection_valid(selection_valid),.selection_image(selection_image));
 image_melody_i2s audio(.I_mclk(mclk),.I_rst(reset),.selection_update(selection_update),.selection_valid(selection_valid),.selection_image(selection_image),
  .active_valid(),.active_image(),.song_start(),.playback_status(music_audio),.O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
 I2S_receiver pcm(.I_clk(clk),.I_rst(reset),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),
  .O_audio_valid(pcm_valid),.O_audio_left_data(pcm_left),.O_audio_right_data(pcm_right));
 melody_status_cdc status(.audio_clk(mclk),.video_clk(clk),.reset(reset),.audio_status(music_audio),.video_status(music_video));
 wire snapshot_valid,analysis_busy,overrun,received;
 wire[127:0]snapshot_levels,frame_levels;
 pcm_spectrum_dft512 analysis(.clk(clk),.reset(reset),.sample_valid(pcm_valid),.pcm_sample(pcm_left),
  .snapshot_valid(snapshot_valid),.snapshot_levels(snapshot_levels),.snapshot_power(),.busy(analysis_busy),.overrun(overrun));
 spectrum_snapshot_cdc mailbox(.src_clk(clk),.src_reset(reset),.src_snapshot_valid(snapshot_valid),.src_levels(snapshot_levels),.src_ready(),
  .video_clk(clk),.video_reset(reset),.frame_boundary(boundary),.frame_levels(frame_levels),.frame_commit(),.received_pulse(received));
 wire[7:0]sample_index;wire signed[7:0]amplitude;wire sample_valid;
 audio_wave_capture wave(.pixel_clk(clk),.reset(reset),.audio_valid(pcm_valid),.audio_left(pcm_left),.frame_boundary(boundary),.video_de(de),
  .read_index(sample_index),.read_amplitude(amplitude),.read_valid(sample_valid),.snapshot_valid(),.snapshot_commit());
 reg negative=0;
 wire ph,pv,pd;wire[10:0]px,py;wire[23:0]presentation_rgb;
 wire[127:0]display_levels=negative?128'd0:frame_levels;
 showcase_presentation_pipeline #(.SPECTRUM_ENABLE(1),.COORD_BITS(11),.VIDEO_720P(1),.COMPLIANCE_UI(1),.PERCENT_CONTRAST(1),.TOURISM_TEXT(1)) presentation(
  .pixel_clk(clk),.reset(reset),.frame_boundary(boundary),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),.background_rgb(24'h536F91),
  .subtitles_visible(1'b1),.visual_visible(1'b1),.sample_amplitude(amplitude),.sample_valid(sample_valid),.sample_index(sample_index),
  .audio_status(music_video),.spectrum_levels(display_levels),.error_status(8'd0),.display_commit(1'b0),.display_valid(1'b1),.auto_play_enable(1'b0),
  .image_index(2'd0),.interval_code(2'd2),.preset_mode(2'd0),.brightness(8'sd0),.contrast(8'd100),.brightness_digits(12'd0),.contrast_digits(12'h100),
  .fade_level(3'd4),.scaling_meta_valid(1'b0),.adjust_mode(1'b0),.adjust_target_contrast(1'b0),.adjust_fast(1'b0),.waiting_for_scene(1'b0),.scaling_meta_bcd(64'd0),
  .out_hs(ph),.out_vs(pv),.out_de(pd),.out_x(px),.out_y(py),.output_rgb(presentation_rgb));
 wire oh,ov,od;wire[10:0]ox,oy;wire[23:0]output_rgb;
 hdmi_diagnostic_overlay #(.SHOW_FIXED_CHINESE(1),.SHOW_DIAGNOSTIC_LABEL(0)) terminal(
  .pixel_clk(clk),.reset(reset),.hs(ph),.vs(pv),.de(pd),.x(px),.y(py),.rgb(presentation_rgb),.phase(2'd0),
  .frame_boundary(boundary),.scene_index(2'd0),.chinese_enable(1'b1),
  .out_hs(oh),.out_vs(ov),.out_de(od),.out_x(ox),.out_y(oy),.out_rgb(output_rgb));
 integer pcm_samples=0,snapshots=0,metadata_checks=0,active_pixels=0,bar_checks=0,lit_checks=0;
 reg[24:0]expected_metadata[0:9];integer i,primed=0,column,height;
 reg[23:0]expected_rgb;
 reg checking=0;
 always @(posedge clk)begin
  if(reset)begin for(i=0;i<10;i=i+1)expected_metadata[i]=0;primed=0;end
  else begin
   if(pcm_valid)begin pcm_samples=pcm_samples+1;if(pcm_left!==pcm_right)$fatal(1,"M5_PCM_PRESENTATION_REJECT unequal PCM channels");end
   if(snapshot_valid)snapshots=snapshots+1;
   if(overrun)$fatal(1,"M5_PCM_PRESENTATION_REJECT actual PCM rate overrun");
   for(i=9;i>0;i=i-1)expected_metadata[i]=expected_metadata[i-1];expected_metadata[0]={hs,vs,de,x,y};
   #0.03;
   if(primed>=10)begin
    if({oh,ov,od,ox,oy}!==expected_metadata[9])$fatal(1,"M5_PCM_PRESENTATION_REJECT ten-cycle metadata");
    metadata_checks=metadata_checks+1;
   end else primed=primed+1;
  end
 end
 always @(negedge clk)if(checking && od)begin
  if(ox!==active_pixels%1280 || oy!==active_pixels/1280)$fatal(1,"M5_PCM_PRESENTATION_REJECT frame pixel order");
  active_pixels=active_pixels+1;
  if(ox>=1040 && ox<1248 && oy>=649 && oy<=679)begin
   column=(ox-1040)/13;height=frame_levels[column*8+:8]/8;expected_rgb=24'h0B1725;
   if((ox-1040)%13<11 && height>0 && oy>679-height)begin
    case(column/4)0:expected_rgb=24'h00EEA0;1:expected_rgb=24'h28CFE8;2:expected_rgb=24'h4294F0;3:expected_rgb=24'hA878EC;endcase
    lit_checks=lit_checks+1;
   end
   if(output_rgb!==expected_rgb)$fatal(1,"M5_PCM_PRESENTATION_REJECT independent real spectrum pixel x%0d y%0d band%0d height%0d got%h expected%h",ox,oy,column,height,output_rgb,expected_rgb);
   bar_checks=bar_checks+1;
  end
 end
 integer hp,vp;
 initial begin
  negative=$test$plusargs("ZERO_BANDS");
  repeat(10)@(negedge clk);reset=0;
  wait(received);repeat(5)@(negedge clk);
  boundary=1;@(negedge clk);boundary=0;repeat(5)@(negedge clk);
  if(frame_levels==0)$fatal(1,"M5_PCM_PRESENTATION_REJECT no actual PCM-derived levels");
  checking=1;
  for(vp=0;vp<750;vp=vp+1)for(hp=0;hp<1650;hp=hp+1)begin
   @(negedge clk);x=hp;y=vp;de=(hp<1280&&vp<720);hs=!(hp>=1390&&hp<1430);vs=!(vp>=725&&vp<730);
  end
  @(negedge clk);de=0;repeat(20)@(negedge clk);
  if(active_pixels!=921600 || pcm_samples<512 || snapshots<1 || bar_checks!=6448 || lit_checks<100)
   $fatal(1,"M5_PCM_PRESENTATION_REJECT incomplete frame/spectrum coverage");
  $display("M5_REAL_PCM_PRESENTATION_PASS active_pixels=%0d pcm_samples=%0d snapshots=%0d bar_checks=%0d lit_checks=%0d metadata_checks=%0d levels=%h",active_pixels,pcm_samples,snapshots,bar_checks,lit_checks,metadata_checks,frame_levels);$finish;
 end
 initial begin #100000000;$fatal(1,"M5_PCM_PRESENTATION_REJECT timeout");end
endmodule
