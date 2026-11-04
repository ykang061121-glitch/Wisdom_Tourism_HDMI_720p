`timescale 1ns/1ps
module tb_picture_transitions;
  reg clk=0,src=0,mclk=0,reset=1,frame=0;
  always #5 clk=~clk;always #7 src=~src;always #3 mclk=~mclk;
  reg req_toggle=0,ready_toggle=0,cancel_toggle=0;
  reg [3:0] payload=0;
  reg start=0,cancel=0,arm=0,source_done=0,scale_done=0,memory_done=0;
  wire complete;
  frame_completion_guard guard(.clk(src),.reset(reset),.start(start),.cancel(cancel),.memory_arm(arm),
    .source_done(source_done),.scale_done(scale_done),.memory_done(memory_done),
    .source_seen(),.scale_seen(),.memory_seen(),.ready_pulse(complete));
  always @(posedge src)if(reset)ready_toggle<=0;else if(complete)ready_toggle<=~ready_toggle;
  wire request,abort_request,ready,commit,done,valid,busy;
  wire [3:0] bundled;wire [1:0] buf_idx,image,mode;wire [2:0] level,state;wire [3:0] step;
  fade_transition_cdc cdc(.src_clk(src),.src_reset(reset),.src_request_toggle(req_toggle),
    .src_ready_toggle(ready_toggle),.src_cancel_toggle(cancel_toggle),.src_pending_payload(payload),
    .src_commit_pulse(),.src_transition_done_pulse(),.dst_clk(clk),.dst_reset(reset),
    .dst_request_pulse(request),.dst_cancel_pulse(abort_request),.dst_next_frame_ready(ready),
    .dst_pending_payload(bundled),.dst_commit_pulse(commit),.dst_transition_done_pulse(done));
  fade_transition_ctrl #(.FRAMES_PER_STEP(2)) control(.video_clk(clk),.reset(reset),.frame_start_pulse(frame),
    .transition_request_pulse(request),.transition_cancel_pulse(abort_request),.next_frame_ready(ready),
    .pending_buf_idx(bundled[1:0]),.pending_image_idx(bundled[3:2]),.display_buf_idx(buf_idx),
    .display_image_idx(image),.display_valid(valid),.fade_level(level),.transition_busy(busy),
    .transition_state(state),.swap_commit_pulse(commit),.transition_done_pulse(done));
  reg de=1;reg [9:0] x=0,y=239;
  wire [23:0] background={image,6'b110101,8'hac,8'h63};
  wire [23:0] rgb;
  picture_transition effect(.pixel_clk(clk),.reset(reset),.frame_boundary(frame),.de(de),.x(x),.y(y),
    .rgb_in(background),.fade_level(level),.transition_state(state),.pending_image_index(bundled[3:2]),
    .scene_commit(commit),.display_valid(valid),
    .rgb_out(rgb),.effect_mode(mode),.reveal_step(step));
  wire [23:0] narrow_rgb;
  picture_transition #(.ACTIVE_WIDTH(320)) narrow_wipe(.pixel_clk(clk),.reset(reset),.frame_boundary(frame),
    .de(de),.x(x),.y(y),.rgb_in(background),.fade_level(level),.transition_state(state),
    .pending_image_index(bundled[3:2]),.scene_commit(commit),.display_valid(valid),
    .rgb_out(narrow_rgb),.effect_mode(),.reveal_step());
  wire selection_update,selection_valid;wire [1:0] selected,active_image;
  wire active_valid;
  image_audio_cdc music_cdc(.video_clk(clk),.video_reset(reset),.display_valid(valid),.display_image(image),
    .audio_clk(mclk),.audio_reset(reset),.selection_update(selection_update),.selection_valid(selection_valid),.selection_image(selected));
  image_melody_i2s #(.BASE_NOTE_SAMPLES(64),.RAMP_HOLD_SAMPLES(1),.SILENCE_SAMPLES(2)) music(
    .I_mclk(mclk),.I_rst(reset),.selection_update(selection_update),.selection_valid(selection_valid),.selection_image(selected),
    .O_i2s_BCLK(),.O_i2s_LRCK(),.O_i2s_DOUT(),.active_valid(active_valid),.active_image(active_image),.song_start(),.playback_status());
  integer swaps=0,pixels=0;reg [2:0] oldstate,oldlevel;reg [3:0] oldstep;
  reg oldready,oldframe,observed_commit;
  always @(posedge clk)begin
    oldstate=state;oldlevel=level;oldstep=step;oldready=ready;oldframe=frame;
    #0.1;
    if(!reset)begin
      observed_commit=commit;
      if($test$plusargs("INJECT_EARLY_COMMIT") && oldstate==2 && ready)observed_commit=1;
      if(observed_commit && !(oldstate==3 && oldlevel==0 && oldstep==0 && oldready && oldframe))begin
        $display("ADVANCED_CHECKER_REJECT EARLY_COMMIT");$fatal(1,"nonblack or unready swap");
      end
      if(commit)swaps++;
    end
  end
  function [7:0] reference_scale(input [7:0] c,input integer l);
    case(l)4:reference_scale=c;3:reference_scale=c-c/4;2:reference_scale=c/2;1:reference_scale=c/4;default:reference_scale=0;endcase
  endfunction
  task row(input integer expected_mode,expected_step,expected_level);
    integer px,stripe,rank;reg [23:0] expected,observed;
    begin
      if(mode!==expected_mode[1:0] || step!==expected_step[3:0] || level!==expected_level[2:0])
        $fatal(1,"frame-level effect state mismatch mode=%d step=%d level=%d expected=%d/%d/%d",mode,step,level,expected_mode,expected_step,expected_level);
      for(px=0;px<640;px++)begin
        @(negedge clk);x=px;#1;expected=background;
        if(expected_mode==0)expected={reference_scale(background[23:16],expected_level),reference_scale(background[15:8],expected_level),reference_scale(background[7:0],expected_level)};
        else if(expected_mode==1 && px>=expected_step*80)expected=0;
        if(expected_level==0 || state==3)expected=0;
        observed=rgb;
        if($test$plusargs("INJECT_MASK_LEAK") && expected_level==0 && px==37)observed=background;
        if(observed!==expected)begin
          $display("ADVANCED_CHECKER_REJECT MASK x=%0d mode=%0d step=%0d got=%h expected=%h",px,expected_mode,expected_step,observed,expected);
          $fatal(1,"mask boundary, direction or final clear mismatch");
        end
        if(expected_mode==1)begin
          expected=(expected_level!=0 && (state==0 || state==1 || px<expected_step*40))?background:24'd0;
          if(narrow_rgb!==expected)$fatal(1,"parameterized wipe width boundary");
        end
        pixels++;
      end
    end
  endtask
  task pulse_frame;begin @(negedge clk);frame=1;@(negedge clk);frame=0;repeat(4)@(negedge clk);end endtask
  task source_pulse(input integer which);
    begin
      @(negedge src);case(which)0:start=1;1:arm=1;2:source_done=1;3:scale_done=1;4:memory_done=1;endcase
      @(negedge src);start=0;arm=0;source_done=0;scale_done=0;memory_done=0;
    end
  endtask
  task transition(input integer target,input integer automatic_request);
    integer j,chosen,before_swap;reg was_valid;reg [1:0] oldimage,oldbuf;
    begin
      was_valid=valid;oldimage=image;oldbuf=buf_idx;before_swap=swaps;
      @(negedge src);payload={target[1:0],(was_valid?(buf_idx^2'd1):2'd0)};req_toggle=~req_toggle;
      source_pulse(0);source_pulse(1);wait(state==1);repeat(30)@(negedge clk);
      if(image!=oldimage || buf_idx!=oldbuf || (was_valid && level!=4))$fatal(1,"load wait changed picture");
      // Completion order differs between manual and automatic requests.
      source_pulse(automatic_request?4:2);source_pulse(3);
      repeat(20)@(negedge clk);if(state!=1 || swaps!=before_swap)$fatal(1,"early frame ready");
      source_pulse(automatic_request?2:4);
      chosen=was_valid?((before_swap-1)%2):0;
      wait(state==2 || state==3);
      if(was_valid)begin
        j=1;
        if(target==1)begin
          // First OUT cycle and frame pulse coincide: do not lose a step.
          pulse_frame;row(chosen,7,4);j=2;
        end else begin repeat(5)@(negedge clk);row(chosen,8,4);end
        for(j=j;j<=8;j++)begin
          pulse_frame;row(chosen,8-j,4-j/2);
          if(j==3)begin @(negedge src);req_toggle=~req_toggle;end // extra busy next must not queue
        end
      end else begin chosen=0;repeat(5)@(negedge clk);end
      if(state!=3 || image!=oldimage)$fatal(1,"must hold old buffer until black");
      row(chosen,0,0);pulse_frame;
      if(image!=target || swaps!=before_swap+1)$fatal(1,"wrong commit/index count");
      row(chosen,0,0);
      for(j=1;j<=8;j++)begin pulse_frame;row(chosen,j,j/2);end
      if(busy || state!=0 || image!=target)$fatal(1,"transition did not finish");
      repeat(10000)@(negedge clk);
      if(swaps!=before_swap+1 || !active_valid || active_image!=target || selected!=target)
        $fatal(1,"extra busy swap or melody mismatch");
      $display("TRANSITION_CASE_PASS target=%0d automatic=%0d mode=%0d",target,automatic_request,chosen);
    end
  endtask
  integer saved;reg [1:0] savedimage;
  initial begin
    repeat(8)@(negedge clk);reset=0;
    transition(0,0);transition(1,0);transition(2,1);transition(3,1);transition(0,0);
    saved=swaps;savedimage=image;
    @(negedge src);req_toggle=~req_toggle;source_pulse(0);source_pulse(1);
    wait(state==1);repeat(200)@(negedge clk);
    if(image!=savedimage || level!=4)$fatal(1,"failed load revealed pending frame");
    @(negedge src);cancel=1;cancel_toggle=~cancel_toggle;@(negedge src);cancel=0;
    wait(state==0);if(swaps!=saved || image!=savedimage)$fatal(1,"cancel swapped buffer");
    reset=1;repeat(8)@(negedge clk);reset=0;repeat(8)@(negedge clk);
    if(valid || swaps!=saved || busy)$fatal(1,"reset leaked picture/commit");
    $display("PICTURE_TRANSITIONS_TEST_PASS pixels=%0d commits=%0d two_alternating_modes guard CDC cancel busy audio",pixels,swaps);$finish;
  end
  initial begin #10000000;$fatal(1,"transition test timeout");end
endmodule
