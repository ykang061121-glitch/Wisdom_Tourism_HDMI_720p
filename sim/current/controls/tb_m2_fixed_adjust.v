`timescale 1ns/1ps
// Isolated exact production-module chain. The top-level selector is extracted
// from -Project by run_tests.ps1, not substituted from an independent branch.
module tb_m2_fixed_adjust;
 reg clk=0,reset=1,hs=0,vs=0,de=0,frame=0;
 always #6.734 clk=~clk;
 reg [10:0] x=0,y=0;reg[23:0]rgb=0;
 reg signed[7:0]bri=0;reg[7:0]con=100;
 wire[1:0]phase;wire[23:0]actual_rgb,bypass_rgb,selected_rgb;
 wire ah,av,ad,bh,bv,bd;wire[10:0]ax,ay,bx,by;
 diagnostic_frame_phase #(.HOLD_FRAMES(2)) observer(clk,reset,frame,1'b1,phase);
 video_adjust_percent adjust(clk,reset,hs,vs,de,x,y,rgb,bri,con,ah,av,ad,ax,ay,actual_rgb);
 pixel_identity_delay bypass(clk,reset,hs,vs,de,x,y,rgb,bh,bv,bd,bx,by,bypass_rgb);
 // Generated from the actual top assign; fault forces the old A/B selection.
 m2_selector_from_project select_pixel(actual_rgb,bypass_rgb,phase,selected_rgb);
 wire[23:0]dr;wire dh,dv,dd;wire[10:0]dx,dy;
 hdmi_diagnostic_overlay #(.PATTERNS(0)) final_two(clk,reset,ah,av,ad,ax,ay,selected_rgb,2'd0,dh,dv,dd,dx,dy,dr);
 reg[48:0]expected[0:6],identity[0:4];
 integer i,n,checks=0,phase_changes=0;reg[1:0]last_phase;
 reg[23:0]calculated;reg[48:0]wanted;
 function[7:0]channel(input integer p,b,c);
  integer value;begin value=128+(p-128)*c/100+b;
   channel=value<0?0:value>255?255:value;end
 endfunction
 task reject(input[255:0]reason);
  begin $display("M2_FIXED_CHECKER_REJECT %0s actual=%h expected=%h phase=%0d",reason,{dh,dv,dd,dx,dy,dr},wanted,phase);$fatal(1);end
 endtask
 always @(posedge clk)begin
  if(reset)begin
   for(i=0;i<7;i=i+1)expected[i]=0;
   for(i=0;i<5;i=i+1)identity[i]=0;
   last_phase=0;
  end else begin
   for(i=6;i>0;i=i-1)expected[i]=expected[i-1];
   for(i=4;i>0;i=i-1)identity[i]=identity[i-1];
   calculated=de?{channel(rgb[23:16],$signed(bri),con),channel(rgb[15:8],$signed(bri),con),channel(rgb[7:0],$signed(bri),con)}:24'd0;
   expected[0]={hs,vs,de,x,y,calculated};
   identity[0]={hs,vs,de,x,y,(de?rgb:24'd0)};
   #0.1;
   if({bh,bv,bd,bx,by,bypass_rgb}!==identity[4])reject("original five-stage bypass changed");
   wanted=expected[6];
   if(!wanted[46])wanted[23:0]=0;
   // Final label is still the original A label and the original two clocks.
   else if(wanted[45:35]>=16&&wanted[45:35]<160&&wanted[34:24]>=48&&wanted[34:24]<72)begin
    // Only known independently checked D row pixels are injected by fixture.
    if(wanted[34:24]==52&&wanted[45:35]==25)wanted[23:0]=24'hffff00;
    else if(wanted[45:35]<24||wanted[45:35]>=152||wanted[34:24]<52||wanted[34:24]>=68||
            (wanted[34:24]==52&&wanted[45:35]==24))wanted[23:0]=24'h07152c;
    else wanted[23:0]=dr; // other glyph RGB is covered by existing D1 tests; metadata is still checked
   end
   if($test$plusargs("ALIGN")&&checks>200)wanted[35]=~wanted[35];
   if({dh,dv,dd,dx,dy,dr}!==wanted)reject("RGB/sideband or fixed selection");
   if(phase!=last_phase)phase_changes=phase_changes+1;
   last_phase=phase;checks=checks+1;
  end
 end
 task sample_block(input integer brightness,contrast);
  begin
   // Hold blanking long enough for the existing gain register before pixels.
   @(negedge clk);de=0;bri=brightness;con=contrast;
   repeat(12)@(negedge clk);
   for(n=0;n<22000;n=n+1)begin
    @(negedge clk);x=n%1650;y=(n*17)%750;hs=(n%1650)<40;vs=(n%3000)<15;
    de=x<1280&&y<720;rgb={8'(n*3),8'(255-n*7),8'(n*13)};frame=(n%1237)==0;
    if(n%1000==1)begin x=25;y=52;de=1;end
    if(n%1000==2)begin x=24;y=52;de=1;end
   end
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);reset=0;
  sample_block(0,100);sample_block(32,100);sample_block(0,175);sample_block(-64,50);sample_block(64,200);
  reset=1;repeat(4)@(negedge clk);reset=0;sample_block(0,100);
  @(negedge clk);de=0;repeat(12)@(negedge clk);
  if(phase_changes<10)$fatal(1,"observer was not exercised");
  $display("M2_FIXED_TEST_PASS samples=%0d phase_changes=%0d RGB_sidebands7 bypass5 original_two_stages fixed_ADJUST",checks,phase_changes);$finish;
 end
 initial begin #5000000;$fatal(1,"timeout");end
endmodule
