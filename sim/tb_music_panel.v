`timescale 1ns/1ps
module tb_music_panel;
    reg clk=0,reset=1,de=0,visible=1,sub_visible=1,valid=1,auto_mode=1,notice=0;
    reg [9:0] x=0,y=0,status=0;
    reg [23:0] background=24'hFFFFFF;
    reg [1:0] image=0,interval=2,preset=0,con=1,notice_index=0;
    reg signed [7:0] bri=0;
    reg [2:0] fade=4;
    wire mh,mv,md,oh,ov,od;
    wire [9:0] mx,my,ox,oy;
    wire [23:0] music,rgb;
    wire [7:0] sample_index;
    always #5 clk=~clk;
    `include "showcase_reference.vh"
    showcase_music_overlay layer(.pixel_clk(clk),.reset(reset),.hs(1'b1),.vs(1'b1),.de(de),
        .x(x),.y(y),.background_rgb(background),.visible(visible),.music_status(status),
        .sample_amplitude(-8'sd41),.sample_valid(1'b1),.sample_index(sample_index),
        .out_hs(mh),.out_vs(mv),.out_de(md),.out_x(mx),.out_y(my),.output_rgb(music));
    showcase_ui ui(.pixel_clk(clk),.reset(reset),.hs(mh),.vs(mv),.de(md),.x(mx),.y(my),
        .background_rgb(music),.display_valid(valid),.auto_play_enable(auto_mode),
        .subtitles_visible(sub_visible),.visual_visible(visible),.image_index(image),
        .interval_code(interval),.preset_mode(preset),.brightness(bri),.contrast(con),.fade_level(fade),
        .music_status(status),.hint_visible(1'b0),.hint_kind(3'd0),.notice_visible(notice),.notice_index(notice_index),
        .out_hs(oh),.out_vs(ov),.out_de(od),.out_x(ox),.out_y(oy),.output_rgb(rgb));
    reg [23:0] expected[0:2];
    reg [20:0] metadata[0:2];
    integer checks=0,pipeline=0;
    always @(posedge clk)begin
        if(reset)pipeline=0;
        else begin
            expected[2]=expected[1];expected[1]=expected[0];
            metadata[2]=metadata[1];metadata[1]=metadata[0];metadata[0]={de,x,y};
            expected[0]=ref_music_pixel(x,y,de,visible,status,1,-41,background);
            expected[0]=ref_showcase_ui(x,y,de,valid,image,auto_mode,interval,
                {(!visible),(!sub_visible),preset},bri,con,fade,status,notice,notice_index,0,0,expected[0]);
            #0.1;
            if(pipeline<3)pipeline++;
            else begin
                if({od,ox,oy}!==metadata[2] || rgb!==expected[2])begin
                    $display("SHOWCASE_CHECKER_REJECT PANEL x=%0d y=%0d got=%h expected=%h",ox,oy,rgb,expected[2]);
                    $fatal(1,"bar height/highlight/name/glyph/pipeline mismatch");
                end
                checks++;
            end
        end
    end
    task pixel(input integer px,py);
        begin @(negedge clk);x=px;y=py;de=1;end
    endtask
    integer m,s,k,h,xx,yy,p;
    initial begin
        repeat(5)@(negedge clk);reset=0;
        for(m=0;m<4;m++)for(s=0;s<8;s++)begin
            @(negedge clk);status={1'b1,2'(m),3'(s),3'd2,1'b1};image=m;
            background=((m+s)%2)?24'hFFFFFF:24'h010203;
            for(k=0;k<8;k++)begin
                h=ref_bar_height(ref_midi(m,k));
                pixel(40+k*72,432-h-1);pixel(40+k*72,432-h);
                pixel(87+k*72,432);pixel(88+k*72,432);pixel(60+k*72,431);
                h=ref_compact_height(ref_midi(m,k));
                pixel(408+k*27,439-h-1);pixel(408+k*27,439-h);
                pixel(425+k*27,439);pixel(426+k*27,439);pixel(418+k*27,438);
            end
            for(yy=328;yy<364;yy++)for(xx=16;xx<=623;xx++)pixel(xx,yy);
            for(yy=375;yy<=451;yy++)for(xx=400;xx<=631;xx++)pixel(xx,yy);
        end
        for(p=0;p<4;p++)begin
            @(negedge clk);preset=p;interval=p;auto_mode=p[0];
            bri=(p==1)?-32:(p==2)?16:0;con=(p==1)?0:(p==3)?2:1;
            notice=1;notice_index=p;
            for(yy=12;yy<=87;yy++)for(xx=16;xx<=623;xx++)pixel(xx,yy);
            for(yy=224;yy<=303;yy++)for(xx=344;xx<=623;xx++)pixel(xx,yy);
        end
        for(p=0;p<5;p++)begin
            @(negedge clk);status={1'(p==1 || p==2 || p==3),2'd3,3'd7,3'(p),1'(p==2 || p==3)};
            for(yy=328;yy<364;yy++)for(xx=16;xx<600;xx++)pixel(xx,yy);
            for(yy=375;yy<=451;yy++)for(xx=400;xx<=631;xx++)pixel(xx,yy);
        end
        @(negedge clk);visible=0;sub_visible=0;notice=0;
        for(yy=320;yy<480;yy++)for(xx=0;xx<640;xx++)pixel(xx,yy);
        visible=1;valid=0;for(xx=0;xx<640;xx++)pixel(xx,20);
        @(negedge clk);de=0;repeat(10)@(negedge clk);
        $display("MUSIC_PANEL_TEST_PASS pixels=%0d all_32_note_highlights heights names light_dark settings muted hidden",checks);$finish;
    end
    initial begin #30000000;$fatal(1,"music panel timeout");end
endmodule
