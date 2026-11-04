`timescale 1ns/1ps
// Full 800x525 raster with the NEW music/I2S/PCM feeding the unchanged layers.
module tb_showcase_video;
    reg clk=0,mclk=0,reset=1,req_d=0,aligned_boundary=0;
    always #20 clk=~clk;
    always #40.666667 mclk=~mclk;
    wire req,hs0,vs0,de0,hs,vs,de,re,wh,wv,wd,sh,sv,sd;
    wire [9:0] x,y,wx,wy,sx,sy;
    wire [23:0] memory_rgb,adjusted,faded,wave,subtitle,rgb;
    integer frames=0;
    wire [23:0] background=(frames%3==0)?24'hFFFFFF:(frames%3==1)?24'h010203:(memory_rgb^{x[7:0],y[7:0],8'h5A});
    wire boundary=req && !req_d;
    integer complete_frames=0,pixels=0,green=0,black_green=0,starts=0,restored_green=0,hidden_pcm=0;
    integer preview_file=0;
    initial if($test$plusargs("WRITE_SHOWCASE_FRAME"))preview_file=$fopen("showcase_frame.rgb","wb");
    `include "showcase_reference.vh"
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
    reg display_commit=0;
    wire [9:0] playback_status,video_status;
    reg [9:0] expected_music=0;
    integer notice_left=0,hint_left=0,hint_type=0;
    reg setting_check=0,settings_primed=0;
    reg [6:0] previous_settings=0;
    wire [6:0] current_settings={wave_visible,subtitles_visible,preset_mode,1'b1,
        (frames>0)?2'((frames-1)%4):2'd0};
    reg [1:0] expected_notice_image=0;
    melody_status_cdc status_cdc(.audio_clk(mclk),.video_clk(clk),.reset(reset),
        .audio_status(playback_status),.video_status(video_status));
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
        .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrclk),.O_i2s_DOUT(dout),.active_valid(),.active_image(),.song_start(song_start),.playback_status(playback_status));
    I2S_receiver rx(.I_clk(clk),.I_rst(reset),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrclk),.I_i2s_DOUT(dout),
        .O_audio_valid(audio_valid),.O_audio_left_data(left_pcm),.O_audio_right_data(right_pcm));
    video_adjust adjust(.pixel_clk(clk),.reset(reset),.de(de),.rgb_in(background),
        .brightness(brightness),.contrast(contrast),.rgb_out(adjusted));
    video_fade fade(.pixel_clk(clk),.reset(reset),.de(de),.rgb_in(adjusted),.fade_level(level),.rgb_out(faded));
    audio_wave_capture capture(.pixel_clk(clk),.reset(reset),.audio_valid(audio_valid),.audio_left(left_pcm),
        .frame_boundary(boundary),.video_de(de),.read_index(read_index),.read_amplitude(amplitude),
        .read_valid(sample_valid),.snapshot_valid(valid_snapshot),.snapshot_commit(snapshot_commit));
    showcase_presentation #(.GROUP_FRAMES(2),.NOTICE_FRAMES(2)) layers(.pixel_clk(clk),.reset(reset),
        .frame_boundary(boundary),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),
        .subtitles_visible(subtitles_visible),.visual_visible(wave_visible),
        .background_rgb(displayed?faded:24'd0),.sample_amplitude(amplitude),
        .sample_valid(sample_valid),.sample_index(read_index),.audio_status(video_status),
        .display_commit(display_commit),.display_valid(displayed),.image_index(image),
        .auto_play_enable(1'b1),.interval_code((frames>0)?2'((frames-1)%4):2'd0),
        .preset_mode(preset_mode),.brightness(brightness),.contrast(contrast),.fade_level(level),
        .out_hs(sh),.out_vs(sv),.out_de(sd),.out_x(sx),.out_y(sy),.output_rgb(rgb));
    always @(posedge clk)begin
        if(reset)begin req_d<=0;aligned_boundary<=0;frames<=0;display_commit<=0;end
        else begin req_d<=req;aligned_boundary<=boundary;display_commit<=0;
            if(boundary)begin frames<=frames+1;display_commit<=((frames%4)==0);end end
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
    integer bank_data[0:511],collected=0,skip=0,wb=0,db=1,windows=0,pcm_events=0;
    reg pending=0,published=0,old_pending,old_published,old_boundary;
    reg [23:0] expected[0:4];
    reg [22:0] metadata[0:4];
    reg check_rgb[0:4],black[0:4];
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
            if(setting_check)begin
                if(settings_primed && current_settings!=previous_settings)begin
                    hint_left=72;
                    if(current_settings[6]!=previous_settings[6])hint_type=5;
                    else if(current_settings[5]!=previous_settings[5])hint_type=4;
                    else if(current_settings[4:3]!=previous_settings[4:3])hint_type=3;
                    else if(current_settings[2]!=previous_settings[2])hint_type=2;
                    else hint_type=1;
                end else if(hint_left>0)hint_left--;
                previous_settings=current_settings;settings_primed=1;
            end
            setting_check=boundary;
            if(boundary)expected_music=video_status;
            if(!displayed)notice_left=0;
            else if(display_commit)begin notice_left=2;expected_notice_image=image;end
            else if(boundary && notice_left>0)notice_left--;
            for(integer p=4;p>0;p--)begin
                expected[p]=expected[p-1];metadata[p]=metadata[p-1];
                black[p]=black[p-1];check_rgb[p]=check_rgb[p-1];
            end
            metadata[0]={hs,vs,de,x,y};check_rgb[0]=1;black[0]=(level==0);
            target=(!de || !displayed || level==0)?0:
                {adjusted_channel(background[23:16]),adjusted_channel(background[15:8]),adjusted_channel(background[7:0])};
            index=(x>=408 && x<624)?x-408:0;
            target=ref_music_pixel(x,y,de,(frames==0 || !((frames-1)&8)),expected_music,
                old_published,old_published?bank_data[db*256+index]:0,target);
            target=ref_subtitle_plate(x,y,de,(frames==0 || !((frames-1)&4)),target);
            if(frames==0 || !((frames-1)&4))target=ref_compact_subtitle(x,y,de,frames,2,2,target);
            target=ref_showcase_ui(x,y,de,displayed,image,1,(frames>0)?((frames-1)%4):0,
                (frames>0)?((frames-1)%16):0,brightness,contrast,level,
                expected_music,(notice_left>0),expected_notice_image,(hint_left>0),hint_type,target);
            expected[0]=target;
            if(audio_valid)begin
                pcm_events++;
                if(frames>=9 && frames<=16)hidden_pcm++;
                if(skip<2)skip++;
                else if(!pending)begin bank_data[wb*256+collected]=quantize(left_pcm);collected++;if(collected==256)pending=1;end
            end
            if(boundary && old_pending)begin
                if(de)$fatal(1,"new audio snapshot frame event in active video");
                db=wb;wb=1-wb;collected=0;pending=0;published=1;windows++;
            end
            #0.1;
            if(snapshot_commit!==(old_boundary && old_pending))$fatal(1,"audio snapshot tore in full raster");
            if(pipeline_valid<6)pipeline_valid++;
            else begin
                cycle++;
                if({sh,sv,sd,sx,sy}!==metadata[4])$fatal(1,"music broke video pipeline alignment");
                if(!sd && rgb!==0)$fatal(1,"invalid DE generated nonblack output");
                if($test$plusargs("INJECT_VIS_HIDDEN") && frames==10 && sd && sx==500 && sy==430)
                    force layers.music.visible_d=1'b1;
                if(check_rgb[4] && rgb!==expected[4])begin
                    $display("SHOWCASE_CHECKER_REJECT VIS_HIDDEN frame=%0d x=%0d y=%0d got=%h expected=%h",frames,sx,sy,rgb,expected[4]);
                    $fatal(1,"layer bypass, text, or adjusted background pixel mismatch");
                end
                if(sd)begin
                    if(preview_file!=0 && complete_frames==2)
                        $fwrite(preview_file,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
                    if(sx!==frame_pixels%640 || sy!==frame_pixels/640)$fatal(1,"lost/repeated active video pixel");
                    frame_pixels++;pixels++;
                    if(rgb==24'h00FF80)begin
                        green++;if(black[4])black_green++;
                        if(frames>=17)restored_green++;
                    end
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
        // Four more complete frames restore BOTH visibility switches after
        // the hidden interval and revisit IMG01 with fresh real PCM/state.
        wait(complete_frames>=21);@(negedge clk);
        if(preview_file!=0)$fclose(preview_file);
        if(starts!=5 || windows<6 || pcm_events<5000 || green<1000 ||
           black_green<100 || restored_green<1000 || hidden_pcm<5000 || hchecks<10000 || vchecks<19)
            $fatal(1,"insufficient music/video visibility recovery coverage");
        $display("SHOWCASE_VIDEO_TEST_PASS frames=%0d pixels=%0d song_starts=%0d PCM=%0d snapshots=%0d green=%0d black_green=%0d restored_green=%0d hidden_PCM=%0d",
                 complete_frames,pixels,starts,pcm_events,windows,green,black_green,restored_green,hidden_pcm);$finish;
    end
    initial begin #420000000;$fatal(1,"presentation full-raster timeout");end
endmodule




