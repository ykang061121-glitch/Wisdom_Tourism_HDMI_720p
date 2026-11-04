`timescale 1ns/1ps
module tb_transparent_osd;
    reg clk=0,reset=1,de=0,visible=1,sub_visible=1,valid=1,auto_mode=1,notice=0,hint=0;
    reg [9:0] x=0,y=0,status=0;
    reg [23:0] background=24'hFFFFFF;
    reg [1:0] image=0,interval=2,preset=0,con=1,notice_index=0;
    reg signed [7:0] bri=0;
    reg [2:0] fade=4,hint_kind=0;
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
        .music_status(status),.hint_visible(hint),.hint_kind(hint_kind),.notice_visible(notice),.notice_index(notice_index),
        .out_hs(oh),.out_vs(ov),.out_de(od),.out_x(ox),.out_y(oy),.output_rgb(rgb));
    wire old_h,old_v,old_de,no_h,no_v,no_de;
    wire [9:0] old_x,old_y,no_x,no_y;
    wire [23:0] old_rgb,no_rgb;
    wire [23:0] pre_palette_rgb;
    showcase_ui_pre_palette old_palette(.pixel_clk(clk),.reset(reset),.hs(mh),.vs(mv),.de(md),.x(mx),.y(my),
        .background_rgb(music),.display_valid(valid),.auto_play_enable(auto_mode),
        .subtitles_visible(sub_visible),.visual_visible(visible),.image_index(image),
        .interval_code(interval),.preset_mode(preset),.brightness(bri),.contrast(con),.fade_level(fade),
        .music_status(status),.hint_visible(hint),.hint_kind(hint_kind),.notice_visible(notice),.notice_index(notice_index),
        .out_hs(),.out_vs(),.out_de(),.out_x(),.out_y(),.output_rgb(pre_palette_rgb));
    showcase_ui_compact_baseline frozen(.pixel_clk(clk),.reset(reset),.hs(mh),.vs(mv),.de(md),.x(mx),.y(my),
        .background_rgb(music),.display_valid(valid),.auto_play_enable(auto_mode),
        .subtitles_visible(sub_visible),.visual_visible(visible),.image_index(image),
        .interval_code(interval),.preset_mode(preset),.brightness(bri),.contrast(con),.fade_level(fade),
        .music_status(status),.hint_visible(hint),.hint_kind(hint_kind),.notice_visible(notice),.notice_index(notice_index),
        .out_hs(old_h),.out_vs(old_v),.out_de(old_de),.out_x(old_x),.out_y(old_y),.output_rgb(old_rgb));
    showcase_ui without_fade(.pixel_clk(clk),.reset(reset),.hs(mh),.vs(mv),.de(md),.x(mx),.y(my),
        .background_rgb(music),.display_valid(valid),.auto_play_enable(auto_mode),
        .subtitles_visible(sub_visible),.visual_visible(visible),.image_index(image),
        .interval_code(interval),.preset_mode(preset),.brightness(bri),.contrast(con),.fade_level(3'd4),
        .music_status(status),.hint_visible(hint),.hint_kind(hint_kind),.notice_visible(notice),.notice_index(notice_index),
        .out_hs(no_h),.out_vs(no_v),.out_de(no_de),.out_x(no_x),.out_y(no_y),.output_rgb(no_rgb));
    reg [23:0] expected[0:2];
    reg [20:0] metadata[0:2];
    integer checks=0,pipeline=0,music_checks=0,transparent_checks=0,no_prompt_checks=0;
    reg [23:0] backgrounds[0:2];
    reg [2:0] fades[0:2];
    reg hint_flags[0:2],notice_flags[0:2];
    reg [23:0] observed;
    always @(posedge clk)begin
        if(reset)pipeline=0;
        else begin
            expected[2]=expected[1];expected[1]=expected[0];
            for(integer j=2;j>0;j--)begin
                backgrounds[j]=backgrounds[j-1];fades[j]=fades[j-1];
                hint_flags[j]=hint_flags[j-1];notice_flags[j]=notice_flags[j-1];
            end
            backgrounds[0]=background;fades[0]=fade;hint_flags[0]=hint;notice_flags[0]=notice;
            metadata[2]=metadata[1];metadata[1]=metadata[0];metadata[0]={de,x,y};
            expected[0]=ref_music_pixel(x,y,de,visible,status,1,-41,background);
            expected[0]=ref_showcase_ui(x,y,de,valid,image,auto_mode,interval,
                {(!visible),(!sub_visible),preset},bri,con,fade,status,notice,notice_index,hint,hint_kind,expected[0]);
            #0.1;
            if(pipeline<3)pipeline++;
            else begin
                observed=rgb;
                // Mutation source is the actual frozen Oct18 RTL, not an
                // invented reference rectangle or a weakened expectation.
                if($test$plusargs("INJECT_OPAQUE_TOP") && od && oy>=8 && oy<=39 && ox>=8 && ox<=631)
                    observed=old_rgb;
                if($test$plusargs("INJECT_FADE_FLASH") && od && oy>=44 && oy<=67 &&
                   ox>=8 && ox<=319 && fades[2]!=4 && !hint_flags[2])observed=old_rgb;
                if($test$plusargs("INJECT_TOP_OUTLINE") && od && oy>=16 && oy<32 &&
                   pre_palette_rgb==0 && backgrounds[2]!=0)observed=pre_palette_rgb;
                if($test$plusargs("INJECT_TOP_WHITE") && od && oy>=16 && oy<32 &&
                   rgb==24'hFFC000)observed=24'hEAF6FF;
                if({old_h,old_v,old_de,old_x,old_y}!=={oh,ov,od,ox,oy} ||
                   {no_h,no_v,no_de,no_x,no_y}!=={oh,ov,od,ox,oy})$fatal(1,"UI latency changed");
                if(od && oy>=375 && oy<=451 && ox>=400 && ox<=631)begin
                    music_checks++;
                    if(rgb!==old_rgb)$fatal(1,"SATISFIED MUSIC PANEL CHANGED");
                end
                // Metamorphic proof: fade_level cannot affect ANY UI pixel.
                if(observed!==no_rgb)begin
                    $display("TRANSPARENT_CHECKER_REJECT FADE_OR_PLATE x=%0d y=%0d observed=%h nofade=%h",ox,oy,observed,no_rgb);
                    $fatal(1,"fade debug text, opaque plate, or outline regression");
                end
                if(od && oy>=8 && oy<=39 && ox>=8 && ox<=631 && expected[2]===backgrounds[2])begin
                    transparent_checks++;
                    if(observed!==backgrounds[2])$fatal(1,"non-glyph top pixel not transparent");
                end
                if(od && oy>=16 && oy<32 && observed==0 && backgrounds[2]!=0)
                    $fatal(1,"black outline restored in colored top row");
                if(od && oy>=44 && oy<=67 && !hint_flags[2] && !notice_flags[2])begin
                    no_prompt_checks++;
                    if(observed!==backgrounds[2])$fatal(1,"unrequested flash text");
                end
                if({od,ox,oy}!==metadata[2] || observed!==expected[2])begin
                    $display("TRANSPARENT_CHECKER_REJECT PANEL x=%0d y=%0d got=%h expected=%h",ox,oy,observed,expected[2]);
                    $fatal(1,"bar height/highlight/name/glyph/pipeline mismatch");
                end
                checks++;
            end
        end
    end
    task pixel(input integer px,py);
        begin @(negedge clk);x=px;y=py;de=1;end
    endtask
    integer m,s,xx,yy,p,a,r;
    initial begin
        repeat(5)@(negedge clk);reset=0;
        // Establish the font side-bearing assumption for every supported
        // glyph/punctuation, independently from the DUT's ROM implementation.
        for(a=0;a<128;a++)for(r=0;r<8;r++)
            if(ref_ui_dot(a,r,0))$fatal(1,"outline assumption: first column not empty");
        for(m=0;m<4;m++)for(s=0;s<8;s++)begin
            @(negedge clk);status={1'b1,2'(m),3'(s),3'd2,1'b1};image=m;
            background=((m+s)%2)?24'hFFFFFF:24'h010203;
            for(yy=374;yy<=452;yy++)for(xx=398;xx<=633;xx++)pixel(xx,yy);
        end
        for(p=0;p<16;p++)begin
            @(negedge clk);preset=p%4;interval=p%4;image=p%4;auto_mode=p[0];
            visible=!p[3];sub_visible=!p[2];fade=p%5;hint=p[2];hint_kind=1+(p%5);
            notice=p[1];notice_index=p%4;background=p[0]?24'hFFFFFF:24'h010203;
            for(yy=0;yy<81;yy++)for(xx=0;xx<640;xx++)pixel(xx,yy);
        end
        // Every prompt type with BOTH visible and hidden layer switches.
        for(p=0;p<5;p++)begin
            @(negedge clk);hint=1;hint_kind=p+1;notice=1;
            for(yy=44;yy<=67;yy++)for(xx=0;xx<640;xx++)pixel(xx,yy);
        end
        @(negedge clk);de=0;repeat(10)@(negedge clk);
        if(music_checks<570000 || transparent_checks<100000 || no_prompt_checks<10000)
            $fatal(1,"insufficient transparent/music/metamorphic coverage");
        $display("TRANSPARENT_OSD_TEST_PASS pixels=%0d music_equivalent=%0d non_glyph_top=%0d no_prompt=%0d all_32_notes white_dark all_controls no_fade",checks,music_checks,transparent_checks,no_prompt_checks);$finish;
    end
    initial begin #40000000;$fatal(1,"transparent OSD timeout");end
endmodule
