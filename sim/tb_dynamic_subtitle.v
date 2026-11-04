`timescale 1ns/1ps
module tb_dynamic_subtitle;
    reg clk=0,reset=1,boundary=0,hs=1,vs=1,de=0;
    reg [9:0] x=0,y=0;
    reg [23:0] bg=24'h123456;
    wire oh,ov,od;
    wire [9:0] ox,oy,offset;
    wire [1:0] message,group_number;
    wire [23:0] rgb;
    integer frames=0,checks=0,frame_checks=0,xx,yy,n,r,c,a;
    reg inject_pixel,inject_scroll;
    reg [23:0] exp_rgb[0:1];
    reg [22:0] exp_meta[0:1];
    integer pipeline_valid=0;
    reg [23:0] observed;
    always #20 clk=~clk;
    `include "subtitle_reference.vh"
    dynamic_subtitle_overlay dut(.pixel_clk(clk),.reset(reset),.frame_boundary(boundary),
        .hs(hs),.vs(vs),.de(de),.x(x),.y(y),.background_rgb(bg),
        .out_hs(oh),.out_vs(ov),.out_de(od),.out_x(ox),.out_y(oy),.subtitle_rgb(rgb),
        .scroll_offset(offset),.scroll_message(message),.subtitle_group(group_number));
    reg [5:0] fixture_code=0;
    reg [2:0] fixture_row=0;
    reg [9:0] fixture_address=0;
    wire [7:0] fixture_bits,fixture_character;
    reg [63:0] glyph;
    reg [7:0] expected_byte;
    integer ascii;
    string expected_text;
    subtitle_font_rom glyph_fixture(.pixel_clk(clk),.glyph_code(fixture_code),
        .glyph_row(fixture_row),.font_bits(fixture_bits));
    subtitle_text_rom text_fixture(.pixel_clk(clk),.address(fixture_address),.character(fixture_character));
    always @(posedge clk) begin
        if(reset) begin frames=0;pipeline_valid=0;end
        else begin
            exp_rgb[1]=exp_rgb[0];exp_meta[1]=exp_meta[0];
            exp_rgb[0]=ref_subtitle(x,y,de,frames,2,180,bg);
            exp_meta[0]={hs,vs,de,x,y};
            if(boundary && !de) frames=frames+1;
            #1;
            observed=rgb;
            if(inject_pixel && od && rgb==24'hFFCC40) observed=rgb^24'd1;
            if(pipeline_valid>=1 &&
               (observed!==exp_rgb[1] || {oh,ov,od,ox,oy}!==exp_meta[1])) begin
                $display("SUBTITLE_CHECKER_REJECT pixel x=%0d y=%0d observed=%h expected=%h",ox,oy,observed,exp_rgb[1]);
                $fatal(1,"subtitle glyph/clip/pipeline mismatch");
            end
            if((offset+(inject_scroll && frames>0))!==ref_scroll_offset(frames,2) ||
               message!==ref_scroll_message(frames,2) || group_number!==(frames/180)%3) begin
                $display("SUBTITLE_CHECKER_REJECT scroll frames=%0d offset=%0d expected=%0d",frames,offset,ref_scroll_offset(frames,2));
                $fatal(1,"frame-only scroll/group state mismatch");
            end
            pipeline_valid=pipeline_valid+1;checks=checks+1;
        end
    end
    task pixel(input integer px,py,active,frame_event);
        begin
            @(negedge clk);x=px;y=py;de=active;boundary=frame_event;
            hs=(px%11!=0);vs=(py%7!=0);bg=((px*97)^py)^24'hABC123;
        end
    endtask
    task next_frame;
        begin pixel(0,0,0,1);pixel(0,0,0,0);frame_checks=frame_checks+1;end
    endtask
    initial begin
        inject_pixel=$test$plusargs("INJECT_SUBTITLE_PIXEL");
        inject_scroll=$test$plusargs("INJECT_SUBTITLE_SCROLL");
        repeat(4) @(negedge clk);reset=0;
        // All supported glyphs and every unused code/row must match the fixture.
        for(c=0;c<64;c=c+1) for(r=0;r<8;r=r+1) begin
            @(negedge clk);fixture_code=c;fixture_row=r;
            ascii=(c>=1 && c<=26)?64+c:(c>=27 && c<=36)?48+c-27:(c==37)?120:32;
            glyph=ref_bitmap(ascii);expected_byte=(glyph >> ((7-r)*8)) & 255;
            @(posedge clk);#2;
            if(fixture_bits!==expected_byte) $fatal(1,"font code=%0d row=%0d mismatch",c,r);
        end
        for(a=0;a<1024;a=a+1) begin
            @(negedge clk);fixture_address=a;expected_text=ref_string(a/64);
            expected_byte=((a%64)<expected_text.len())?expected_text[a%64]:8'h20;
            @(posedge clk);#2;
            if(fixture_character!==expected_byte) $fatal(1,"text ROM byte address=%0d mismatch",a);
        end
        for(yy=0;yy<480;yy=yy+1) for(xx=0;xx<640;xx=xx+1) pixel(xx,yy,1,0);
        // Mathematical absolute-frame reference covers two full scroll cycles.
        for(n=0;n<10432;n=n+1) begin
            next_frame;
            if((n%97)==0) for(xx=0;xx<640;xx=xx+1) pixel(xx,184+(n%16),1,0);
            if((n%180)==0)
                for(yy=250;yy<292;yy=yy+1) for(xx=8;xx<288;xx=xx+1) pixel(xx,yy,1,0);
        end
        pixel(19,250,1,1);pixel(19,250,1,0); // unsafe active event is ignored
        for(xx=0;xx<640;xx=xx+1) pixel(xx,199,1,0);
        pixel(19,250,0,0);pixel(19,250,0,0);pixel(19,250,0,0);
        @(negedge clk);reset=1;#1;
        if(rgb!==0 || od!==0 || offset!==0 || message!==0 || group_number!==0) $fatal(1,"reset contract");
        repeat(3) @(negedge clk);reset=0;boundary=0;de=0;
        for(yy=184;yy<200;yy=yy+1) for(xx=0;xx<640;xx=xx+1) pixel(xx,yy,1,0);
        repeat(3) pixel(0,0,0,0);
        @(negedge clk);
        $display("DYNAMIC_SUBTITLE_TEST_PASS glyph_codes=38 font_rows=512 text_bytes=1024 independent_pixels=%0d frame_events=%0d full_scroll_cycles=2 default_group_frames=180",checks,frame_checks);
        $finish;
    end
    initial begin #150000000;$fatal(1,"subtitle unit timeout");end
endmodule
