`timescale 1ns/1ps
// RGB frames are recorded ONLY from real RTL output. Uncaptured animation
// frames may be accelerated as blank frame events; captured rasters are 800x525.
module tb_advanced_video;
  reg clk=0,mclk=0,reset=1,frame=0,request=0,ready=0;
  always #20 clk=~clk;always #40.666667 mclk=~mclk;
  reg [1:0] pending=0;wire [1:0] image,buffer_index,mode;
  wire [2:0] level,state;wire [3:0] reveal;wire valid,busy,commit,done;
  fade_transition_ctrl controller(.video_clk(clk),.reset(reset),.frame_start_pulse(frame),
    .transition_request_pulse(request),.transition_cancel_pulse(1'b0),.next_frame_ready(ready),
    .pending_buf_idx({1'b0,pending[0]}),.pending_image_idx(pending),.display_buf_idx(buffer_index),
    .display_image_idx(image),.display_valid(valid),.fade_level(level),.transition_busy(busy),
    .transition_state(state),.swap_commit_pulse(commit),.transition_done_pulse(done));
  reg de=0,hs=1,vs=1;reg [9:0] x=0,y=0;
  reg [23:0] photos[0:1228799];string photo_path;
  integer n,photo_pixel;
  initial begin
    if($value$plusargs("BACKGROUND_HEX=%s",photo_path))$readmemh(photo_path,photos);
    else if($test$plusargs("WRITE_ADVANCED_FRAMES"))$fatal(1,"real BMP fixtures required for previews");
    else for(n=0;n<4;n++)for(photo_pixel=0;photo_pixel<307200;photo_pixel++)
      photos[n*307200+photo_pixel]={8'(photo_pixel%251),8'(n*51),8'((photo_pixel/640)%255)};
  end
  wire [23:0] background=photos[image*307200+y*640+x];
  wire [23:0] adjusted,masked,ui_rgb,baseline_ui,rgb;
  video_adjust adjust(.pixel_clk(clk),.reset(reset),.de(de),.rgb_in(background),
    .brightness(8'sd0),.contrast(2'd1),.rgb_out(adjusted));
  picture_transition effect(.pixel_clk(clk),.reset(reset),.frame_boundary(frame),.de(de),.x(x),.y(y),
    .rgb_in(adjusted),.fade_level(level),.transition_state(state),.pending_image_index(pending),
    .scene_commit(commit),.display_valid(valid),
    .rgb_out(masked),.effect_mode(mode),.reveal_step(reveal));
  wire su,svld,active_valid,song_start,bclk,lrclk,dout,audio_valid;
  wire [1:0] selection,active_image;
  wire [9:0] audio_status,video_status;
  wire [23:0] pcm_left,pcm_right;
  image_audio_cdc selection_cdc(.video_clk(clk),.video_reset(reset),.display_valid(valid),.display_image(image),
    .audio_clk(mclk),.audio_reset(reset),.selection_update(su),.selection_valid(svld),.selection_image(selection));
  image_melody_i2s tx(.I_mclk(mclk),.I_rst(reset),.selection_update(su),.selection_valid(svld),.selection_image(selection),
    .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrclk),.O_i2s_DOUT(dout),.active_valid(active_valid),.active_image(active_image),
    .song_start(song_start),.playback_status(audio_status));
  I2S_receiver rx(.I_clk(clk),.I_rst(reset),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrclk),.I_i2s_DOUT(dout),
    .O_audio_valid(audio_valid),.O_audio_left_data(pcm_left),.O_audio_right_data(pcm_right));
  melody_status_cdc status_cdc(.audio_clk(mclk),.video_clk(clk),.reset(reset),.audio_status(audio_status),.video_status(video_status));
  wire [7:0] sample_index,other_index;wire signed [7:0] amplitude;wire sample_valid;
  audio_wave_capture capture(.pixel_clk(clk),.reset(reset),.audio_valid(audio_valid),.audio_left(pcm_left),
    .frame_boundary(frame),.video_de(de),.read_index(sample_index),.read_amplitude(amplitude),.read_valid(sample_valid),
    .snapshot_valid(),.snapshot_commit());
  reg subs=1,visual=1;reg [1:0] interval_code=1;
  wire oh,ov,od;wire [9:0] ox,oy;
  showcase_presentation layers(.pixel_clk(clk),.reset(reset),.frame_boundary(frame),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),
    .background_rgb(valid?masked:24'd0),.subtitles_visible(subs),.visual_visible(visual),
    .sample_amplitude(amplitude),.sample_valid(sample_valid),.sample_index(sample_index),.audio_status(video_status),
    .display_commit(commit),.display_valid(valid),.image_index(image),.auto_play_enable(1'b1),
    .interval_code(interval_code),.preset_mode(2'd0),.brightness(8'sd0),.contrast(2'd1),.fade_level(level),
    .out_hs(oh),.out_vs(ov),.out_de(od),.out_x(ox),.out_y(oy),.output_rgb(ui_rgb));
  // An unchanged old layer chain proves the satisfied opaque music panel is
  // pixel-identical regardless of the new background masks.
  showcase_presentation frozen_layers(.pixel_clk(clk),.reset(reset),.frame_boundary(frame),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),
    .background_rgb(valid?adjusted:24'd0),.subtitles_visible(subs),.visual_visible(visual),
    .sample_amplitude(amplitude),.sample_valid(sample_valid),.sample_index(other_index),.audio_status(video_status),
    .display_commit(commit),.display_valid(valid),.image_index(image),.auto_play_enable(1'b1),
    .interval_code(interval_code),.preset_mode(2'd0),.brightness(8'sd0),.contrast(2'd1),.fade_level(level),
    .out_hs(),.out_vs(),.out_de(),.out_x(),.out_y(),.output_rgb(baseline_ui));
  reg timer_restart=1,timer_enable=0;
  wire [8:0] units1,units5;wire run1,run5;
  playback_interval_control #(.CLK_FREQ_HZ(1000),.DEFAULT_INTERVAL_CODE(1)) timer1(
    .clk(clk),.reset(reset),.key_interval(1'b1),.timer_enable(timer_enable),.timer_restart(timer_restart),
    .interval_code(),.interval_press(),.auto_tick(),.progress_running(run1),.progress_units(units1));
  playback_interval_control #(.CLK_FREQ_HZ(1000),.DEFAULT_INTERVAL_CODE(2)) timer5(
    .clk(clk),.reset(reset),.key_interval(1'b1),.timer_enable(timer_enable),.timer_restart(timer_restart),
    .interval_code(),.interval_press(),.auto_tick(),.progress_running(run5),.progress_units(units5));
  reg show_progress=0;reg [8:0] progress_frame=0;
  playback_progress_overlay progress(.reset(reset),.de(od),.x(ox),.y(oy),.visible(show_progress),
    .progress_units(progress_frame),.background_rgb(ui_rgb),.output_rgb(rgb));
  reg [22:0] metadata[0:4];reg [23:0] expected_background[0:4];
  integer pipe=0,checks=0,panel_checks=0,frame_pixels=0,file_handle=0,frame_number=0;
  integer expected_mode=0,expected_step=0,expected_level=0;
  reg [23:0] expected,plain,observed;
  function [7:0] scale(input [7:0] c,input integer l);
    case(l)4:scale=c;3:scale=c-c/4;2:scale=c/2;1:scale=c/4;default:scale=0;endcase
  endfunction
  integer stripe,rank;
  always @(posedge clk)begin
    if(reset)pipe=0;
    else begin
      for(integer j=4;j>0;j--)begin metadata[j]=metadata[j-1];expected_background[j]=expected_background[j-1];end
      metadata[0]={hs,vs,de,x,y};plain=background;
      if(expected_mode==0)plain={scale(background[23:16],expected_level),scale(background[15:8],expected_level),scale(background[7:0],expected_level)};
      else if(expected_mode==1 && x>=expected_step*80)plain=0;
      if(!de || !valid || expected_level==0)plain=0;
      expected_background[0]=plain;
      #0.1;
      if(pipe<6)pipe++;else begin
        if({oh,ov,od,ox,oy}!==metadata[4])$fatal(1,"new layers changed 5-clock video alignment");
        observed=rgb;
        if($test$plusargs("INJECT_VIDEO_ALIGNMENT") && od && ox==100 && oy==100)observed=24'hffffff;
        if(!od && rgb!==0)$fatal(1,"blanking not black");
        if(od)begin
          if(oy>=84 && oy<=365 && observed!==expected_background[4])begin
            $display("ADVANCED_CHECKER_REJECT VIDEO_MASK");$fatal(1,"full frame mask mismatch or tearing");end
          if(visual && ox>=400 && ox<=631 && oy>=375 && oy<=451)begin
            panel_checks++;if(rgb!==baseline_ui)$fatal(1,"music panel changed by effect/progress");end
          expected=(show_progress && oy>=475 && oy<=477 && ox>=16 && ox<624 &&
                    ox-16<(progress_frame*608)/256)?24'h38E8DC:ui_rgb;
          if(rgb!==expected)$fatal(1,"progress leaked into other layer");
          if(file_handle!=0)$fwrite(file_handle,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
          frame_pixels++;checks++;
        end
      end
    end
  end
  task advance;begin
    @(negedge clk);de=0;frame=1;@(negedge clk);frame=0;repeat(8)@(negedge clk);
  end endtask
  task raster(input string name);
    integer px,py;
    begin
      frame_pixels=0;
      if($test$plusargs("WRITE_ADVANCED_FRAMES"))file_handle=$fopen({name,".rgb"},"wb");
      for(py=0;py<525;py++)for(px=0;px<800;px++)begin
        @(negedge clk);hs=!(px>=656 && px<752);vs=!(py>=490 && py<492);
        de=px<640 && py<480;x=(px<640)?px:0;y=(py<480)?py:0;
      end
      @(negedge clk);de=0;repeat(8)@(negedge clk);
      if(frame_pixels!=307200)$fatal(1,"wrong full-raster pixel count: %0d",frame_pixels);
      if(file_handle!=0)begin $fclose(file_handle);file_handle=0;end
      frame_number++;
      $display("RTL_FRAME_CAPTURE name=%s image=%0d mode=%0d step=%0d fade=%0d progress=%0d pixels=%0d",name,image,mode,reveal,level,progress_frame,frame_pixels);
    end
  endtask
  task load(input integer target,input integer chosen);
    integer j;
    begin
      @(negedge clk);pending=target;request=1;@(negedge clk);request=0;
      repeat(10)@(negedge clk);ready=1;wait(state==2 || state==3);repeat(8)@(negedge clk);
      if(valid)for(j=1;j<=8;j++)begin
        advance;expected_mode=chosen;expected_step=8-j;expected_level=4-j/2;
        if(j%2==0 && j<8)raster($sformatf("effect%0d_out_step%0d",chosen,8-j));
      end
      expected_mode=chosen;expected_step=0;expected_level=0;
      advance;ready=0; // safe BLACK_SWAP commit, not an arbitrary image-index write
      raster($sformatf("effect%0d_step0",chosen));
      for(j=1;j<=8;j++)begin
        advance;expected_step=j;expected_level=j/2;
        if(j%2==0)raster($sformatf("effect%0d_step%0d",chosen,j));
      end
      expected_step=8;expected_level=4;
    end
  endtask
  initial begin
    repeat(10)@(negedge clk);reset=0;
    load(0,0);raster("forest_stable"); // retain a distinct real forest capture
    load(1,0);load(2,1);load(3,0);load(0,1);
    timer_enable=1;timer_restart=1;repeat(3)@(negedge clk);timer_restart=0;
    repeat(751)@(negedge clk);progress_frame=units1;interval_code=1;show_progress=1;
    advance;raster("auto3_progress25");
    timer_restart=1;repeat(3)@(negedge clk);timer_restart=0;
    repeat(2501)@(negedge clk);progress_frame=units5;interval_code=2;
    advance;raster("auto5_progress50");
    subs=0;visual=0;advance;raster("hidden_layers_progress");
    subs=1;visual=1;advance;raster("restored_layers_progress");
    if(!active_valid || active_image!=image)$fatal(1,"real audio was stopped/mismatched by visual controls");
    if(panel_checks==0 || checks<6000000)$fatal(1,"incomplete raster coverage");
    $display("ADVANCED_VIDEO_TEST_PASS frames=%0d pixels=%0d panel=%0d RGB_HS_VS_DE_XY_aligned",frame_number,checks,panel_checks);$finish;
  end
  initial begin #1000000000;$fatal(1,"advanced raster timeout");end
endmodule
