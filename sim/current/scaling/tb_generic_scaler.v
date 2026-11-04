`timescale 1ns/1ps
module tb_generic_scaler;
    parameter MODE=0;
    reg clk=0;always #5 clk=~clk;
    reg reset=1,cancel=0,start=0;
    reg [10:0] w=16,h=16;
    reg [23:0] in_rgb;
    reg in_valid=0,out_ready=0;
    wire in_ready,out_valid,done,busy;
    wire [23:0] rgb;
    wire [10:0] x,row;
    integer sw,sh,send_count,recv_count,done_count,seed=139,rounds=0;
    integer ox,oy,sx,sy,cw,ch,l,t,num,cycles,held=0;
    reg [23:0] expected,held_rgb;
    reg [10:0] held_x,held_row;
    reg armed=0,negative;
    image_scaler_generic #(.MODE(MODE)) dut(
        .clk(clk),.reset(reset),.cancel(cancel),.start(start),
        .source_width(w),.source_height(h),.in_rgb(in_rgb),.in_valid(in_valid),
        .in_ready(in_ready),.out_rgb(rgb),.out_valid(out_valid),.out_ready(out_ready),
        .out_x(x),.out_row(row),.scale_done(done),.busy(busy));
    function [23:0] pattern;
        input integer a,b;
        begin pattern={8'((a*7+b*3)&255),8'((a*13+b*11)&255),8'((((a/7)^(b/5))&1)?240:16)};end
    endfunction
    task fail;
        input [511:0] why;
        begin $display("GENERIC_SCALER_CHECKER_REJECT %0s mode=%0d W=%0d H=%0d count=%0d x=%0d row=%0d sx=%0d sy=%0d got=%h expected=%h",why,MODE,sw,sh,recv_count,x,row,sx,sy,rgb,expected);$fatal(1);end
    endtask
    always @(negedge clk)begin
        if(armed)begin
            in_valid=(send_count<sw*sh) && (($random(seed)&7)!=0);
            in_rgb=pattern(send_count%sw,sh-1-send_count/sw);
            // Include long repeated output stalls, not just single-cycle noise.
            out_ready=(cycles%501<430) && (($random(seed)&3)!=0);
        end else begin in_valid=0;out_ready=0;end
    end
    always @(posedge clk)if(armed && !reset && !cancel)begin
        cycles=cycles+1;
        // Large sources legitimately consume more input cycles. Still finite,
        // bounded by source area plus the unchanged sink stall schedule.
        if(cycles>7000000 && cycles>2*sw*sh+6*921600+10000)fail("timeout/deadlock");
        if(in_ready && in_valid)send_count=send_count+1;
        if(held)begin
            if(!out_valid || rgb!==held_rgb || x!==held_x || row!==held_row)fail("stalled payload changed");
        end
        held=out_valid&&!out_ready;held_rgb=rgb;held_x=x;held_row=row;
        if(out_valid && out_ready)begin
            ox=recv_count%1280;oy=719-recv_count/1280;
            if(x!==ox || row!==(recv_count/1280))fail("output coordinate/count");
            if(dut.sx>=sw && dut.content)fail("RAM address bounds");
            sx=-1;sy=-1;
            if(MODE==2)begin sx=(2*ox+1)*sw/2560;sy=(2*oy+1)*sh/1440;end
            else if(MODE==1)begin
                if(sw*720>=sh*1280)begin
                    sx=(sw*720+(2*ox+1-1280)*sh)/1440;
                    sy=(2*oy+1)*sh/1440;
                end else begin
                    sx=(2*ox+1)*sw/2560;
                    sy=(sh*1280+(2*oy+1-720)*sw)/2560;
                end
            end else begin
                if(sw*720>=sh*1280)begin cw=1280;ch=sh*1280/sw;end
                else begin cw=sw*720/sh;ch=720;end
                l=(1280-cw)/2;t=(720-ch)/2;
                if(ox>=l && ox<l+cw && oy>=t && oy<t+ch)begin
                    sx=(2*(ox-l)+1)*sw/(2*cw);
                    sy=(2*(oy-t)+1)*sh/(2*ch);
                end
            end
            expected=(sx<0)?0:pattern(sx,sy);
            if(negative && recv_count==731)expected=expected^24'h010000;
            if(rgb!==expected)fail("mathematical pixel mismatch");
            recv_count=recv_count+1;
            if(recv_count>921600)fail("too many pixels");
        end
        if(done)begin
            if(recv_count!=921600)fail("scale_done before last accepted output");
            done_count=done_count+1;
        end
    end
    task frame;
        input integer fw,fh;
        begin
            @(negedge clk);sw=fw;sh=fh;w=fw;h=fh;send_count=0;recv_count=0;done_count=0;cycles=0;held=0;
            start=1;armed=1;
            @(negedge clk);start=0;
            wait(busy);wait(!busy);repeat(2)@(negedge clk);
            @(negedge clk);armed=0;
            if(send_count!=sw*sh || recv_count!=921600 || done_count!=1)fail("exact EOF/drain/output count");
            rounds=rounds+1;
            $display("GENERIC_FULL_FRAME_PASS mode=%0d source=%0dx%0d input=%0d output=%0d cycles=%0d",MODE,sw,sh,send_count,recv_count,cycles);
        end
    endtask
    initial begin
        negative=$test$plusargs("BAD_PIXEL");
        repeat(5)@(negedge clk);reset=0;
        // Historic sizes plus odd-width padding, portrait, 16:10 and bounds.
        frame(320,240);frame(640,480);frame(800,600);frame(1280,720);
        frame(321,241);frame(853,480);frame(854,481);frame(855,482);
        frame(1024,640);frame(480,800);frame(479,801);
        frame(16,16);frame(17,31);frame(1280,1024);frame(16,1024);frame(1280,16);
        frame(1024,768);frame(1366,768);frame(1600,900);
        frame(1920,1080);frame(1080,1920);frame(1920,1200);
        frame(1919,1079);frame(1920,1920);
        frame(16,1920);frame(1920,16);frame(21,1920);
        // Cancel during an input row, then reset during backpressured output.
        @(negedge clk);sw=800;sh=600;w=800;h=600;send_count=0;recv_count=0;done_count=0;cycles=0;held=0;armed=1;start=1;
        @(negedge clk);start=0;
        wait(send_count>300);@(negedge clk);cancel=1;armed=0;
        @(negedge clk);cancel=0;
        if(busy || out_valid || in_ready)fail("cancel not idle");
        frame(17,31);
        @(negedge clk);sw=16;sh=1024;w=16;h=1024;send_count=0;recv_count=0;done_count=0;cycles=0;held=0;armed=1;start=1;
        @(negedge clk);start=0;wait(recv_count>400);
        @(negedge clk);reset=1;armed=0;
        repeat(3)@(negedge clk);reset=0;held=0;
        frame(321,241);
        $display("GENERIC_SCALER_TEST_PASS mode=%0d full_frames=%0d pixels=%0d",MODE,rounds,rounds*921600);$finish;
    end
endmodule
