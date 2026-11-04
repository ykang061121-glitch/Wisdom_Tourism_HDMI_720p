`timescale 1ns/1ps
module tb_subtitle_composition;
    reg clk=0,reset=1,req_d=0,wave_frame_boundary=0;
    wire req,hs0,vs0,de0,read_en;
    wire hs,vs,de,wh,wv,wd,sh,sv,sd;
    wire [9:0] x,y,wx,wy,sx,sy,scroll_offset;
    wire [1:0] message,group_number;
    wire [23:0] from_memory,adjusted,faded,wave,subtitle,osd,probe;
    wire [7:0] read_index;
    wire signed [7:0] amplitude;
    wire sample_valid,snapshot_valid,commit;
    wire boundary=req && !req_d;
    integer frames=0,aligned_frames=0,sample_number=0;
    reg [9:0] audio_count=0;
    wire audio_valid=(frames>=2 && frames<5 && audio_count==520);
    wire signed [23:0] pcm=((sample_number%91)-45)*65536;
    wire [23:0] bg=from_memory ^ {x[7:0],y[7:0],8'h5A};
    wire display_valid=(frames>0);
    reg [2:0] fade_level;
    always @* begin
        case(frames)
            2:fade_level=3;3:fade_level=2;4:fade_level=1;
            5,6:fade_level=0;default:fade_level=4;
        endcase
    end
    wire [23:0] gated=display_valid?faded:24'd0;
    always #20 clk=~clk;
    `include "subtitle_reference.vh"
    video_timing_data timing(.video_clk(clk),.rst(reset),.read_req(req),.read_req_ack(1'b1),.hs(hs0),.vs(vs0),.de(de0));
    video_delay delay(.video_clk(clk),.rst(reset),.read_en(read_en),.read_data(24'h234567),
        .hs(hs0),.vs(vs0),.de(de0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(from_memory));
    video_active_position position(.pixel_clk(clk),.reset(reset),.vs(vs),.de(de),.x(x),.y(y));
    always @(posedge clk) begin
        if(reset) begin req_d<=0;wave_frame_boundary<=0;audio_count<=0;sample_number<=0;end
        else begin
            req_d<=req;wave_frame_boundary<=boundary;
            audio_count<=(audio_count==520)?0:audio_count+1;
            if(audio_valid) sample_number<=sample_number+1;
        end
    end
    video_adjust adjust(.pixel_clk(clk),.reset(reset),.de(de),.rgb_in(bg),.brightness(8'sd16),.contrast(2'd1),.rgb_out(adjusted));
    video_fade fade(.pixel_clk(clk),.reset(reset),.de(de),.rgb_in(adjusted),.fade_level(fade_level),.rgb_out(faded));
    audio_wave_capture capture(.pixel_clk(clk),.reset(reset),.audio_valid(audio_valid),.audio_left(pcm),
        .frame_boundary(boundary),.video_de(de),.read_index(read_index),.read_amplitude(amplitude),
        .read_valid(sample_valid),.snapshot_valid(snapshot_valid),.snapshot_commit(commit));
    audio_wave_overlay wave_layer(.pixel_clk(clk),.reset(reset),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),
        .background_rgb(gated),.sample_amplitude(amplitude),.sample_valid(sample_valid),.sample_index(read_index),
        .out_hs(wh),.out_vs(wv),.out_de(wd),.out_x(wx),.out_y(wy),.wave_rgb(wave));
    // Accelerated GROUP_FRAMES=2 covers every complete raster for all groups;
    // the separate unit test checks the actual default 180-frame schedule.
    dynamic_subtitle_overlay #(.GROUP_FRAMES(2)) subtitles(
        .pixel_clk(clk),.reset(reset),.frame_boundary(wave_frame_boundary),.hs(wh),.vs(wv),.de(wd),
        .x(wx),.y(wy),.background_rgb(wave),.out_hs(sh),.out_vs(sv),.out_de(sd),.out_x(sx),.out_y(sy),
        .subtitle_rgb(subtitle),.scroll_offset(scroll_offset),.scroll_message(message),.subtitle_group(group_number));
    osd_overlay status_text(.pixel_clk(clk),.reset(reset),.de(sd),.x(sx),.y(sy),.background_rgb(subtitle),
        .image_index(2'd1),.auto_play_enable(1'b1),.display_valid(display_valid),
        .brightness(8'sd16),.contrast(2'd1),.fade_level(fade_level),.osd_rgb(osd));
    // Test-only overlap probe: original OSD stays highest even if placed over
    // the fixed subtitle line. Formal OSD_Y remains 16, untouched.
    osd_overlay #(.OSD_Y(250)) overlap_probe(.pixel_clk(clk),.reset(reset),.de(sd),.x(sx),.y(sy),
        .background_rgb(subtitle),.image_index(2'd1),.auto_play_enable(1'b1),.display_valid(1'b1),
        .brightness(8'sd16),.contrast(2'd1),.fade_level(fade_level),.osd_rgb(probe));

    function automatic [7:0] ref_channel(input integer original,level);
        integer adjusted_value;
        begin
            adjusted_value=(original+16>255)?255:original+16;
            case(level)
                4:ref_channel=adjusted_value;
                3:ref_channel=adjusted_value-adjusted_value/4;
                2:ref_channel=adjusted_value/2;
                1:ref_channel=adjusted_value/4;
                default:ref_channel=0;
            endcase
        end
    endfunction
    function automatic [23:0] ref_osd(input integer px,py,active,valid,level,input [23:0] background);
        string text_value;
        integer row_number,char_number,column,local_y;
        begin
            ref_osd=active?background:0;text_value="";row_number=0;
            char_number=(px-16)/8;column=(px-16)%8;local_y=py-16;
            if(valid==0) begin
                if(local_y>=0 && local_y<16) text_value="LOADING";
            end else begin
                if(local_y>=0 && local_y<16) text_value="ANLOGIC FPGA";
                else if(local_y>=20 && local_y<36) begin text_value="IMG:02";local_y=local_y-20;end
                else if(local_y>=40 && local_y<56) begin text_value="AUTO:ON";local_y=local_y-40;end
                else if(local_y>=60 && local_y<76) begin text_value="BRI:+16";local_y=local_y-60;end
                else if(local_y>=80 && local_y<96) begin text_value="CON:100";local_y=local_y-80;end
                else if(local_y>=100 && local_y<116) begin
                    case(level)
                        0:text_value="FADE:000";1:text_value="FADE:025";2:text_value="FADE:050";
                        3:text_value="FADE:075";default:text_value="FADE:100";
                    endcase
                    local_y=local_y-100;
                end
            end
            if(active && px>=16 && px<112 && char_number<text_value.len() &&
               ref_dot(text_value[char_number],local_y/2,column)) ref_osd=24'hFFFFFF;
        end
    endfunction

    integer banks[0:511],collected=0,skipped=0,wb=0,db=1,last_audio_frame=-10;
    reg held=0,published=0,old_held,old_published,monitor_enable=0;
    integer old_db,ri,ty,value;
    reg [23:0] expected[0:2];
    reg [22:0] metadata[0:2];
    reg [23:0] background_reference,wave_reference,subtitle_reference;
    integer cycles=0,checked_pixels=0,output_frames=0,frame_pixels=0;
    integer hs_start=0,vs_start=0,hs_low=0,vs_low=0,line_pixels=0;
    reg last_hs=1,last_vs=1,last_de=0,seen_hs=0,seen_vs=0,track_hs_low=0,track_vs_low=0;
    integer commits=0,overlap_checks=0,black_text_checks=0,no_audio_frames=0,audio_frames=0;
    integer pipeline_valid=0;

    always @(posedge clk) if(!reset && monitor_enable) begin
        old_held=held;old_published=published;old_db=db;
        expected[2]=expected[1];expected[1]=expected[0];
        metadata[2]=metadata[1];metadata[1]=metadata[0];metadata[0]={hs,vs,de,x,y};
        background_reference=(!de || !display_valid)?0:
            {ref_channel(bg[23:16],fade_level),ref_channel(bg[15:8],fade_level),ref_channel(bg[7:0],fade_level)};
        wave_reference=background_reference;
        if(de && x>=16 && x<=623 && y>=330 && y<=455) begin
            wave_reference=24'h18202A;
            if(x==16 || x==623 || y==330 || y==455) wave_reference=24'h608090;
            else begin
                if(y==392) wave_reference=24'h405060;
                if(old_published && x>=64 && x<=575) begin
                    ri=(x-64)/2;ty=392-banks[old_db*256+ri];
                    if(y>=ty-1 && y<=ty+1) wave_reference=24'h00FF80;
                end
            end
        end
        subtitle_reference=ref_subtitle(x,y,de,frames,2,2,wave_reference);
        expected[0]=ref_osd(x,y,de,display_valid,fade_level,subtitle_reference);
        if(audio_valid) begin
            last_audio_frame=frames;
            if(skipped<2) skipped=skipped+1;
            else if(!held) begin
                banks[wb*256+collected]=(sample_number%91)-45;
                collected=collected+1;if(collected==256) held=1;
            end
        end
        if(boundary) begin
            if(de) $fatal(1,"raw frame event not blanking");
            if(old_held) begin db=wb;wb=1-wb;collected=0;held=0;published=1;commits=commits+1;end
            if(frames-last_audio_frame>=2) begin published=0;held=0;collected=0;skipped=0;end
            frames=frames+1;
        end
        if(wave_frame_boundary) begin
            if(wd) $fatal(1,"subtitle event not aligned to blanking");
            aligned_frames=aligned_frames+1;
        end
        #1;
        if(scroll_offset!==ref_scroll_offset(aligned_frames,2) || message!==ref_scroll_message(aligned_frames,2) ||
           group_number!==(aligned_frames/2)%3) $fatal(1,"real frame subtitle schedule mismatch");
        if(pipeline_valid>=2) begin
            if({sh,sv,sd,sx,sy}!==metadata[2] || osd!==expected[2])
                $fatal(1,"composition pixel/metadata mismatch x=%0d y=%0d observed=%h expected=%h",sx,sy,osd,expected[2]);
            cycles=cycles+1;
            if(last_hs && !sh) begin
                if(seen_hs && cycles-hs_start!=800) $fatal(1,"line total changed");
                seen_hs=1;hs_start=cycles;hs_low=0;track_hs_low=1;
            end
            if(!sh && track_hs_low) hs_low=hs_low+1;
            if(sh && !last_hs && track_hs_low) begin
                if(hs_low!=96) $fatal(1,"HSYNC width/polarity changed");track_hs_low=0;
            end
            if(last_vs && !sv) begin
                if(seen_vs && cycles-vs_start!=420000) $fatal(1,"525-line frame total changed");
                if(frame_pixels!=307200) $fatal(1,"active frame count %0d",frame_pixels);
                output_frames=output_frames+1;frame_pixels=0;
                seen_vs=1;vs_start=cycles;vs_low=0;track_vs_low=1;
                if(published) audio_frames=audio_frames+1;else no_audio_frames=no_audio_frames+1;
            end
            if(!sv && track_vs_low) vs_low=vs_low+1;
            if(sv && !last_vs && track_vs_low) begin
                if(vs_low!=1600) $fatal(1,"VSYNC width/polarity changed");track_vs_low=0;
            end
            if(sd) begin frame_pixels=frame_pixels+1;checked_pixels=checked_pixels+1;line_pixels=line_pixels+1;end
            if(last_de && !sd) begin if(line_pixels!=640) $fatal(1,"line active count changed");line_pixels=0;end
            if(sd && sx==19 && sy==250) begin
                if(probe!==24'hFFFFFF) $fatal(1,"OSD priority over subtitles lost");
                overlap_checks=overlap_checks+1;
            end
            if(sd && fade_level==0 && osd==24'hFFCC40) black_text_checks=black_text_checks+1;
            last_hs=sh;last_vs=sv;last_de=sd;
        end else begin
            // Prime edge history from the actual startup blanking level.
            // Initial VS is already low: do not fabricate a falling edge.
            last_hs=sh;last_vs=sv;last_de=sd;
        end
        pipeline_valid=pipeline_valid+1;
    end
    initial begin
        repeat(8) @(negedge clk);reset=0;
        repeat(40) @(negedge clk);monitor_enable=1;
        wait(output_frames==8);@(negedge clk);
        if(checked_pixels!=2457600 || overlap_checks<8 || black_text_checks==0 ||
           audio_frames==0 || no_audio_frames==0 || commits<2 || snapshot_valid!==0)
            $fatal(1,"composition coverage insufficient or missing-PCM not invalidated");
        $display("SUBTITLE_COMPOSITION_TEST_PASS full_frames=%0d active_pixels=%0d window_commits=%0d overlap_checks=%0d black_text_pixels=%0d real_800x525_timing audio_and_no_audio",output_frames,checked_pixels,commits,overlap_checks,black_text_checks);
        $finish;
    end
    initial begin #160000000;$fatal(1,"composition timeout");end
endmodule
