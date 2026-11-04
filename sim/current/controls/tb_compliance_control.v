`timescale 1ns/1ps
module tb_compliance_control;
 parameter PHASE=0;
 reg sclk=0,vclk=0,rst=1,frame=0,k3=1,k4=1;
 always #5 sclk=~sclk;
 initial begin #(PHASE);forever #6.734 vclk=~vclk;end
 reg [3:0]sw=0;
 reg [43:0]meta=0;reg[1:0]sid=0,vid=0;
 wire signed[7:0]pb,bri;wire[1:0]pc,preset,interval,locked_preset;wire[7:0]con;
 wire[11:0]bri_digits,con_digits;
 wire p3,p4,mode,target,fast,mv;
 wire[63:0]bcd;wire[3:0]sw_active;
 reg auto_mode=0;integer n3=0,n4=0,frames=0,transfers=0;
 reg [109:0]last_outputs;reg permit,primed=0;
 presentation_control #(.STABLE_CYCLES(16)) presets(.video_clk(vclk),.reset(rst),
 .frame_boundary(frame),.switches_async(sw),.switches_active(sw_active),.preset_mode(preset),
 .brightness(pb),.contrast(pc),.subtitles_visible(),.wave_visible());
 compliance_control_bridge #(.CLK_FREQ_HZ(1000)) dut(.sd_clk(sclk),.video_clk(vclk),
 .reset(rst),.frame_boundary(frame),.key3_n(k3),.key4_n(k4),.switches_async(sw[1:0]),
 .scaling_meta_sd(meta),.image_sd(sid),.image_video(vid),.preset_brightness(pb),.preset_contrast(pc),
 .normal_key3(p3),.normal_key4(p4),.brightness(bri),.contrast(con),.adjust_mode(mode),
 .preset_mode(locked_preset),.brightness_digits(bri_digits),.contrast_digits(con_digits),
 .target_contrast(target),.fast_step(fast),.meta_valid(mv),.meta_bcd(bcd));
 playback_interval_control #(.CLK_FREQ_HZ(1000),.EXTERNAL_EVENTS(1)) timer(
 .clk(sclk),.reset(rst),.key_interval(1'b1),.key_event(p3),
 .timer_enable(auto_mode),.timer_restart(p4),.interval_code(interval),.interval_press(),
 .auto_tick(),.progress_running(),.progress_units());
 always @(posedge sclk)if(rst)auto_mode<=0;else begin
 if(p3)n3=n3+1;if(p4)begin n4=n4+1;auto_mode<=~auto_mode;end
 end
 task fail(input[511:0]reason);
 begin $display("COMPLIANCE_CONTROL_CHECKER_REJECT %0s phase=%0d mode=%b bri=%0d con=%0d meta=%h valid=%b",reason,PHASE,mode,bri,con,bcd,mv);$fatal(1);end
 endtask
 task check(input bit ok,input[511:0]reason);if(!ok)fail(reason);endtask
 always @(posedge vclk)begin
 permit=dut.apply_pending;
 #0.001;
 if(!rst && primed && {mode,target,fast,bri,con,mv,bcd,locked_preset,bri_digits,con_digits}!==last_outputs && !permit)
     fail("parameters changed outside blanking apply");
 last_outputs={mode,target,fast,bri,con,mv,bcd,locked_preset,bri_digits,con_digits};primed=!rst;
 end
 task tick(input integer n);repeat(n)@(negedge sclk);endtask
 task boundary;
 begin
 tick(60);@(negedge vclk);frame=1;@(negedge vclk);frame=0;
 repeat(8)@(negedge vclk);frames=frames+1;
 end
 endtask
 task single(input integer key);
 begin if(key==3)k3=0;else k4=0;tick(40);k3=1;k4=1;tick(40);boundary;end
 endtask
 task chord;
 begin k3=0;tick(7);k4=0;tick(1100);k3=1;tick(9);k4=1;tick(50);boundary;end
 endtask
 function[15:0] decimal(input integer v);
 begin decimal={(4'((v/1000)%10)),(4'((v/100)%10)),(4'((v/10)%10)),(4'(v%10))};end
 endfunction
 task metadata(input integer id,w,h,cw,ch,input bit video_first);
 reg[63:0]expected;
 begin
 expected={decimal(w),decimal(h),decimal(cw),decimal(ch)};
 if(video_first)begin vid=id;boundary;check(!mv,"stale identity should hide metadata");end
 @(negedge sclk);sid=id;meta={11'(w),11'(h),11'(cw),11'(ch)};
 boundary;
 if(!video_first)begin check(!mv,"source-leading identity must not mislabel old picture");vid=id;boundary;end
 check(mv&&bcd===expected,"coherent BCD dimensions/content ratio");transfers=transfers+1;
 end
 endtask
 initial begin
 tick(5);rst=0;boundary;check(!mode&&bri==0&&con==100&&!mv,"startup defaults");
 meta={11'd640,11'd480,11'd960,11'd720};boundary;
 check(mv&&bcd==64'h0640048009600720,"first committed scene dimensions");
 single(3);check(interval==3&&n3==1,"normal K3 still 5->10 seconds");
 single(4);check(auto_mode&&n4==1,"normal K4 toggles AUTO");
 chord;check(mode&&interval==3&&auto_mode&&n3==1&&n4==1,"entry chord not ordinary keys");
 single(3);check(bri==1&&con==100,"fine positive brightness");
 sw=2;tick(50);boundary;single(3);check(bri==17,"coarse brightness");
 sw=1;tick(50);boundary;single(3);check(con==105&&bri==17,"contrast selected separately");
 sw=3;tick(50);boundary;single(3);check(con==130,"coarse contrast exact 25 percent");
 single(4);check(con==105&&auto_mode&&n4==1,"ADJ minus is not AUTO toggle");
 check(bri_digits==12'h017 && con_digits==12'h105,"BCD matches actual applied values");
 metadata(1,853,480,1279,720,1);
 metadata(2,479,801,430,720,0);
 metadata(3,1280,1024,900,720,1);
 metadata(0,17,31,394,720,0);
 if($test$plusargs("TORN"))begin
     force dut.mailbox.dst_data_sync1[84:53]=32'h12345678;
     sw=1;tick(50);boundary;boundary;
     check(bcd===64'h0017003103940720,"coherent BCD dimensions/content ratio");
     fail("fault injection escaped checker");
 end
 chord;check(!mode&&n3==1&&n4==1&&interval==3&&auto_mode,"exit chord not normal events");
 check(bri==17&&con==105&&locked_preset==0,"exit retains both adjustments and latched base");
 sw=1;tick(50);boundary;check(bri==-15&&con==80,"normal explicit SOFT plus retained manual offsets");
 single(3);check(interval==1,"normal K3 10->3 after exit");
 single(4);check(!auto_mode,"normal K4 works after exit");
 rst=1;meta=0;sid=0;vid=0;k3=1;k4=1;tick(5);rst=0;boundary;
 check(!mode&&!mv,"reset clears UI/metadata epoch");
 $display("COMPLIANCE_CONTROL_TEST_PASS phase=%0d coherent_transfers=%0d boundaries=%0d normal_events=%0d/%0d",PHASE,transfers,frames,n3,n4);$finish;
 end
endmodule
