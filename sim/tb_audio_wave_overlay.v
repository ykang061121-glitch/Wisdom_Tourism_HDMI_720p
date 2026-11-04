`timescale 1ns/1ps
module tb_audio_wave_overlay;
    reg clk=0,reset=1,hs=1,vs=1,de=0;
    reg [9:0] x=0,y=0;
    reg [23:0] rgb=0;
    reg signed [7:0] amp=0;
    reg sample_valid=0;
    wire [7:0] addr;
    wire oh,ov,od;
    wire [9:0] ox,oy;
    wire [23:0] wave,adjusted,faded,layer_rgb,osd;
    integer xx,yy,a,checks=0;
    reg oldh,oldv,oldd;
    reg [9:0] oldx,oldy;
    reg [23:0] oldrgb,exp;
    always #20 clk=~clk;
    audio_wave_overlay dut(.pixel_clk(clk),.reset(reset),.hs(hs),.vs(vs),.de(de),
        .x(x),.y(y),.background_rgb(rgb),.sample_amplitude(amp),.sample_valid(sample_valid),
        .sample_index(addr),.out_hs(oh),.out_vs(ov),.out_de(od),.out_x(ox),.out_y(oy),.wave_rgb(wave));
    function [23:0] reference;
        input integer px,py,value,has_audio,active;
        input [23:0] bg;
        integer ty;
        begin
            reference=active?bg:0;
            if(active && px>=16 && px<=623 && py>=330 && py<=455) begin
                reference=24'h18202A;
                if(px==16 || px==623 || py==330 || py==455) reference=24'h608090;
                else begin
                    if(py==392) reference=24'h405060;
                    ty=392-value;
                    if(has_audio && px>=64 && px<=575 && (py-ty>=-1 && py-ty<=1)) reference=24'h00FF80;
                end
            end
        end
    endfunction
    task pixel;
        input integer px,py,value,has_audio,active;
        input [23:0] bg;
        integer expected_index;
        begin
            @(negedge clk);
            x=px;y=py;rgb=bg;de=active;hs=(px%9!=0);vs=(py%7!=0);
            // Synchronous RAM data arrives AFTER the sampling edge, not early.
            oldh=hs;oldv=vs;oldd=de;oldx=x;oldy=y;oldrgb=rgb;
            expected_index=(px>=64 && px<=575)?(px-64)/2:0;
            #1;if(addr!==expected_index[7:0]) $fatal(1,"x-to-sample address mismatch");
            @(posedge clk);#0.1;amp=value;sample_valid=has_audio;#0.9;
            exp=reference(px,py,value,has_audio,active,bg);
            if(wave!==exp || {oh,ov,od,ox,oy}!=={oldh,oldv,oldd,oldx,oldy})
                $fatal(1,"overlay pixel/timing mismatch x=%0d y=%0d amp=%0d rgb=%h/%h",px,py,value,wave,exp);
            checks=checks+1;
        end
    endtask
    // A second instance exercises the actual adjust -> fade -> wave -> OSD order.
    reg [9:0] lx=0,ly=0;
    reg ld=1;
    wire lh,lv,ld1;
    wire [9:0] lx1,ly1;
    wire [7:0] la;
    video_adjust adjust(.pixel_clk(clk),.reset(reset),.de(ld),.rgb_in(24'h8090A0),
        .brightness(8'sd16),.contrast(2'd1),.rgb_out(adjusted));
    video_fade fade(.pixel_clk(clk),.reset(reset),.de(ld),.rgb_in(adjusted),.fade_level(3'd0),.rgb_out(faded));
    audio_wave_overlay layer(.pixel_clk(clk),.reset(reset),.hs(1'b1),.vs(1'b1),.de(ld),.x(lx),.y(ly),
        .background_rgb(faded),.sample_amplitude(8'sd30),.sample_valid(1'b1),.sample_index(la),
        .out_hs(lh),.out_vs(lv),.out_de(ld1),.out_x(lx1),.out_y(ly1),.wave_rgb(layer_rgb));
    osd_overlay text(.pixel_clk(clk),.reset(reset),.de(ld1),.x(lx1),.y(ly1),.background_rgb(layer_rgb),
        .image_index(2'd1),.auto_play_enable(1'b1),.display_valid(1'b1),.brightness(8'sd16),
        .contrast(2'd1),.fade_level(3'd0),.osd_rgb(osd));
    initial begin
        repeat(4) @(negedge clk);reset=0;
        // Full 640x480 scan checks unchanged background and every panel pixel.
        for(yy=0;yy<480;yy=yy+1) for(xx=0;xx<640;xx=xx+1)
            pixel(xx,yy,((xx/2)%91)-45,1,1,((xx*91)^yy)&24'hFFFFFF);
        for(a=-45;a<=45;a=a+1) for(yy=330;yy<=455;yy=yy+1) pixel(100,yy,a,1,1,24'h123456);
        pixel(64,392,0,1,1,24'h123456);
        pixel(64,347,45,1,1,24'h123456);
        pixel(575,437,-45,1,1,24'h123456);
        pixel(100,362,30,0,1,24'h123456);
        pixel(100,392,30,0,1,24'h123456);
        pixel(100,362,30,1,0,24'h123456);
        @(negedge clk);lx=100;ly=362;
        @(posedge clk);#1;if(osd!==24'h00FF80 || faded!==0) $fatal(1,"wave faded with background");
        @(negedge clk);lx=19;ly=16; // A row 0 = 0x18: column 3 is foreground
        @(posedge clk);#1;if(osd!==24'hFFFFFF || layer_rgb!==0) $fatal(1,"OSD not on top of black background");
        @(negedge clk);lx=100;ly=200;
        @(posedge clk);#1;if(osd!==0) $fatal(1,"outside-layer background changed");
        reset=1;#1;if(wave!==0 || od!==0) $fatal(1,"reset pixel output invalid");
        $display("AUDIO_WAVE_OVERLAY_TEST_PASS independent_pixels=%0d",checks);$finish;
    end
    initial begin #20000000;$fatal(1,"overlay timeout");end
endmodule
