`timescale 1ns/1ps
// Full 800x525 raster with the NEW music/I2S/PCM feeding the unchanged layers.
module tb_presentation_video;
    reg clk=0,mclk=0,reset=1,req_d=0,aligned_boundary=0;
    always #20 clk=~clk;
    always #40.666667 mclk=~mclk;
    wire req,hs0,vs0,de0,hs,vs,de,re,wh,wv,wd,sh,sv,sd;
    wire [9:0] x,y,wx,wy,sx,sy;
    wire [23:0] memory_rgb,adjusted,faded,wave,subtitle,rgb;
    wire [23:0] background=memory_rgb^{x[7:0],y[7:0],8'h5A};
    wire boundary=req && !req_d;
    integer frames=0,complete_frames=0,pixels=0,green=0,black_green=0,starts=0;
    `include "subtitle_reference.vh"
    reg [3:0] switches_async=0;
    wire [3:0] active_switches;
    wire [1:0] preset_mode,contrast;
    wire signed [7:0] brightness;
    wire subtitles_visible,wave_visible;
    presentation_control #(.STABLE_CYCLES(8)) controls(.video_clk(clk),.reset(reset),
        .frame_boundary(boundary),.switches_async(switches_async),.switches_active(active_switches),
        .preset_mode(preset_mode),.brightness(brightness),.contrast(contrast),
        .subtitles_visible(subtitles_visible),.wave_visible(wave_visible));
    always @(negedge clk) switches_async=frames[3:0];
    wire displayed=(frames>0);
    wire [1:0] image=(frames>0)?(frames-1)/4:0;
    wire [2:0] level=(frames==5 || frames==6)?0:4;
    wire su,svalid,bclk,lrclk,dout,audio_valid,song_start;
    wire [1:0] song_image;
    wire [23:0] left_pcm,right_pcm;
    wire [7:0] read_index;
    wire signed [7:0] amplitude;
    wire sample_valid,valid_snapshot,snapshot_commit;
    video_timing_data timing(.video_clk(clk),.rst(reset),.read_req(req),.read_req_ack(1'b1),
        .hs(hs0),.vs(vs0),.de(de0));
    video_delay delay(.video_clk(clk),.rst(reset),.read_en(re),.read_data(24'h234567),
        .hs(hs0),.vs(vs0),.de(de0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(memory_rgb));
    video_active_position position(.pixel_clk(clk),.reset(reset),.vs(vs),.de(de),.x(x),.y(y));
    image_audio_cdc cdc(.video_clk(clk),.video_reset(reset),.display_valid(displayed),.display_image(image),
        .audio_clk(mclk),.audio_reset(reset),.selection_update(su),.selection_valid(svalid),.selection_image(song_image));
    image_melody_i2s #(.BASE_NOTE_SAMPLES(512),.RAMP_HOLD_SAMPLES(2),.SILENCE_SAMPLES(4)) tx(
        .I_mclk(mclk),.I_rst(reset),.selection_update(su),.selection_valid(svalid),.selection_image(song_image),
        .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrclk),.O_i2s_DOUT(dout),.active_valid(),.active_image(),.song_start(song_start));
    I2S_receiver rx(.I_clk(clk),.I_rst(reset),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrclk),.I_i2s_DOUT(dout),
        .O_audio_valid(audio_valid),.O_audio_left_data(left_pcm),.O_audio_right_data(right_pcm));
    video_adjust adjust(.pixel_clk(clk),.reset(reset),.de(de),.rgb_in(background),
        .brightness(brightness),.contrast(contrast),.rgb_out(adjusted));
    video_fade fade(.pixel_clk(clk),.reset(reset),.de(de),.rgb_in(adjusted),.fade_level(level),.rgb_out(faded));
    audio_wave_capture capture(.pixel_clk(clk),.reset(reset),.audio_valid(audio_valid),.audio_left(left_pcm),
        .frame_boundary(boundary),.video_de(de),.read_index(read_index),.read_amplitude(amplitude),
        .read_valid(sample_valid),.snapshot_valid(valid_snapshot),.snapshot_commit(snapshot_commit));
    presentation_overlay #(.GROUP_FRAMES(2)) layers(.pixel_clk(clk),.reset(reset),
        .frame_boundary(boundary),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),
        .subtitles_visible(subtitles_visible),.wave_visible(wave_visible),
        .background_rgb(displayed?faded:24'd0),.sample_amplitude(amplitude),
        .sample_valid(sample_valid),.sample_index(read_index),
        .out_hs(sh),.out_vs(sv),.out_de(sd),.out_x(sx),.out_y(sy),.output_rgb(subtitle));
    osd_overlay #(.SHOW_SETTINGS(1)) osd(.pixel_clk(clk),.reset(reset),.de(sd),.x(sx),.y(sy),
        .background_rgb(subtitle),.image_index(image),.auto_play_enable(1'b1),.display_valid(displayed),
        .brightness(brightness),.contrast(contrast),.fade_level(level),
        .interval_code((frames>0)?2'((frames-1)%4):2'd0),.preset_mode(preset_mode),
        .subtitles_visible(subtitles_visible),.wave_visible(wave_visible),.osd_rgb(rgb));
    always @(posedge clk)begin
        if(reset)begin req_d<=0;aligned_boundary<=0;frames<=0;end
        else begin req_d<=req;aligned_boundary<=boundary;if(boundary)frames<=frames+1;end
    end
    always @(posedge mclk)begin #0.1;if(!reset && song_start)starts++;end
    function integer quantize(input [23:0] bits);
        integer v,q;
        begin
            v=(bits>=24'h800000)?bits-16777216:bits;
            q=(v>=0)?v/65536:-((-v+65535)/65536);
            quantize=(q>45)?45:(q< -45)?-45:q;
        end
    endfunction
    function [7:0] adjusted_channel(input integer v);
        integer c,n,value,m;
        begin
            m=(frames>0)?(frames-1)%4:0;c=v-128;
            case(m)
                1:begin n=c*3;value=128+((n<0)?-((-n)/4):(n+3)/4)-32;end
                2:value=v+16;
                3:begin n=c*5;value=128+((n<0)?-((-n+3)/4):n/4);end
                default:value=v;
            endcase
            adjusted_channel=(value<0)?0:(value>255)?255:value;
        end
    endfunction
    function automatic [23:0] reference_osd(input integer px,py,active,valid,level_number,frame_number,
                                            input [23:0] background);
        string text_value,bri,con;
        integer local_y,index,column,row,m,interval_number;
        begin
            reference_osd=active?background:0;text_value="";row=0;index=0;column=0;
            m=(frame_number>0)?(frame_number-1)%4:0;interval_number=m;
            case(m)
                1:begin bri="BRI:-32";con="CON:075";end
                2:begin bri="BRI:+16";con="CON:100";end
                3:begin bri="BRI:+00";con="CON:125";end
                default:begin bri="BRI:+00";con="CON:100";end
            endcase
            if(px>=16 && px<112)begin
                local_y=py-16;index=(px-16)/8;column=(px-16)%8;
                if(local_y>=0 && local_y<16)text_value=valid?"ANLOGIC FPGA":"LOADING";
                else if(valid)begin
                    if(local_y>=20 && local_y<36)begin text_value=$sformatf("IMG:0%0d",1+(frame_number-1)/4);local_y-=20;end
                    else if(local_y>=40 && local_y<56)begin text_value="AUTO:ON";local_y-=40;end
                    else if(local_y>=60 && local_y<76)begin text_value=bri;local_y-=60;end
                    else if(local_y>=80 && local_y<96)begin text_value=con;local_y-=80;end
                    else if(local_y>=100 && local_y<116)begin text_value=(level_number==0)?"FADE:000":"FADE:100";local_y-=100;end
                end
                row=local_y/2;
            end else if(px>=360 && px<448)begin
                index=(px-360)/8;column=(px-360)%8;local_y=py-16;
                if(local_y>=0 && local_y<16)case(interval_number)
                    0:text_value="INT:01S";1:text_value="INT:03S";2:text_value="INT:05S";3:text_value="INT:10S";endcase
                else if(local_y>=20 && local_y<36)begin
                    case(m)0:text_value="MODE:NORMAL";1:text_value="MODE:SOFT";2:text_value="MODE:BRIGHT";3:text_value="MODE:VIVID";endcase
                    local_y-=20;
                end else if(local_y>=40 && local_y<56)begin text_value=(frame_number>0 && ((frame_number-1)&4))?"SUB:OFF":"SUB:ON";local_y-=40;end
                else if(local_y>=60 && local_y<76)begin text_value=(frame_number>0 && ((frame_number-1)&8))?"WAVE:OFF":"WAVE:ON";local_y-=60;end
                row=local_y/2;
            end
            if(active && row>=0 && row<8 && index<text_value.len() &&
               ref_dot(text_value[index],row,column))reference_osd=24'hFFFFFF;
        end
    endfunction
    integer bank_data[0:511],collected=0,skip=0,wb=0,db=1,windows=0,pcm_events=0;
    reg pending=0,published=0,old_pending,old_published,old_boundary;
    reg [23:0] expected[0:2];
    reg [22:0] metadata[0:2];
    reg check_rgb[0:2],black[0:2];
    reg [23:0] target;
    integer index,target_y,pipeline_valid=0,cycle=0,frame_pixels=0;
    integer last_hfall=0,last_vfall=0,hstart=0,vstart=0,hchecks=0,vchecks=0;
    // Reset begins inside an already-low pulse. Measure widths only AFTER a
    // genuinely observed high-to-low edge, not at monitor initialization.
    reg last_hs=0,last_vs=0,seen_h=0,seen_v=0,active_h=0,active_v=0;
    always @(posedge clk)begin
        if(reset)begin pipeline_valid=0;collected=0;skip=0;wb=0;db=1;pending=0;published=0;end
        else begin
            old_pending=pending;old_published=published;old_boundary=boundary;
            expected[2]=expected[1];expected[1]=expected[0];
            metadata[2]=metadata[1];metadata[1]=metadata[0];metadata[0]={hs,vs,de,x,y};
            check_rgb[2]=check_rgb[1];check_rgb[1]=check_rgb[0];
            black[2]=black[1];black[1]=black[0];black[0]=(level==0);
            check_rgb[0]=1'b1;
            target=(!de || !displayed || level==0)?0:
                {adjusted_channel(background[23:16]),adjusted_channel(background[15:8]),adjusted_channel(background[7:0])};
            if(de && (frames==0 || !((frames-1)&8)) && x>=16 && x<=623 && y>=330 && y<=455)begin
                target=24'h18202A;
                if(x==16 || x==623 || y==330 || y==455)target=24'h608090;
                else begin
                    if(y==392)target=24'h405060;
                    if(old_published && x>=64 && x<576)begin
                        index=(x-64)/2;target_y=392-bank_data[db*256+index];
                        if(y>=target_y-1 && y<=target_y+1)target=24'h00FF80;
                    end
                end
            end
            if(frames==0 || !((frames-1)&4))target=ref_subtitle(x,y,de,frames,2,2,target);
            target=reference_osd(x,y,de,displayed,level,frames,target);
            expected[0]=target;
            if(audio_valid)begin
                pcm_events++;
                if(skip<2)skip++;
                else if(!pending)begin bank_data[wb*256+collected]=quantize(left_pcm);collected++;if(collected==256)pending=1;end
            end
            if(boundary && old_pending)begin
                if(de)$fatal(1,"new audio snapshot frame event in active video");
                db=wb;wb=1-wb;collected=0;pending=0;published=1;windows++;
            end
            #0.1;
            if(snapshot_commit!==(old_boundary && old_pending))$fatal(1,"audio snapshot tore in full raster");
            if(pipeline_valid<4)pipeline_valid++;
            else begin
                cycle++;
                if({sh,sv,sd,sx,sy}!==metadata[2])$fatal(1,"music broke video pipeline alignment");
                if(!sd && rgb!==0)$fatal(1,"invalid DE generated nonblack output");
                if($test$plusargs("INJECT_LAYER") && frames==10 && sd && sx==200 && sy==392)
                    force layers.wave_visible_d=1'b1;
                if(check_rgb[2] && rgb!==expected[2])begin
                    $display("INTERACTION_CHECKER_REJECT LAYER frame=%0d x=%0d y=%0d got=%h expected=%h",frames,sx,sy,rgb,expected[2]);
                    $fatal(1,"layer bypass, text, or adjusted background pixel mismatch");
                end
                if(sd)begin
                    if(sx!==frame_pixels%640 || sy!==frame_pixels/640)$fatal(1,"lost/repeated active video pixel");
                    frame_pixels++;pixels++;
                    if(rgb==24'h00FF80)begin green++;if(black[2])black_green++;end
                    if(frame_pixels==307200)begin frame_pixels=0;complete_frames++;end
                end
                if(last_hs && !sh)begin
                    if(seen_h && cycle-last_hfall!=800)$fatal(1,"horizontal period changed");
                    seen_h=1;last_hfall=cycle;hstart=cycle;active_h=1;
                end
                if(!last_hs && sh && active_h)begin if(cycle-hstart!=96)$fatal(1,"HS width changed");active_h=0;hchecks++;end
                if(last_vs && !sv)begin
                    if(seen_v && cycle-last_vfall!=420000)$fatal(1,"frame period changed");
                    seen_v=1;last_vfall=cycle;vstart=cycle;active_v=1;
                end
                if(!last_vs && sv && active_v)begin if(cycle-vstart!=1600)$fatal(1,"VS width changed");active_v=0;vchecks++;end
                last_hs=sh;last_vs=sv;
            end
        end
    end
    initial begin
        repeat(20)@(negedge clk);reset=0;
        // The initial raster precedes the first read_req event. Include that
        // raster PLUS all sixteen post-boundary physical switch combinations.
        wait(complete_frames>=17);@(negedge clk);
        if(starts!=4 || windows<6 || pcm_events<5000 || green<1000 ||
           black_green<100 || hchecks<8000 || vchecks<15)$fatal(1,"insufficient music/video integration coverage");
        $display("PRESENTATION_VIDEO_TEST_PASS frames=%0d pixels=%0d melodies=%0d PCM=%0d snapshots=%0d green=%0d black_green=%0d",
                 complete_frames,pixels,starts,pcm_events,windows,green,black_green);$finish;
    end
    initial begin #320000000;$fatal(1,"presentation full-raster timeout");end
endmodule


