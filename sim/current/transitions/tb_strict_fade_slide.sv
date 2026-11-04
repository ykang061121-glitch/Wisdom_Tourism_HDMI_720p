`timescale 1ns/1ps
// Real current controller + picture observer. Photo memory is a controlled
// stimulus, not a SiP electrical model. Every sampled output is independent
// mathematical RGB reference; full mode checks all 921600 active pixels/frame.
module tb_strict_fade_slide;
 parameter FULL=0;
 parameter PREVIEW=0;
 reg clk=0,aclk=0,reset=1,frame=0,complete=0,request=0,cancel=0,ready=0,de=0;
 always #6.734 clk=~clk;
 always #17 aclk=~aclk;
 reg[1:0]pending_bank=0,pending_image=0;
 wire[1:0]bank,image,target,effect;
 wire valid,busy,commit,done,slide,style;
 wire[2:0]fade,state;wire[10:0]shift;wire[3:0]reveal;
 reg[10:0]x=0,y=0;reg[23:0]source=0;wire[23:0]rgb;
 wire audio_update,audio_valid;wire[1:0]audio_image;
 wire notice_visible;wire[1:0]notice_index;
 slide_transition_ctrl #(.FRAMES_PER_STEP(2)) ctrl(.video_clk(clk),.reset(reset),.frame_start_pulse(frame),.frame_complete(complete),
  .transition_request_pulse(request),.transition_cancel_pulse(cancel),.next_frame_ready(ready),
  .pending_buf_idx(pending_bank),.pending_image_idx(pending_image),.display_buf_idx(bank),.display_image_idx(image),
  .display_valid(valid),.fade_level(fade),.transition_busy(busy),.transition_state(state),.swap_commit_pulse(commit),
  .transition_done_pulse(done),.slide_active(slide),.slide_shift(shift),.slide_target(target),.active_style(style));
 picture_transition #(.COORD_BITS(11),.ACTIVE_WIDTH(1280)) picture(.pixel_clk(clk),.reset(reset),
  .frame_boundary(frame),.de(de),.x(x),.y(y),.rgb_in(source),.fade_level(fade),.transition_state(state),
  .pending_image_index(pending_image),.scene_commit(commit),.display_valid(valid),.rgb_out(rgb),.effect_mode(effect),.reveal_step(reveal));
 image_audio_cdc audio_identity(.video_clk(clk),.video_reset(reset),.display_valid(valid),.display_image(image),
  .audio_clk(aclk),.audio_reset(reset),.selection_update(audio_update),.selection_valid(audio_valid),.selection_image(audio_image));
 scene_notice notice(.pixel_clk(clk),.reset(reset),.frame_boundary(frame),.display_commit(commit),.display_valid(valid),.display_image(image),
  .visible(notice_visible),.scene_index(notice_index));
 reg[7:0]photos[0:11059199];integer fd,loaded,scene_no=0,old_scene=0,mode=0;
 integer commits=0,dones=0,pixels=0,frames=0,ordinary=0,slide_frames=0,fade_frames=0,stable_frames=0;
 integer fade_levels_seen=0,wait_checks=0,cancel_checks=0,busy_checks=0,identity_checks=0;
 integer last_frame_shift=-1,capture=-1;reg[32:0]shifts_seen=0;
 reg monitor=0;reg[1:0]previous_image=0,previous_bank=0;reg previous_valid=0;
 function[23:0]photo(input integer which,input integer px,input integer py);
  integer a;begin a=(which*921600+py*1280+px)*3;photo={photos[a],photos[a+1],photos[a+2]};end
 endfunction
 function[23:0]scale(input[23:0]p,input integer lev);
  integer n,r,g,b;begin
   // Independent rational intensity rule, with original 75% ceiling.
   n=(lev==3)?1:0;
   r=lev==3?(3*p[23:16]+3)/4:p[23:16]*lev/4;
   g=lev==3?(3*p[15:8]+3)/4:p[15:8]*lev/4;
   b=lev==3?(3*p[7:0]+3)/4:p[7:0]*lev/4;
   scale={8'(r),8'(g),8'(b)};
  end
 endfunction
 task fail(input string reason);
  begin $display("STRICT_TRANSITION_REJECT %s scene=%0d ordinary=%0d frame=%0d state=%0d fade=%0d shift=%0d effect=%0d xy=%0d,%0d rgb=%h",reason,scene_no,ordinary,frames,state,fade,shift,effect,x,y,rgb);$fatal(1);end
 endtask
 always @(posedge clk)begin
  #0.001;
  if(!reset)begin
   if(commit)begin
    commits=commits+1;
    if(!ready)fail("commit before complete next-frame ready");
    if(state==4 && !ctrl.slide_post && fade!=0)fail("black commit did not require level zero");
    if(ctrl.slide_post && (image!=pending_image || bank!=target))fail("slide identity not atomic");
   end
   if(done)dones=dones+1;
   if(monitor && (image!=previous_image||bank!=previous_bank||valid!=previous_valid)&&!commit)
    fail("scene identity moved without safe commit");
   previous_image=image;previous_bank=bank;previous_valid=valid;
  end else begin previous_image=0;previous_bank=0;previous_valid=0;end
 end
 task pixel(input integer px,input integer py);
  reg[23:0]expected,raw;integer sx,which;
  begin
   @(negedge clk);de=1;x=px;y=py;
   if(slide)begin
    if(px<1280-shift)begin which=old_scene;sx=px+shift;end
    else begin which=scene_no;sx=px-(1280-shift);end
   end else begin which=image;sx=px;end
   raw=photo(which,sx,py);source=raw;
   if(!valid||fade==0||state==3)expected=0;
   else expected=scale(raw,fade);
   #0.001;
   if(rgb!==expected)fail("actual photo RGB differs from FADE/continuous SLIDE reference");
   pixels=pixels+1;
   if(capture!=-1)$fwrite(capture,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
  end
 endtask
 task raster;
  integer px,py,want_capture;string path;
  begin
   want_capture=FULL && ((ordinary==3 && (state==0 || state==2 || state==3 || state==4)) || (ordinary==2 && slide));
   if(want_capture)begin
    path=$sformatf("rtl_ordinary%0d_frame%03d_state%0d_level%0d_shift%04d.rgb",ordinary,frames,state,fade,shift);
    capture=$fopen(path,"wb");if(!capture)fail("capture open");
   end
   if(FULL && (!PREVIEW || want_capture))for(py=0;py<720;py=py+1)for(px=0;px<1280;px=px+1)pixel(px,py);
   else for(py=0;py<720;py=py+359)for(px=0;px<1280;px=px+39)pixel(px,py);
   if(capture!=-1)begin $fclose(capture);capture=-1;end
   frames=frames+1;
   if(slide)begin
    slide_frames=slide_frames+1;shifts_seen[shift/40]=1;
    if(fade!=4 || effect!=0)fail("slide masked by black/legacy wipe");
   end else if(state==2 || state==4)begin fade_frames=fade_frames+1;fade_levels_seen=fade_levels_seen|(1<<fade);end
   else if(state==0)stable_frames=stable_frames+1;
   @(negedge clk);de=0;complete=1;@(negedge clk);complete=0;
   repeat(5)@(negedge clk);frame=1;@(negedge clk);frame=0;repeat(5)@(negedge clk);
  end
 endtask
 task pulse_request;
  begin @(negedge clk);request=1;@(negedge clk);request=0;repeat(3)@(negedge clk);end
 endtask
 task cancel_unready;
  integer c;reg token;begin
   c=commits;token=ctrl.next_style;old_scene=image;ready=0;pulse_request;
   repeat(3)begin
    raster;wait_checks=wait_checks+1;
    if(state!=1||commit||image!=old_scene||ctrl.next_style!=token)fail("WAIT consumed style or old scene");
   end
   @(negedge clk);cancel=1;@(negedge clk);cancel=0;repeat(3)@(negedge clk);
   if(state!=0||commits!=c||ctrl.next_style!=token)fail("cancel consumed style/committed");
   cancel_checks=cancel_checks+1;
  end
 endtask
 task load_scene(input integer which,input integer is_boot);
  integer n,old_done,c,expected_slide;reg[1:0]before_image;
  begin
   scene_no=which;old_done=dones;c=commits;before_image=image;old_scene=image;
   pending_bank=~bank;pending_bank={1'b0,pending_bank[0]};pending_image=which;ready=0;
   pulse_request;
   // Alternate AUTO/manual launch sources through the same request port.
   $display("STRICT_LAUNCH scene=%0d ordinary=%0d source=%s",which,ordinary,(ordinary%2)?"AUTO":"K2");
   n=ordinary%3;
   repeat(n+1)begin raster;wait_checks=wait_checks+1;if(state!=1||image!=before_image)fail("preload WAIT changed identity");end
   @(negedge clk);ready=1;repeat(5)@(negedge clk);
   expected_slide=!is_boot && ordinary%2==0;
   n=0;
   while(dones==old_done)begin
    if(style!==expected_slide[0])fail("FADE/SLIDE strict alternation violated");
    if(!expected_slide && effect!=0 && state==2)fail("legacy WIPE selected during required FADE");
    // A busy K2 must not consume an extra effect/scene.
    if(n==2)begin pulse_request;busy_checks=busy_checks+1;end
    raster;n=n+1;if(n>60)fail("transition watchdog");
   end
   if(commits!=c+1||image!=which||bank!=pending_bank)fail("one safe atomic commit per successful scene");
   repeat(40)@(negedge clk);
   if(!audio_valid||audio_image!=which||notice_index!=which)fail("audio/title target mismatched committed scene");
   identity_checks=identity_checks+1;
   $display("STRICT_SCENE_PASS scene=%0d ordinary=%0d style=%0d commits=%0d audio=%0d title=%0d",which,ordinary,style,commits,audio_image,notice_index);
  end
 endtask
 integer k;
 initial begin
  fd=$fopen("../four_photos.rgb","rb");if(!fd)fail("actual photo stimulus missing");
  loaded=$fread(photos,fd);$fclose(fd);if(loaded!=11059200)fail("photo byte count");
  repeat(5)@(negedge clk);reset=0;monitor=1;
  load_scene(0,1);
  for(k=1;k<=8;k=k+1)begin
   ordinary=k;
   if(k==3||k==6)cancel_unready;
   load_scene(k%4,0);
   if(PREVIEW && k==3)begin
    raster; // Capture the actual stable 100%-new frame after FADE_IN DONE.
    $display("STRICT_TRANSITION_PREVIEW_PASS real_rgb_frames=FADE_AND_SLIDE pixels=%0d frames=%0d",pixels,frames);$finish;
   end
  end
  if(commits!=9||shifts_seen!==33'h1ffffffff||fade_levels_seen!=31||identity_checks!=9||cancel_checks!=2)
   fail("coverage missing");
  // Reset must recover the initial FADE independently of earlier parity.
  @(negedge clk);reset=1;monitor=0;repeat(4)@(negedge clk);reset=0;monitor=1;ordinary=0;
  load_scene(0,1);ordinary=1;load_scene(1,0);
  if(style!=0||effect!=0)fail("reset did not restart ordinary FADE");
  $display("STRICT_TRANSITION_PASS two_rounds=8 boot_excluded=1 reset_restart=1 pixels=%0d frames=%0d slide_frames=%0d fade_frames=%0d wait=%0d cancels=%0d busy_requests=%0d identity=%0d FULL=%0d",pixels,frames,slide_frames,fade_frames,wait_checks,cancel_checks,busy_checks,identity_checks,FULL);
  $finish;
 end
 initial begin #(64'd10000000000);fail("global watchdog");end
endmodule
