`timescale 1ns/1ps
module tb_bmp_stream;
    reg clk=0,rst=1,cancel=0,start=0;
    always #5 clk=~clk;
    reg [15:0] w=1,h=3;
    reg [31:0] seed=32'h12678ABC;
    reg [7:0] sd_data=0;
    reg sd_valid=0,sd_end=0,ack=0;
    wire ready,sd_read,req,pv,row_last,done,error,frame_start;
    wire [31:0] sd_addr;
    wire [23:0] rgb;
    wire [7:0] error_code;
    reg pr=0;
    integer mode=0,byte_index=0,packet_addr=0,gap=0;
    integer pixels=0,dones=0,requests=0,n,x,y,stride,pos,field;
    reg active=0,held_valid=0;
    reg [23:0] held_pixel;
    bmp_read #(.TEST_ALLOW_SIZE(1), .SECTOR_TIMEOUT_CYCLES(4096)) dut (
        .clk(clk),.rst(rst),.cancel(cancel),.ready(ready),
        .scan_start(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd1),
        .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
        .load_start(start),.load_sector(32'd0),.sd_init_done(1'b1),.state_code(),
        .bmp_width(w),.bmp_height(h),.write_req(req),.write_req_ack(ack),
        .sd_sec_read(sd_read),.sd_sec_read_addr(sd_addr),.sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),
        .bmp_data_wr_en(pv),.bmp_data(rgb),.pixel_ready(pr),.pixel_row_last(row_last),
        .source_width(),.source_height(),.frame_start(frame_start),.source_done(done),
        .load_error(error),.error_code(error_code));
    function [23:0] color;
        input integer x,y;
        begin color={8'hA1+x[7:0],8'h53+y[7:0],8'h17+x[7:0]+y[7:0]};end
    endfunction
    function [7:0] bytes;
        input integer p;
        integer value,k,row,col;
        reg [23:0] c;
        begin
            bytes=0;value=0;
            case(p)
                0:bytes=mode==1?"X":"B";1:bytes="M";
                2,3,4,5:begin value=511+(((w*3+3)/4)*4)*h;if(mode==8)value=value-1;if(mode==16)value=-1;bytes=value>>((p-2)*8);end
                10,11,12,13:begin value=mode==9?53:mode==15?-16:511;bytes=value>>((p-10)*8);end
                14:bytes=mode==2?108:40;
                16:bytes=mode==19?1:0;
                18,19,20,21:begin value=w;if(mode==3)value=value+65536;if(mode==10)value=321;bytes=value>>((p-18)*8);end
                22,23,24,25:begin value=h;if(mode==4)value=-h;if(mode==14)value=value+65536;if(mode==21)value=0;bytes=value>>((p-22)*8);end
                26:bytes=mode==5?2:1;28:bytes=mode==6?16:24;30:bytes=mode==7?1:0;
                27:bytes=mode==17?1:0;29:bytes=mode==18?1:0;33:bytes=mode==20?1:0;
                default:if(p>=511)begin
                    k=p-511;row=k/(((w*3+3)/4)*4);col=(k%(((w*3+3)/4)*4))/3;
                    if(row<h && col<w)begin c=color(col,row);case(k%(((w*3+3)/4)*4)%3)0:bytes=c[7:0];1:bytes=c[15:8];2:bytes=c[23:16];endcase end
                    else bytes=8'hED; // padding must NEVER become a pixel
                end
            endcase
        end
    endfunction
    // Four-phase ACK model, with return low deliberately delayed.
    integer ack_delay=0;
    always @(posedge clk)begin
        if(rst)begin ack<=0;ack_delay<=0;end
        else if(req)begin ack_delay<=0;ack<=1;end
        else if(ack)begin if(ack_delay==7)ack<=0;else ack_delay<=ack_delay+1;end
    end
    always @(negedge clk)begin
        seed={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]};
        pr=seed[0] && seed[2];
    end
    always @(posedge clk)begin
        if(rst)begin active<=0;sd_valid<=0;sd_end<=0;end
        else begin
            sd_valid<=0;sd_end<=0;
            if(!active && sd_read && !sd_end)begin active<=1;byte_index=0;packet_addr=sd_addr;gap=13;requests=requests+1;end
            else if(active && mode!=12)begin
                if(gap>0)gap=gap-1;
                else if(byte_index==((mode==11 || (mode==22 && packet_addr>0))?510:mode==13?513:512))begin active<=0;sd_end<=1;end
                else begin sd_valid<=1;sd_data<=bytes(packet_addr*512+byte_index);byte_index=byte_index+1;gap=seed[4:3];end
            end
        end
        if(!rst && !cancel)begin
            if(held_valid && (!pv || rgb!==held_pixel))$fatal(1,"BMP pixel not held under backpressure");
            held_valid=pv&&!pr;held_pixel=rgb;
            if(pv && pr)begin
                if(ack||req)$fatal(1,"pixel before four-phase ACK finished");
                x=pixels%w;y=pixels/w;
                if(rgb!==color(x,y) || row_last!==(x==w-1))$fatal(1,"padding/BGR/row boundary error pixel=%0d RGB=%h",pixels,rgb);
                pixels=pixels+1;
            end
            if(done)begin if(pixels!=w*h)$fatal(1,"source_done before last accepted pixel/padding");dones=dones+1;end
        end else held_valid=0;
    end
    task reset_case;
        begin @(negedge clk);rst=1;repeat(4)@(negedge clk);pixels=0;dones=0;requests=0;rst=0;repeat(4)@(negedge clk);end
    endtask
    task begin_load;
        begin wait(ready);@(negedge clk);start=1;@(negedge clk);start=0;end
    endtask
    initial begin
        for(n=1;n<=3;n=n+1)begin
            w=n;mode=0;reset_case;begin_load;wait(dones==1);wait(ready);
            repeat(20)@(negedge clk);
            if(pixels!=w*h || dones!=1)$fatal(1,"padding fixture pixel count");
            $display("BMP_PADDING_%0d_PASS offset=511 pixels=%0d",n,pixels);
        end
        for(n=1;n<=22;n=n+1)begin
            mode=n;reset_case;begin_load;wait(error);@(negedge clk);
            if(req||pixels||dones)$fatal(1,"invalid BMP emitted data/request/done mode=%0d",mode);
            if(mode==12)begin
                repeat(20)@(negedge clk);if(ready)$fatal(1,"timeout started new CMD17 before old one drained");
            end else wait(ready);
            $display("BMP_INVALID_%0d_PASS error=%h",mode,error_code);
        end
        mode=0;w=3;reset_case;begin_load;wait(dut.sector_buffer.state==1);
        @(negedge clk);cancel=1;@(negedge clk);cancel=0;wait(ready);
        if(pixels||dones)$fatal(1,"cancel FETCH emitted pixels");
        for(n=1;n<=4;n=n+1)begin
            reset_case;begin_load;
            wait(dut.decoder.state==n);
            @(negedge clk);cancel=1;@(negedge clk);cancel=0;wait(ready);
            if(dones)$fatal(1,"cancel decoder generated EOF");
        end
        reset_case;begin_load;wait(pv);@(negedge clk);rst=1;repeat(4)@(negedge clk);
        pixels=0;dones=0;rst=0;repeat(4)@(negedge clk);begin_load;wait(dones==1);
        $display("BMP_STREAM_TEST_PASS padding/cross-sector/errors/cancel/reset");$finish;
    end
    initial begin #5000000;$fatal(1,"BMP_STREAM_TIMEOUT");end
endmodule
