`timescale 1ns/1ps
module tb_bmp720_errors;
 reg clk=0,rst=1,cancel=0,start=0;always #5 clk=~clk;
 wire ready,req,rd,pv,done,err;wire[7:0]code;wire[31:0]sector;wire[23:0]pixel;
 wire[10:0]w,h;reg ack=0;reg[7:0]sd_data=0;reg sd_valid=0,sd_end=0;
 reg[7:0]header[0:511];integer f,n,mode=0,st=0,pos=0,ticks=0,errors=0,requests=0,pixels=0;
 string file;reg seen_error=0;reg[7:0]saved_error;reg accepted_request=0;
 bmp_read #(.ALLOW_720P(1),.GENERIC_SIZE(1),.SECTOR_TIMEOUT_CYCLES(4096)) dut(.clk(clk),.rst(rst),.cancel(cancel),.ready(ready),
  .scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd21603),.scan_target_count(3'd4),
  .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),.load_start(start),.load_sector(32'd0),
  .sd_init_done(1'b1),.state_code(),.bmp_width(16'd1280),.bmp_height(16'd720),.write_req(req),.write_req_ack(ack),
  .sd_sec_read(rd),.sd_sec_read_addr(sector),.sd_sec_read_data(sd_data),.sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
  .bmp_data_wr_en(pv),.bmp_data(pixel),.pixel_ready(1'b1),.pixel_row_last(),.source_width(w),.source_height(h),
  .frame_start(),.source_done(done),.load_error(err),.error_code(code));
 always @(posedge clk)begin
  if(rst)begin ack<=0;seen_error=0;accepted_request=0;pixels=0;end
  else begin
   ack<=req;
   if(req)accepted_request=1;
   if(pv)pixels=pixels+1;
   if(done)$fatal(1,"BMP720_ERROR_CHECKER_REJECT incomplete input reported source_done");
   if(err)begin seen_error=1;saved_error=code;end
  end
 end
 always @(negedge clk)begin
  sd_valid=0;sd_end=0;
  if(rst)begin st=0;ticks=0;end
  else case(st)
   0:if(rd)begin pos=0;st=1;ticks=0;requests=requests+1;end
   1:begin
    ticks=ticks+1;
    if(mode==11)begin if(ticks==4200)begin sd_end=1;st=3;end end
    else begin
     sd_valid=1;sd_data=(sector==0)?header[pos]:8'h72;pos=pos+1;
     if(pos==((mode==12&&sector==1)?17:512))st=2;
    end
   end
   2:begin sd_end=1;st=3;end
   3:if(!rd)st=0;
  endcase
 end
 task load_header;
  begin f=$fopen(file,"rb");if(!f)$fatal(1,"header fixture missing");n=$fread(header,f);$fclose(f);if(n!=512)$fatal(1,"header fixture short");end
 endtask
 task bad_case(input integer m,input[7:0]expected_code);
  begin
   rst=1;repeat(3)@(negedge clk);load_header;mode=m;
   case(m)
    0:header[0]="X";
    1:begin header[18]=8'h81;header[19]=7;end // unsupported 1921
    2:header[21]=1; // upper 32-bit width is not ignored
    3:begin header[22]=8'h30;header[23]=8'hfd;header[24]=8'hff;header[25]=8'hff;end
    4:header[26]=2;
    5:header[28]=32;
    6:header[30]=1;
    7:header[14]=108;
    8:header[10]=53;
    9:begin header[2]=54;header[3]=0;header[4]=0;header[5]=0;end
    10:begin header[2]=255;header[3]=255;header[4]=255;header[5]=255;end
    14:begin header[18]=15;header[19]=0;end
    15:begin header[18]=0;header[19]=8;end // 2048: do not truncate to 11 bits
    16:begin header[22]=8'h81;header[23]=7;end // 1921: new upper height boundary
    17:begin header[22]=0;header[23]=0;end
    18:begin header[18]=0;header[19]=0;end
    19:begin header[18]=255;header[19]=255;header[20]=255;header[21]=255;end
    20:begin header[10]=255;header[11]=255;header[12]=255;header[13]=255;end
    default:;
   endcase
   rst=0;wait(ready);@(negedge clk);start=1;@(negedge clk);start=0;
   wait(seen_error);if(saved_error!==expected_code)$fatal(1,"BMP720_ERROR_CHECKER_REJECT m%0d code%h exp%h",m,saved_error,expected_code);
   if((m<=10 || m>=14) && (accepted_request||pixels))$fatal(1,"BMP720_ERROR_CHECKER_REJECT invalid header wrote pixels");
   repeat(4500)@(negedge clk);if(!ready)$fatal(1,"BMP720_ERROR_CHECKER_REJECT failed to drain/recover");
   $display("BMP720_REJECTION_PASS case=%0d error=%h pixels_before_failure=%0d",m,saved_error,pixels);errors=errors+1;
  end
 endtask
 initial begin
  if(!$value$plusargs("RAW=%s",file))$fatal(1,"RAW path missing");
  bad_case(0,8'hE0);bad_case(1,8'hE1);bad_case(2,8'hE1);bad_case(3,8'hE1);
  bad_case(4,8'hE0);bad_case(5,8'hE0);bad_case(6,8'hE0);bad_case(7,8'hE0);
  bad_case(8,8'hE2);bad_case(9,8'hE2);bad_case(10,8'hE2);
  bad_case(11,8'hE3);bad_case(12,8'hE3);
  bad_case(14,8'hE1);bad_case(15,8'hE1);bad_case(16,8'hE1);
  bad_case(17,8'hE1);bad_case(18,8'hE1);bad_case(19,8'hE1);bad_case(20,8'hE2);
  // A valid header may begin, but cancel must suppress further data/completion.
  rst=1;repeat(3)@(negedge clk);load_header;mode=13;rst=0;wait(ready);
  @(negedge clk);start=1;@(negedge clk);start=0;wait(pv);@(negedge clk);cancel=1;
  repeat(4)@(negedge clk);cancel=0;repeat(4200)@(negedge clk);
  if(!ready||pv||done)$fatal(1,"BMP720_ERROR_CHECKER_REJECT cancel recovery");
  $display("BMP720_ERRORS_TEST_PASS rejected=%0d cancel_and_drain_recovered",errors);$finish;
 end
 initial begin #10000000;$fatal(1,"BMP720_ERROR_CHECKER_REJECT timeout");end
endmodule
