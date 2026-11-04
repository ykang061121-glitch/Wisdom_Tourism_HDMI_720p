`timescale 1ns/1ps
module tb_bottom_scroll;
    reg clk=0,reset=1,boundary=0,de=0,sub=1,vis=1,commit=0,auto_mode=0;
    reg [9:0] x=0,y=0;
    reg [1:0] image=0,interval=2,preset=0;
    reg [2:0] fade=4;
    reg [23:0] background=24'hFFFFFF;
    wire oh,ov,od;
    wire [9:0] ox,oy;
    wire [23:0] rgb;
    integer frames=0,pipeline=0,checks=0,foreground=0,shadows=0,hidden=0,wraps=0,last_message=0;
    reg [23:0] expected[0:4],backgrounds[0:4];
    reg [20:0] metadata[0:4];
    always #20 clk=~clk;
    `include "showcase_reference.vh"
    showcase_presentation dut(.pixel_clk(clk),.reset(reset),.frame_boundary(boundary),
        .hs(1'b1),.vs(1'b1),.de(de),.x(x),.y(y),.background_rgb(background),
        .subtitles_visible(sub),.visual_visible(vis),.sample_amplitude(8'sd0),.sample_valid(1'b0),
        .sample_index(),.audio_status(10'd0),.display_commit(commit),.display_valid(1'b1),
        .auto_play_enable(auto_mode),.image_index(image),.interval_code(interval),.preset_mode(preset),
        .brightness(8'sd0),.contrast(2'd1),.fade_level(fade),
        .out_hs(oh),.out_vs(ov),.out_de(od),.out_x(ox),.out_y(oy),.output_rgb(rgb));
    always @(posedge clk)begin
        if(reset)begin frames=0;pipeline=0;end
        else begin
            for(integer p=4;p>0;p--)begin
                expected[p]=expected[p-1];metadata[p]=metadata[p-1];backgrounds[p]=backgrounds[p-1];
            end
            expected[0]=sub?ref_compact_subtitle(x,y,de,frames,2,180,background):(de?background:0);
            backgrounds[0]=background;metadata[0]={de,x,y};
            if(boundary)frames++;
            #0.1;
            if(pipeline<6)pipeline++;
            else begin
                if({od,ox,oy}!==metadata[4] || rgb!==expected[4])begin
                    $display("TRANSPARENT_CHECKER_REJECT SCROLL_PIXEL frame=%0d x=%0d y=%0d got=%h expected=%h",frames,ox,oy,rgb,expected[4]);
                    $fatal(1,"bottom clip/glyph/shadow/hide/pipeline mismatch");
                end
                if(od)begin
                    checks++;
                    if(rgb==24'hFFCC40)foreground++;
                    if(rgb==0 && backgrounds[4]!=0)shadows++;
                    if(!sub)hidden++;
                end
            end
        end
    end
    task pixel(input integer px,py,active);
        begin @(negedge clk);x=px;y=py;de=active;end
    endtask
    task frame;
        begin
            @(negedge clk);boundary=1;de=0;
            @(negedge clk);boundary=0;commit=(frames%137==0);
            image=frames%4;interval=(frames/71)%4;auto_mode=(frames/89)%2;
            preset=(frames/53)%4;fade=frames%5;vis=(frames/97)%2;
            sub=!((frames>=2000 && frames<2300) || (frames>=7200 && frames<7500));
            background=(frames%2)?24'hFFFFFF:24'h010203;
            repeat(4)@(negedge clk);commit=0;
        end
    endtask
    integer n,xx,yy,row_first,row_last,offset,message,tail;
    string message_text;
    initial begin
        repeat(5)@(negedge clk);reset=0;
        // Two complete THREE-message cycles at the ORIGINAL two frames/pixel.
        // Frame events are compressed unit stimuli, not 10432 full rasters;
        // unchanged full-raster tests separately retain every HS/VS/DE check.
        for(n=0;n<10432;n++)begin
            frame;
            offset=ref_scroll_offset(frames,2);message=ref_scroll_message(frames,2);
            message_text=ref_string(message);tail=608+message_text.len()*8-1;
            if($test$plusargs("INJECT_SCROLL_RESTART") && n==400)
                force dut.subtitles.scroll_offset=10'd0;
            #0.1;
            if(dut.subtitles.scroll_offset!==offset || dut.subtitles.scroll_message!==message ||
               dut.subtitles.subtitle_group!==(frames/180)%3)begin
                $display("TRANSPARENT_CHECKER_REJECT SCROLL_STATE frame=%0d offset=%0d expected=%0d",frames,dut.subtitles.scroll_offset,offset);
                $fatal(1,"lost/injected restart, speed or tail wrap mismatch");
            end
            if(message!=last_message)wraps++;
            last_message=message;
            row_first=456+(frames%16);row_last=row_first;
            if(n%32==0 || offset==0 || offset==1 || offset==7 || offset==8 ||
               offset==311 || offset==607 || offset==608 || offset==tail-1 || offset==tail)begin
                row_first=456;row_last=471;
            end
            for(yy=row_first;yy<=row_last;yy++)for(xx=0;xx<640;xx++)pixel(xx,yy,1);
            pixel(0,472,1);pixel(639,472,1);pixel(0,0,0);
        end
        repeat(8)pixel(0,0,0);
        if(wraps!=6 || foreground<200000 || shadows<50000 || hidden<300000 || checks<7000000)
            $fatal(1,"insufficient complete scroll/light/dark/hide coverage");
        @(negedge clk);reset=1;repeat(3)@(negedge clk);reset=0;
        frame;
        if(dut.subtitles.scroll_offset!=0 || dut.subtitles.scroll_message!=0)$fatal(1,"scroll reset not clean");
        $display("BOTTOM_SCROLL_TEST_PASS frame_events=10432 cycles=2 wraps=%0d pixels=%0d foreground=%0d shadow=%0d hidden=%0d original_speed all_messages clipping switch_fade_commit_independent",wraps,checks,foreground,shadows,hidden);$finish;
    end
    initial begin #1000000000;$fatal(1,"bottom scroll timeout");end
endmodule

