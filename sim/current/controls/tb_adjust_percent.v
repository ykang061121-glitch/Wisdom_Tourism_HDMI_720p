`timescale 1ns/1ps
module tb_adjust_percent;
 reg clk=0,reset=1,hs=0,vs=0,de=0;always #6.734 clk=~clk;
 reg[10:0]x=0,y=0;reg[23:0]rgb=0;reg signed[7:0]bri=0;reg[7:0]con=100;
 wire oh,ov,od;wire[10:0]ox,oy;wire[23:0]out;
 video_adjust_percent dut(clk,reset,hs,vs,de,x,y,rgb,bri,con,oh,ov,od,ox,oy,out);
 reg[48:0]expected[0:4];integer n,c,b,v,k,checked=0,inject=0;reg[23:0]ref_rgb;
 function[7:0]math_ref;
  input integer pixel,brightness,contrast;
  integer value;
  begin value=128+((pixel-128)*contrast)/100+brightness;
   math_ref=value<0?0:value>255?255:value;end
 endfunction
 always @(posedge clk)begin
  if(reset)begin for(k=0;k<5;k=k+1)expected[k]=0;end
  else begin
   for(k=4;k>0;k=k-1)expected[k]=expected[k-1];
   ref_rgb=de?{math_ref(rgb[23:16],$signed(bri),con),math_ref(rgb[15:8],$signed(bri),con),math_ref(rgb[7:0],$signed(bri),con)}:24'd0;
   expected[0]={hs,vs,de,x,y,ref_rgb};
   #1;
   if({oh,ov,od,ox,oy,out}!==expected[4])begin
    $display("ADJUST_PERCENT_CHECKER_REJECT sample=%0d actual=%h expected=%h",checked,{oh,ov,od,ox,oy,out},expected[4]);$fatal(1);
   end
   checked=checked+1;
  end
 end
 initial begin
  inject=$test$plusargs("FAULT");repeat(4)@(negedge clk);reset=0;
  for(c=50;c<=200;c=c+5)for(b=-64;b<=64;b=b+1)for(v=0;v<256;v=v+1)begin
   @(negedge clk);con=c;bri=b;rgb={8'(v),8'(255-v),8'((v*37+c)&255)};
   x=(v*7+c)%1650;y=(v*3+c)%750;de=(v%17)!=0;hs=v[0];vs=v[2];
   if(inject && checked==200)force dut.quotient[0]=9'd255;
  end
  repeat(8)@(negedge clk);
  reset=1;repeat(4)@(negedge clk);reset=0;con=100;bri=0;de=1;rgb=24'h0080FF;
  repeat(12)@(negedge clk);
  $display("ADJUST_PERCENT_TEST_PASS input_cases=1023744 checked=%0d full31contrast full129brightness RGB sides5",checked);$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
