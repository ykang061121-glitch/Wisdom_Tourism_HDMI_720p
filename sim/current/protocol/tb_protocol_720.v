`timescale 1ns/1fs
// Encrypted production core, real RGB-to-AXIS, original DDS/I2S/receiver/ACR.
// Video replays ONE previously captured full-UI RTL frame; it is not a new
// renderer. Four audio selections test transport independently of scene UI.
module tb_protocol_720;
 reg clk=0,mclk=0,reset=1;always #6.734006734 clk=~clk;always #40.666666667 mclk=~mclk;
 reg[7:0]photo[0:2764799];string path;integer f,n;
 initial begin
  if(!$value$plusargs("RGB=%s",path))$fatal(1,"RGB capture missing");
  f=$fopen(path,"rb");n=$fread(photo,f);$fclose(f);if(n!=2764800)$fatal(1,"RGB capture size");
 end
 reg[10:0]x=0;reg[9:0]y=0;
 wire de=x<1280&&y<720;wire vs=!(y>=725&&y<730);
 wire[23:0]rgb=de?{photo[(y*1280+x)*3],photo[(y*1280+x)*3+1],photo[(y*1280+x)*3+2]}:24'd0;
 always @(posedge clk)if(reset)begin x<=0;y<=0;end else if(x==1649)begin x<=0;y<=y==749?0:y+1'b1;end else x<=x+1'b1;
 wire user,vld,last,ready;wire[23:0]data;
 video_rgb_to_axis_640x480 #(.ACTIVE_WIDTH(1280)) axis(.I_clk(clk),.I_rst(reset),.I_vs(vs),.I_de(de),.I_rgb(rgb),
  .O_video_user(user),.O_video_valid(vld),.O_video_last(last),.O_video_data(data));
 reg[1:0]scene=0;integer cycles=0;
 // Real production fade-out/silence/fade-in is longer than one video frame.
 // Keep selections 4M pixels apart so this fixture does not cancel a song
 // before its envelope is allowed to acknowledge the new active identity.
 always @(posedge clk)if(!reset)begin cycles<=cycles+1;if(cycles==4000000)scene<=1;if(cycles==8000000)scene<=2;if(cycles==12000000)scene<=3;end
 wire su,sv,active,song;wire[1:0]sel,active_image;wire[9:0]status;
 image_audio_cdc cdc(.video_clk(clk),.video_reset(reset),.display_valid(!reset),.display_image(scene),.audio_clk(mclk),.audio_reset(reset),
  .selection_update(su),.selection_valid(sv),.selection_image(sel));
 wire bclk,lrclk,dout,pcm_valid;wire[23:0]left_pcm,right_pcm;
 image_melody_i2s melody(.I_mclk(mclk),.I_rst(reset),.selection_update(su),.selection_valid(sv),.selection_image(sel),
  .active_valid(active),.active_image(active_image),.song_start(song),.playback_status(status),.O_i2s_BCLK(bclk),.O_i2s_LRCK(lrclk),.O_i2s_DOUT(dout));
 I2S_receiver receiver(.I_clk(clk),.I_rst(reset),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrclk),.I_i2s_DOUT(dout),
  .O_audio_valid(pcm_valid),.O_audio_left_data(left_pcm),.O_audio_right_data(right_pcm));
 wire av;wire[19:0]cts,an;
 audio_arc_calculate #(.ACR_N(6144)) acr(.I_clk(clk),.I_rst(reset),.I_audio_valid(pcm_valid),.O_acr_valid(av),.O_acr_cts(cts),.O_acr_n(an));
 wire[9:0]ch0,ch1,ch2,chc;wire scl,sda;
 hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
  .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.VIDEO_VIC(4),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),
  .AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)) core(.I_pixel_clk(clk),.I_rst(reset),.I_edid_read_trig(1'b0),.O_edid_read_valid(),.O_edid_read_data(),
  .I_axis_s_user(user),.I_axis_s_valid(vld),.I_axis_s_last(last),.I_axis_s_data(data),.O_axis_s_ready(ready),
  .I_audio_valid(pcm_valid),.I_audio_left_data(left_pcm),.I_audio_right_data(right_pcm),.I_acr_valid(av),.I_acr_cts(cts),.I_acr_n(an),
  .O_video_locked(),.O_ddc_scl(scl),.IO_ddc_sda(sda),.O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),.O_clk_tmds_data(chc));
 integer fd,pcm_fd,acr_fd,clock_count=0,samples=0,acr_count=0;reg[3:0]songs=0;
 integer bcount=0,slot_count=0,frames=0;realtime previous_lr=0;
 always @(posedge bclk)if(!reset)begin bcount++;slot_count++;end
 always @(lrclk)if(!reset&&$time>10000)begin
  if(slot_count!=64)$fatal(1,"AUDIO720_CHECKER_REJECT slot BCLK %0d",slot_count);slot_count=0;
  if(!lrclk)begin
   if(frames>0 && (bcount!=128 || $realtime-previous_lr<20821.32 || $realtime-previous_lr>20821.35))
    $fatal(1,"AUDIO720_CHECKER_REJECT stereo rate/count %0d %f",bcount,$realtime-previous_lr);
   frames++;bcount=0;previous_lr=$realtime;
  end
 end
 always @(posedge clk)begin
  if(!reset&&pcm_valid)begin
   if(left_pcm!==right_pcm)$fatal(1,"AUDIO720_CHECKER_REJECT channels");samples++;
   $fdisplay(pcm_fd,"%0d %06h %06h %0d %0d",clock_count,left_pcm,right_pcm,active_image,status);
  end
  if(!reset&&av)begin
   acr_count++;if(an!=6144 || (acr_count>1&&(cts<74205||cts>74210)))$fatal(1,"AUDIO720_CHECKER_REJECT CTS %0d",cts);
   $fdisplay(acr_fd,"%0d %0d %0d",clock_count,an,cts);
  end
  if(!reset&&song)songs=songs|(1<<active_image);
  #1;clock_count++;
  $fwrite(fd,"%0d %03h %03h %03h %03h\n",clock_count,ch0,ch1,ch2,chc);
  if(clock_count==16000000)begin
   if(songs!=15||samples<3000||acr_count<60)$fatal(1,"AUDIO720_CHECKER_REJECT coverage songs=%b samples=%0d acr=%0d",songs,samples,acr_count);
   $fclose(fd);$fclose(pcm_fd);$fclose(acr_fd);
   $display("AUDIO720_CORE_CAPTURE_PASS cycles=%0d samples=%0d acr=%0d songs=%h I2S_frames=%0d",clock_count,samples,acr_count,songs,frames);$finish;
  end
 end
 initial begin fd=$fopen("symbols.txt","w");pcm_fd=$fopen("pcm_input.txt","w");acr_fd=$fopen("acr_input.txt","w");#503;reset=0;end
endmodule
