`timescale 1ns/1ps
// Full 800x525 rasters through the real five-clock presentation pipeline.
// SD/timer/guard/transition are the same real RTL fixture as the phase tests.
// Only CMD17 bytes and completed memory bursts are controlled models.
module tb_osd_progress_polish;
    wire unused;
    progress_commit_case #(.RUN_AUTOMATIC_CASE(0)) core(unused);
    wire clk=core.vclk,reset=core.reset;
    reg mclk=0;always #40.666667 mclk=~mclk;
    reg de=0,hs=1,vs=1;reg [9:0] x=0,y=0;
    reg [23:0] photos[0:1228799];string path;
    integer n,p;
    initial begin
        if($value$plusargs("BACKGROUND_HEX=%s",path))$readmemh(path,photos);
        else if($test$plusargs("WRITE_POLISH_FRAMES"))$fatal(1,"real BMP fixtures required");
        else for(n=0;n<4;n++)for(p=0;p<307200;p++)
            photos[n*307200+p]=(n==2)?24'hFFFFFF:(n==3)?24'hE4EFF2:{8'(p%251),8'(n*51),8'((p/640)%255)};
    end
    wire [23:0] background=photos[core.image*307200+y*640+x];
    wire [23:0] adjusted,masked,ui,rgb;
    wire [1:0] effect;wire [3:0] reveal;
    video_adjust adjust(.pixel_clk(clk),.reset(reset),.de(de),.rgb_in(background),
        .brightness(8'sd0),.contrast(2'd1),.rgb_out(adjusted));
    picture_transition picture(.pixel_clk(clk),.reset(reset),.frame_boundary(core.frame),.de(de),.x(x),.y(y),
        .rgb_in(adjusted),.fade_level(core.level),.transition_state(core.state),
        .pending_image_index(core.payload[3:2]),.scene_commit(core.commit),.display_valid(core.valid),
        .rgb_out(masked),.effect_mode(effect),.reveal_step(reveal));
    wire su,sv,active_valid,song,bclk,lrclk,dout,pcm_valid;
    wire [1:0] song_index,active_image;wire [23:0] left_pcm,right_pcm;
    wire [9:0] audio_status,video_status;
    image_audio_cdc audio_selection(.video_clk(clk),.video_reset(reset),.display_valid(core.valid),.display_image(core.image),
        .audio_clk(mclk),.audio_reset(reset),.selection_update(su),.selection_valid(sv),.selection_image(song_index));
    image_melody_i2s audio(.I_mclk(mclk),.I_rst(reset),.selection_update(su),.selection_valid(sv),.selection_image(song_index),
        .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrclk),.O_i2s_DOUT(dout),.active_valid(active_valid),.active_image(active_image),
        .song_start(song),.playback_status(audio_status));
    I2S_receiver receiver(.I_clk(clk),.I_rst(reset),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrclk),.I_i2s_DOUT(dout),
        .O_audio_valid(pcm_valid),.O_audio_left_data(left_pcm),.O_audio_right_data(right_pcm));
    melody_status_cdc audio_snapshot(.audio_clk(mclk),.video_clk(clk),.reset(reset),.audio_status(audio_status),.video_status(video_status));
    wire [7:0] sample_index;wire signed [7:0] amplitude;wire sample_valid;
    audio_wave_capture capture(.pixel_clk(clk),.reset(reset),.audio_valid(pcm_valid),.audio_left(left_pcm),
        .frame_boundary(core.frame),.video_de(de),.read_index(sample_index),.read_amplitude(amplitude),.read_valid(sample_valid),
        .snapshot_valid(),.snapshot_commit());
    // This is the same bundled status transfer as the top-level OSD.
    wire [2:0] setting_snapshot;
    reg [2:0] settings=2;
    osd_status_cdc #(.WIDTH(3)) settings_mailbox(.src_clk(core.clk),.src_reset(reset),
        .src_status({core.auto_mode,core.period}),.dst_clk(clk),.dst_reset(reset),.dst_status(setting_snapshot));
    always @(posedge clk)if(reset)settings<=2;else if(core.frame)settings<=setting_snapshot;
    wire oh,ov,od;wire [9:0] ox,oy;
    showcase_presentation layers(.pixel_clk(clk),.reset(reset),.frame_boundary(core.frame),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),
        .background_rgb(core.valid?masked:24'd0),.subtitles_visible(1'b1),.visual_visible(1'b1),
        .sample_amplitude(amplitude),.sample_valid(sample_valid),.sample_index(sample_index),.audio_status(video_status),
        .display_commit(core.commit),.display_valid(core.valid),.image_index(core.image),.auto_play_enable(settings[2]),
        .interval_code(settings[1:0]),.preset_mode(2'd0),.brightness(8'sd0),.contrast(2'd1),.fade_level(core.level),
        .error_status(core.error),.out_hs(oh),.out_vs(ov),.out_de(od),.out_x(ox),.out_y(oy),.output_rgb(ui));
    playback_progress_overlay bar(.reset(reset),.de(od),.x(ox),.y(oy),.visible(core.bar_visible),
        .progress_units(core.bar_units),.background_rgb(ui),.output_rgb(rgb));
    `include "showcase_reference.vh"
    reg [22:0] metadata[0:4];reg [23:0] expected_top[0:4],expected_bg[0:4];
    integer pipe=0,checks=0,top_checks=0,bar_checks=0,frame_pixels=0,frames=0,fd=0;
    integer capture_units;reg capture_visible;
    reg [23:0] plain,expected;
    always @(posedge clk)begin
        if(reset)pipe=0;
        else begin
            for(integer j=4;j>0;j--)begin metadata[j]=metadata[j-1];expected_top[j]=expected_top[j-1];expected_bg[j]=expected_bg[j-1];end
            metadata[0]={hs,vs,de,x,y};plain=background;
            if(effect==0)case(core.level)
                3:plain={background[23:16]-(background[23:16]>>2),background[15:8]-(background[15:8]>>2),background[7:0]-(background[7:0]>>2)};
                2:plain={1'b0,background[23:17],1'b0,background[15:9],1'b0,background[7:1]};
                1:plain={2'b0,background[23:18],2'b0,background[15:10],2'b0,background[7:2]};
                0:plain=0;default:plain=background;
            endcase
            else if(effect==1 && x>=reveal*80)plain=0;
            if(!de || !core.valid || core.level==0)plain=0;
            expected_bg[0]=plain;
            expected_top[0]=ref_showcase_ui(x,y,de,core.valid,core.image,settings[2],settings[1:0],0,
                0,1,core.level,0,0,0,0,0,plain);
            #0.1;
            if(pipe<6)pipe++;
            else begin
                if({oh,ov,od,ox,oy}!==metadata[4])$fatal(1,"polish five-clock RGB/HS/VS/DE/XY alignment");
                if(!od && rgb!==0)$fatal(1,"nonblack blanking");
                if(od)begin
                    if(oy>=8 && oy<=39)begin top_checks++;if(rgb!==expected_top[4])$fatal(1,"colored transparent top mismatch x=%0d y=%0d got=%h expected=%h",ox,oy,rgb,expected_top[4]);end
                    if(oy>=84 && oy<=365 && rgb!==expected_bg[4])$fatal(1,"picture center changed or torn");
                    expected=(core.bar_visible && oy>=475 && oy<=477 && ox>=16 && ox<624 &&
                        ox-16<(core.bar_units*608)/256)?24'h38E8DC:ui;
                    if(rgb!==expected)$fatal(1,"bar coverage mismatch");
                    if(oy>=475 && oy<=477)bar_checks++;
                    if(core.bar_units!=capture_units || core.bar_visible!=capture_visible)$fatal(1,"bar changed during active raster");
                    if(fd!=0)$fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
                    checks++;frame_pixels++;
                end
            end
        end
    end
    task raster(input string name);
        integer px,py;
        begin frame_pixels=0;capture_units=core.bar_units;capture_visible=core.bar_visible;
            if($test$plusargs("WRITE_POLISH_FRAMES"))fd=$fopen({name,".rgb"},"wb");
            for(py=0;py<525;py++)for(px=0;px<800;px++)begin
                @(negedge clk);hs=!(px>=656 && px<752);vs=!(py>=490 && py<492);
                de=px<640 && py<480;x=px<640?px:0;y=py<480?py:0;
            end
            @(negedge clk);de=0;repeat(8)@(negedge clk);
            if(frame_pixels!=307200)$fatal(1,"incomplete full frame");
            if(fd!=0)begin $fclose(fd);fd=0;end
            frames++;
            $display("POLISH_RTL_FRAME %s scene=%0d state=%0d fade=%0d units=%0d visible=%0d pixels=%0d",name,core.image,core.state,core.level,core.bar_units,core.bar_visible,frame_pixels);
        end
    endtask
    initial begin
        core.sd_ticks(12);core.reset=0;core.settled(0);raster("01_forest_colored_top");
        core.next_key;core.settled(1);raster("02_mountain_colored_top");
        core.next_key;core.settled(2);raster("03_rose_white_colored_top");
        core.next_key;core.settled(3);raster("04_logo_white_colored_top");
        core.hold_fetch=1;core.mode_key;
        wait(core.raw_progress[8:0]>=64);repeat(2)core.advance;raster("05_auto_growth");
        wait(core.ticks>0);wait(core.source.load_busy);core.sd_ticks(80);repeat(2)core.advance;
        core.assert_full;raster("06_expired_loading_full");
        core.hold_fetch=0;core.wait_ready;
        repeat(4)core.advance;core.assert_full;raster("07_fade_out_full");
        while(core.state!=3)core.advance;
        core.assert_full;raster("08_black_before_commit_full");
        core.advance;core.assert_full;raster("09_black_committed_full");
        core.advance;core.assert_full;core.advance;
        if(core.bar_units!=0 || core.level==0)$fatal(1,"first new pixels not paired with zero bar");
        raster("10_first_new_pixels_zero");
        if(checks!=3072000 || top_checks<200000 || bar_checks<15000)$fatal(1,"missing raster coverage");
        $display("OSD_PROGRESS_POLISH_TEST_PASS frames=%0d pixels=%0d top=%0d bar=%0d",frames,checks,top_checks,bar_checks);$finish;
    end
    initial begin #500000000;$fatal(1,"polish full-frame watchdog");end
endmodule
