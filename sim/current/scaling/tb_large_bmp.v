`timescale 1ns/1ps
module tb_large_bmp;
 parameter MODE=0;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,cancel=0,start=0,ack=0;
 wire ready,req,rd,pv,source_done,scale_done,err,frame_start;
 wire [7:0]code;wire [31:0]sector;wire [23:0]pixel,out_rgb;
 wire [10:0]w,h,ox,orow;wire pr,ov,scaler_busy;
 reg [7:0] sd_data=0;reg sd_valid=0,sd_end=0,out_ready=0;
 integer f,st=0,pos=0,seed=7627,latency,packet_count=0;
 integer sw,sh,lba,sectors,offset,inputs,outputs,eofs,scales,cycles,cases=0;
 integer expected_sector,px,py,sx,sy,cw,ch,left,top;
 reg armed=0,seen_error=0;reg [23:0]expected;
 reg memory_done=0;integer memory_wait=0,memories=0,ready_count=0;
 wire guarded_ready,guard_source,guard_scale,guard_memory;
 string file;
 reg[7:0]reference_bytes[0:11060223];
 integer ref_file,ref_count;
 reg inject_bad_pixel;
 bmp_read #(.ALLOW_720P(1),.GENERIC_SIZE(1),.SECTOR_TIMEOUT_CYCLES(4096)) parser(
 .clk(clk),.rst(rst),.cancel(cancel),.ready(ready),
 .scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd131071),.scan_target_count(3'd4),
 .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
 .load_start(start),.load_sector(lba),.sd_init_done(1'b1),.state_code(),
 .bmp_width(16'd0),.bmp_height(16'd0),.write_req(req),.write_req_ack(ack),
 .sd_sec_read(rd),.sd_sec_read_addr(sector),.sd_sec_read_data(sd_data),
 .sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
 .bmp_data_wr_en(pv),.bmp_data(pixel),.pixel_ready(pr),.pixel_row_last(),
 .source_width(w),.source_height(h),.frame_start(frame_start),.source_done(source_done),
 .load_error(err),.error_code(code));
 image_scaler_generic #(.MODE(MODE)) scaler(
 .clk(clk),.reset(rst),.cancel(cancel|err),.start(frame_start),.source_width(w),.source_height(h),
 .in_rgb(pixel),.in_valid(pv),.in_ready(pr),.out_rgb(out_rgb),.out_valid(ov),.out_ready(out_ready),
 .out_x(ox),.out_row(orow),.scale_done(scale_done),.busy(scaler_busy));
 // Controlled completion event only, not an SDRAM timing model. For FILL the
 // selected region can finish before the cropped source tail has drained.
 frame_completion_guard guard(.clk(clk),.reset(rst),.start(start),.cancel(cancel|err),
 .memory_arm(frame_start),.source_done(source_done),.scale_done(scale_done),
 .memory_done(memory_done),.source_seen(guard_source),.scale_seen(guard_scale),
 .memory_seen(guard_memory),.ready_pulse(guarded_ready));
 function [23:0] pattern;
 input integer a,b;
 integer p;
 begin
   p=offset+(sh-1-b)*((sw*3+3)&~3)+a*3;
   pattern={reference_bytes[p+2],reference_bytes[p+1],reference_bytes[p]};
 end
 endfunction
 task fail(input [511:0]reason);
 begin $display("GENERIC_BMP_CHECKER_REJECT %0s source=%0dx%0d mode=%0d inputs=%0d outputs=%0d coord=%0d,%0d source_coord=%0d,%0d data=%h expected=%h error=%h state=%0d",reason,sw,sh,MODE,inputs,outputs,ox,orow,sx,sy,out_rgb,expected,code,parser.state);$fatal(1);end
 endtask
 always @(negedge clk)begin
 sd_valid=0;sd_end=0;
 if(rst)begin st=0;ack=0;end
 else begin
   ack=req; // ACK still passes through production two-FF/four-phase logic.
   out_ready=armed && (cycles%701<600) && (($random(seed)&3)!=0);
   case(st)
    0:if(rd)begin
      if(sector!=expected_sector)fail("sector request sequence");
      if(packet_count==0)expected_sector=lba;
      else expected_sector=expected_sector+1;
      packet_count=packet_count+1;
      if($fseek(f,sector*512,0)!=0)fail("fixture seek");
      pos=0;latency=7+($random(seed)&31);st=1;
    end
    1:if(latency==0)st=2;else latency=latency-1;
    2:if(($random(seed)&7)!=0)begin
      sd_data=$fgetc(f);sd_valid=1;pos=pos+1;if(pos==512)st=3;
    end
    3:begin sd_end=1;st=4;end
    4:if(!rd)st=0;
   endcase
 end
 end
 always @(posedge clk)if(armed && !rst && !cancel)begin
 memory_done<=0;
 cycles=cycles+1;
 if(cycles>40000000)fail("timeout");
 if(err)fail("valid BMP rejected");
 if(pv&&pr)begin
    expected=pattern(inputs%sw,sh-1-inputs/sw);
    if(pixel!==expected)fail("BGR/padding/source mapping");
    inputs=inputs+1;
 end
 if(source_done)begin if(inputs!=sw*sh)fail("source EOF count");eofs=eofs+1;end
 if(ov&&out_ready)begin
    px=outputs%1280;py=719-outputs/1280;
    if(ox!==px || orow!==(outputs/1280))fail("output coordinate");
    sx=-1;sy=-1;
    if(MODE==2)begin sx=(2*px+1)*sw/2560;sy=(2*py+1)*sh/1440;end
    else if(MODE==1)begin
      if(sw*720>=sh*1280)begin sx=(sw*720+(2*px+1-1280)*sh)/1440;sy=(2*py+1)*sh/1440;end
      else begin sx=(2*px+1)*sw/2560;sy=(sh*1280+(2*py+1-720)*sw)/2560;end
    end else begin
      if(sw*720>=sh*1280)begin cw=1280;ch=sh*1280/sw;end else begin cw=sw*720/sh;ch=720;end
      left=(1280-cw)/2;top=(720-ch)/2;
      if(px>=left && px<left+cw && py>=top && py<top+ch)begin sx=(2*(px-left)+1)*sw/(2*cw);sy=(2*(py-top)+1)*sh/(2*ch);end
    end
    expected=sx<0?0:pattern(sx,sy);
    if(inject_bad_pixel && outputs==731)force scaler.ram_q=24'hbadbad;
    if(out_rgb!==expected)fail("scaled pixel mathematical oracle");
    outputs=outputs+1;
 end
 if(scale_done)begin if(outputs!=921600)fail("scale done count");scales=scales+1;memory_wait=7;end
 if(memory_wait>0)begin
   memory_wait=memory_wait-1;
   if(memory_wait==0)begin memory_done<=1;memories=memories+1;end
 end
 if(guarded_ready)begin
   if(eofs!=1 || scales!=1 || memories!=1 || !guard_source || !guard_scale || !guard_memory)
      fail("three-completion guard early/stale ready");
   ready_count=ready_count+1;
 end
 end
 task fixture(input integer fw,fh,flba,fsectors,foffset);
 begin
    @(negedge clk);rst=1;armed=0;
    repeat(3)@(negedge clk);
    sw=fw;sh=fh;lba=flba;sectors=fsectors;offset=foffset;
    if($fseek(ref_file,lba*512,0)!=0)fail("independent reference seek");
    ref_count=$fread(reference_bytes,ref_file,0,sectors*512);
    if(ref_count!=sectors*512)fail("independent file actually truncated");
    inputs=0;outputs=0;eofs=0;scales=0;cycles=0;packet_count=0;expected_sector=lba;
    memory_wait=0;memories=0;ready_count=0;memory_done=0;
    rst=0;wait(ready);@(negedge clk);armed=1;start=1;
    @(negedge clk);start=0;
    wait(eofs==1 && scales==1 && !scaler_busy && ready && ready_count==1);
    repeat(5)@(negedge clk);armed=0;
    if(inputs!=sw*sh || outputs!=921600 || packet_count!=1+sectors || ready_count!=1)
      fail("transaction totals / trailing sector / guard");
    cases=cases+1;
    $display("GENERIC_BMP_FULL_PASS mode=%0d source=%0dx%0d offset=%0d padding=%0d sectors=%0d output=%0d EOF=%0d",MODE,sw,sh,offset,sw%4,packet_count,outputs,eofs);
 end
 endtask
 initial begin
   inject_bad_pixel=$test$plusargs("BAD_PIXEL");
   if(!$value$plusargs("RAW=%s",file))$fatal(1,"fixture RAW missing");
   f=$fopen(file,"rb");if(!f)$fatal(1,"cannot open RAW");
   ref_file=$fopen(file,"rb");if(!ref_file)$fatal(1,"cannot open independent RAW reference");
   repeat(4)@(negedge clk);
   `include "cases.vh"
   $fclose(f);
   $display("GENERIC_BMP_TEST_PASS mode=%0d full_frames=%0d output_pixels=%0d",MODE,cases,cases*921600);$finish;
 end
endmodule
