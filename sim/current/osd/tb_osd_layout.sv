`timescale 1ns/1ps
`define PP(H,V,D,X,Y,R) .pixel_clk(clk),.reset(reset),.frame_boundary(boundary),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),.background_rgb(bg), \
 .subtitles_visible(sub_on),.visual_visible(vis_on),.sample_amplitude(8'sd18),.sample_valid(1'b1),.sample_index(),.audio_status(10'h201),.spectrum_levels(128'h20_30_40_50_60_70_80_90_A0_B0_C0_D0_E0_F0_60_70),.error_status(error_code), \
 .display_commit(commit),.display_valid(1'b1),.auto_play_enable(auto_mode),.image_index(idx),.interval_code(code),.preset_mode(preset),.brightness(8'sd0),.contrast(8'd100), \
 .brightness_digits(12'h000),.contrast_digits(12'h100),.fade_level(3'd4),.scaling_meta_valid(1'b1),.adjust_mode(adj),.adjust_target_contrast(1'b0),.adjust_fast(1'b0),.waiting_for_scene(waiting),.scaling_meta_bcd(64'h1920108012800720), \
 .out_hs(H),.out_vs(V),.out_de(D),.out_x(X),.out_y(Y),.output_rgb(R)
module tb_osd_layout;
 reg clk=0;always #6.734 clk=~clk;
 reg reset=1,boundary=0,hs=0,vs=0,de=0,sub_on=1,vis_on=1,commit=0,auto_mode=1,adj=0,waiting=0;
 reg[10:0]x=0,y=0;reg[23:0]bg=24'hFFFFFF;reg[1:0]idx=0,code=2,preset=0;reg[7:0]error_code=0;
 wire nh,nv,nd,oh,ov,od;wire[10:0]nx,ny,ox,oy;wire[23:0]nr,orr;
 showcase_presentation_pipeline #(.COORD_BITS(11),.VIDEO_720P(1),.COMPLIANCE_UI(1),.PERCENT_CONTRAST(1),.SPECTRUM_ENABLE(1),.TOURISM_TEXT(1)) dut(`PP(nh,nv,nd,nx,ny,nr));
 showcase_presentation_pipeline_frozen #(.COORD_BITS(11),.VIDEO_720P(1),.COMPLIANCE_UI(1),.PERCENT_CONTRAST(1),.SPECTRUM_ENABLE(1),.TOURISM_TEXT(1)) original(`PP(oh,ov,od,ox,oy,orr));
 // Independent original layer input delayed five cycles reconstructs the
 // image below the UI; no edited DUT masks or pixels feed the reference.
 reg[23:0]under_ui[0:4];reg[48:0]side[0:7];integer k;
 always @(posedge clk)begin
  if(reset)begin for(k=0;k<5;k++)under_ui[k]<=0;for(k=0;k<8;k++)side[k]<=0;end
  else begin
   under_ui[0]<=original.visible_s2?original.subtitle_rgb:original.bypass_s2;
   for(k=1;k<5;k++)under_ui[k]<=under_ui[k-1];
   side[0]<={hs,vs,de,x,y,bg};for(k=1;k<8;k++)side[k]<=side[k-1];
  end
 end
 integer checked=0,hidden_scene=0,hidden_interval=0,hidden_mode=0,kept_pixels=0,frames=0,f,xx,yy,fp,rd,pos,n,fd0=-1,fd1=-1,fd2=-1,fd3=-1;
 reg[7:0]photos[0:11059199];reg[1023:0]rootpath;reg[2047:0]name;
 reg[23:0]expected;reg suppress_scene,suppress_hint;
 always @(negedge clk)if(!reset)begin
  if({nh,nv,nd,nx,ny}!=={oh,ov,od,ox,oy} || {nh,nv,nd,nx,ny}!==side[7][48:24])$fatal(1,"OSD_LAYOUT_REJECT metadata/8-cycle alignment");
  if({dut.hint_remaining,dut.hint_kind,dut.notice.visible,dut.notice.remaining,dut.notice.scene_index,dut.param_remaining}!=={original.hint_remaining,original.hint_kind,original.notice.visible,original.notice.remaining,original.notice.scene_index,original.param_remaining})$fatal(1,"OSD_LAYOUT_REJECT internal state changed");
  if(nd && (ny<20 || ny>=36) && nr!==orr)$fatal(1,"OSD_LAYOUT_REJECT pixel outside top frame%0d x%0d y%0d",f,nx,ny);
  if(nd)begin
   checked++;
   if(fd2!=0 && fd2!=-1)$fwrite(fd2,"%c%c%c",under_ui[4][23:16],under_ui[4][15:8],under_ui[4][7:0]);
   if(fd3!=0 && fd3!=-1)$fwrite(fd3,"%c",original.ui.foreground_dot?1:original.ui.top_right_shadow?2:0);
   if(fd0!=0 && fd0!=-1)$fwrite(fd0,"%c%c%c",orr[23:16],orr[15:8],orr[7:0]);
   if(fd1!=0 && fd1!=-1)$fwrite(fd1,"%c%c%c",nr[23:16],nr[15:8],nr[7:0]);
  end
 end
 task frame_boundary;
 begin @(negedge clk);boundary=1;@(negedge clk);boundary=0;repeat(12)@(negedge clk);end endtask
 initial begin
  if(!$value$plusargs("INPUT_ROOT=%s",rootpath))$fatal(1,"input root");
  for(f=0;f<4;f++)begin $sformat(name,"%0s/photo%0d.rgb",rootpath,f);fp=$fopen(name,"rb");rd=$fread(photos,fp,f*2764800,2764800);$fclose(fp);if(rd!=2764800)$fatal(1,"photo length");end
  repeat(8)@(negedge clk);reset=0;frame_boundary();
  for(f=0;f<($test$plusargs("QUICK")?1:12);f++)begin
   de=0;error_code=0;adj=0;waiting=0;
   case(f)
    0:begin idx=0;commit=1;end // scene only, white
    1:begin code=3;end // INTERVAL 10, dark
    2:begin code=1;idx=0;end // INTERVAL03, west lake
    3:begin auto_mode=0;idx=1;commit=1;end // mode+scene, palace
    4:begin preset=3;idx=2;end // preset unchanged visible
    5:begin sub_on=0;idx=3;end // SUB remains visible
    6:begin vis_on=0;end // VIS remains visible
    7:begin error_code=8'hE1;end // Error remains visible
    8:begin waiting=1;end // WAIT remains visible
    9:begin adj=1;end // ADJ remains visible
    10:begin auto_mode=1;code=2;commit=1;idx=2;end // simultaneous latest commit
    11:begin reset=1;repeat(8)@(negedge clk);reset=0;end
   endcase
   frame_boundary();commit=0;repeat(12)@(negedge clk);
   $sformat(name,"RTL_OSD_before_f%0d.rgb",f);fd0=$fopen(name,"wb");$sformat(name,"RTL_OSD_after_f%0d.rgb",f);fd1=$fopen(name,"wb");$sformat(name,"RTL_OSD_under_f%0d.rgb",f);fd2=$fopen(name,"wb");$sformat(name,"RTL_OSD_mask_f%0d.bin",f);fd3=$fopen(name,"wb");if(fd0==0 || fd1==0 || fd2==0 || fd3==0)$fatal(1,"capture open");
   for(yy=0;yy<720;yy++)begin
    for(xx=0;xx<1280;xx++)begin
     @(posedge clk);#0.03;x=xx;y=yy;de=1;hs=0;vs=0;
     if(f>=2 && f<=5)begin pos=((f-2)*921600+yy*1280+xx)*3;bg={photos[pos],photos[pos+1],photos[pos+2]};end
     else bg=f%2?24'h183149:24'hFFFFFF;
    end
    @(posedge clk);#0.03;de=0;hs=1;repeat(3)@(posedge clk);
   end
   @(posedge clk);#0.03;de=0;vs=1;repeat(12)@(posedge clk);@(negedge clk);$fclose(fd0);$fclose(fd1);$fclose(fd2);$fclose(fd3);fd0=-1;fd1=-1;fd2=-1;fd3=-1;frames++;
   $display("OSD_LAYOUT_FRAME_PASS frame=%0d kind=%0d remaining=%0d",f,original.hint_kind,original.hint_remaining);
  end
  // Keep the existing internal counters/state running, though their three
  // output strings are hidden. Real period settings and all priorities remain.
  reset=1;repeat(5)@(negedge clk);reset=0;frame_boundary();code=3;frame_boundary();
  if(dut.hint_remaining!=72)$fatal(1,"OSD_LAYOUT_REJECT hint initial duration");
  for(n=1;n<=72;n++)begin frame_boundary();if(dut.hint_remaining!=72-n)$fatal(1,"OSD_LAYOUT_REJECT hint duration");end
  idx=3;@(negedge clk);commit=1;@(negedge clk);commit=0;repeat(2)@(negedge clk);
  if(!dut.notice.visible || dut.notice.remaining!=72)$fatal(1,"OSD_LAYOUT_REJECT scene initial duration");
  for(n=1;n<=72;n++)begin frame_boundary();if(dut.notice.remaining!=72-n)$fatal(1,"OSD_LAYOUT_REJECT scene duration");end
  if(dut.notice.visible)$fatal(1,"OSD_LAYOUT_REJECT scene expiry");
  if(checked!=($test$plusargs("QUICK")?1:12)*921600)$fatal(1,"OSD_LAYOUT_REJECT coverage");
  $display("OSD_LAYOUT_CAPTURE_PASS frames=%0d pixels=%0d internal_72_frame_state_unchanged",frames,checked);$finish;
 end
 initial begin #1500000000;$fatal(1,"OSD_LAYOUT_REJECT timeout");end
endmodule

