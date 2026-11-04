`timescale 1ns/1ps
module tb_adjust_keys_v2;
 reg clk=0,reset=1,k3=1,k4=1;always #5 clk=~clk;
 reg[1:0]sw=0;wire e3,e4,mode,target,fast;wire signed[7:0]bri;wire[7:0]con;wire[1:0]preset;
 adjustment_key_control #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(2),.CHORD_MS(50))dut(
  .clk(clk),.reset(reset),.key3_n(k3),.key4_n(k4),.switches_async(sw),
  .normal_key3(e3),.normal_key4(e4),.adjust_mode(mode),.brightness(bri),.contrast(con),
  .preset_mode(preset),.target_contrast(target),.fast_step(fast));
 integer n3=0,n4=0,b,c,old,expect_value,checks=0;
 always @(posedge clk)if(!reset)begin if(e3)n3=n3+1;if(e4)n4=n4+1;end
 task waitn;input integer n;begin repeat(n)@(negedge clk);end endtask
 task check;input integer eb,ec;
  begin checks=checks+1;if($signed(bri)!=eb || con!=ec)begin
    $display("ADJUST_KEYS_CHECKER_REJECT BRI=%0d expected=%0d CON=%0d expected=%0d",$signed(bri),eb,con,ec);$fatal(1);end end
 endtask
 task switches;input[1:0]s;begin sw=s;waitn(15);end endtask
 task tap;input integer plus;begin if(plus)k3=0;else k4=0;waitn(12);k3=1;k4=1;waitn(12);end endtask
 task chord;input integer reverse_release;
  begin k3=0;waitn(1);k4=0;waitn(90);
   if(reverse_release)k4=1;else k3=1;waitn(12);
   if(reverse_release)k3=1;else k4=1;waitn(12);end
 endtask
 initial begin
  waitn(4);reset=0;waitn(15);check(0,100);
  k3=0;waitn(1);k3=1;waitn(12);if(n3||n4)$fatal(1,"short glitch");
  tap(1);tap(0);if(n3!=1||n4!=1)$fatal(1,"normal events");
  // Two interrupted holds must NOT accumulate into the long chord.
  k3=0;k4=0;
  if($test$plusargs("FAULT_KEY"))force dut.normal_key4=1;
  waitn(38);k3=1;waitn(20);k3=0;
  if($test$plusargs("FAULT_CHORD"))force dut.chord_count=49;
  waitn(38);
  if(mode)begin $display("ADJUST_KEYS_CHECKER_REJECT interrupted chord accumulated time");$fatal(1);end
  k4=1;waitn(12);k3=1;waitn(15);
  if(mode||n3!=1||n4!=1)begin $display("ADJUST_KEYS_CHECKER_REJECT short chord leaked ordinary key");$fatal(1);end
  chord(0);if(!mode||n3!=1||n4!=1)$fatal(1,"chord conflict");
  switches(2);for(b=16;b<=64;b=b+16)begin tap(1);check(b,100);end
  if($test$plusargs("FAULT"))force dut.brightness=63;
  tap(1);check(64,100);
  for(b=48;b>= -64;b=b-16)begin tap(0);check(b,100);end
  tap(0);check(-64,100);
  switches(0);for(b=-63;b<=64;b=b+1)begin tap(1);check(b,100);end
  // At every fine starting value, both step sizes are reversible if valid.
  for(b=64;b>= -64;b=b-1)begin
   switches(2);tap(1);expect_value=b+16<=64?b+16:b;check(expect_value,100);
   if(b+16<=64)begin tap(0);check(b,100);end
   tap(0);expect_value=b-16>= -64?b-16:b;check(expect_value,100);
   if(b-16>= -64)begin tap(1);check(b,100);end
   switches(0);if(b> -64)tap(0);
  end
  for(b=-63;b<=17;b=b+1)tap(1);check(17,100);
  switches(3);tap(0);tap(0);check(17,50);tap(0);check(17,50);
  switches(1);for(c=55;c<=200;c=c+5)begin tap(1);check(17,c);end
  tap(1);check(17,200);
  for(c=200;c>=50;c=c-5)begin
   switches(3);tap(1);expect_value=c+25<=200?c+25:c;check(17,expect_value);
   if(c+25<=200)begin tap(0);check(17,c);end
   tap(0);expect_value=c-25>=50?c-25:c;check(17,expect_value);
   if(c-25>=50)begin tap(1);check(17,c);end
   switches(1);if(c>50)tap(0);
  end
  for(c=55;c<=125;c=c+5)tap(1);check(17,125);
  switches(3);chord(1);if(mode||preset!=0||n3!=1||n4!=1)$fatal(1,"exit chord conflict");
  waitn(50);check(17,125);if(preset!=0)$fatal(1,"exit switch unexpectedly selects preset");
  switches(2);check(33,125);if(preset!=2)$fatal(1,"base bright");
  switches(1);check(-15,100);if(preset!=1)$fatal(1,"base soft offset");
  chord(1);chord(0);if(mode||n3!=1||n4!=1)$fatal(1,"chord repetition");
  reset=1;waitn(4);sw=0;reset=0;waitn(20);check(0,100);
  $display("ADJUST_KEYS_V2_TEST_PASS checks=%0d all129brightness all31contrast reject_overstep preserve_offsets chord_release",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
