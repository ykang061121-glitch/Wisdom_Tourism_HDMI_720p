`timescale 1ns/1ps
// Real scan/parser/scaler/completion/key/mode/fade/audio/receiver/wave RTL.
// Only CMD17 bytes and SDRAM storage completion are controlled fixtures.
module image_audio_link_case #(parameter PHASE=0)(output reg done=0);
    reg sd_clk=0,video_clk=0,mclk=0,reset=1,k2=1,k4=1;
    always #5 sd_clk=~sd_clk;
    always #20 video_clk=~video_clk;
    initial begin #(PHASE);forever #40.666667 mclk=~mclk;end
    wire req,we,sd_valid,auto_mode;
    reg ack=0,finish_toggle=0;
    wire [31:0] data;
    wire [1:0] write_bank,pending_bank,pending_image,sd_image;
    wire rt,nt,ct,commit_sd,done_sd,rq_video,ready_video,cancel_video;
    wire [3:0] payload;
    wire [1:0] display_bank,display_image;
    wire display_valid,busy,commit_video,done_video;
    wire [2:0] fade,state;
    integer frame_count=0,pixels=0,memory_wait=-1,swaps=0,starts=0;
    wire boundary=(frame_count==9999); // accelerated blanking frame event
    reg prior_req=0,pre_frame;
    reg [2:0] pre_state;
    wire sel_update,sel_valid,active,song_start,bclk,lrclk,dout,pcm_valid;
    wire [1:0] sel_image,active_image;
    wire [23:0] left_pcm,right_pcm;
    wire signed [7:0] amplitude;
    wire sample_valid,snapshot_valid,wave_commit;
    reg [7:0] read_index=0;
    sd_card_bmp #(.CLK_FREQ_HZ(1000000),.SCAN_MAX_SECTOR(3),
        .SCAN_TARGET_COUNT(4),.TEST_ALLOW_SIZE(1),.OUTPUT_WIDTH(4),.OUTPUT_HEIGHT(2)) source(
        .clk(sd_clk),.rst(reset),.cancel(1'b0),.key_next(k2),.key_auto(k4),.key_interval(1'b1),
        .bmp_width(16'd4),.bmp_height(16'd2),.write_finish_toggle(finish_toggle),
        .display_swap_commit_pulse(commit_sd),.transition_done_pulse(done_sd),
        .write_buf_idx(write_bank),.pending_buf_idx(pending_bank),.pending_image_idx(pending_image),
        .transition_request_toggle(rt),.next_frame_ready_toggle(nt),.transition_cancel_toggle(ct),
        .write_req(req),.write_req_ack(ack),.write_ready(1'b1),.write_en(we),.write_data(data),
        .osd_image_index(sd_image),.osd_auto_play_enable(auto_mode),.display_valid(sd_valid),
        .debug_status_code(),.debug_image_number(),.debug_image_valid(),.state_code(),
        .SD_MISO(1'b1),.SD_nCS(),.SD_DCLK(),.SD_MOSI());
    fade_transition_cdc fade_cdc(.src_clk(sd_clk),.src_reset(reset),
        .src_request_toggle(rt),.src_ready_toggle(nt),.src_cancel_toggle(ct),
        .src_pending_payload({pending_image,pending_bank}),
        .src_commit_pulse(commit_sd),.src_transition_done_pulse(done_sd),
        .dst_clk(video_clk),.dst_reset(reset),.dst_request_pulse(rq_video),
        .dst_next_frame_ready(ready_video),.dst_cancel_pulse(cancel_video),
        .dst_pending_payload(payload),.dst_commit_pulse(commit_video),.dst_transition_done_pulse(done_video));
    fade_transition_ctrl #(.FRAMES_PER_STEP(1)) fade_ctrl(
        .video_clk(video_clk),.reset(reset),.frame_start_pulse(boundary),
        .transition_request_pulse(rq_video),.transition_cancel_pulse(cancel_video),
        .next_frame_ready(ready_video),.pending_buf_idx(payload[1:0]),.pending_image_idx(payload[3:2]),
        .display_buf_idx(display_bank),.display_image_idx(display_image),.display_valid(display_valid),
        .fade_level(fade),.transition_busy(busy),.transition_state(state),
        .swap_commit_pulse(commit_video),.transition_done_pulse(done_video));
    image_audio_cdc audio_cdc(.video_clk(video_clk),.video_reset(reset),
        .display_valid(display_valid),.display_image(display_image),.audio_clk(mclk),.audio_reset(reset),
        .selection_update(sel_update),.selection_valid(sel_valid),.selection_image(sel_image));
    image_melody_i2s #(.BASE_NOTE_SAMPLES(16),.RAMP_HOLD_SAMPLES(1),.SILENCE_SAMPLES(4)) tx(
        .I_mclk(mclk),.I_rst(reset),.selection_update(sel_update),.selection_valid(sel_valid),
        .selection_image(sel_image),.O_i2s_BCLK(bclk),.O_i2s_LRCK(lrclk),.O_i2s_DOUT(dout),
        .active_valid(active),.active_image(active_image),.song_start(song_start));
    I2S_receiver receiver(.I_clk(video_clk),.I_rst(reset),.I_i2s_BCLK(bclk),
        .I_i2s_LRCK(lrclk),.I_i2s_DOUT(dout),.O_audio_valid(pcm_valid),
        .O_audio_left_data(left_pcm),.O_audio_right_data(right_pcm));
    audio_wave_capture capture(.pixel_clk(video_clk),.reset(reset),.audio_valid(pcm_valid),
        .audio_left(left_pcm),.frame_boundary(boundary),.video_de(1'b0),.read_index(read_index),
        .read_amplitude(amplitude),.read_valid(sample_valid),
        .snapshot_valid(snapshot_valid),.snapshot_commit(wave_commit));
    always @(posedge sd_clk)begin
        if(reset)begin ack<=0;finish_toggle<=0;prior_req=0;pixels=0;memory_wait=-1;end
        else begin
            ack<=req;
            if(req && !prior_req)begin
                if(source.load_busy && display_valid && write_bank==display_bank)
                    $fatal(1,"audio integration overwrites displayed buffer");
                pixels=0;memory_wait=-1;
            end
            prior_req=req;
            if(we)begin
                if(req || ack || data[31:24]!==8'h80+pending_image || data[23:8]!==16'h4020)
                    $fatal(1,"bad pixel or FIFO data before ACK return-low");
                pixels++;
                if(pixels>8)$fatal(1,"extra output pixel");
                if(pixels==8)memory_wait=47;
            end
            if(memory_wait==0)begin finish_toggle<=~finish_toggle;memory_wait=-1;end
            else if(memory_wait>0)memory_wait--;
        end
    end
    always @(posedge video_clk)begin
        if(reset)begin frame_count<=0;swaps=0;end
        else begin
            frame_count<=boundary?0:frame_count+1;pre_frame=boundary;pre_state=state;
            #0.1;
            if(commit_video)begin
                if(!pre_frame || pre_state!=3 || fade!=0 || pixels!=8 ||
                   !source.source_done_seen || !source.scale_done_seen || !source.memory_done_seen)
                    $fatal(1,"music integration changed black/full-frame commit");
                swaps++;
            end
        end
    end
    reg binding_fault=0;
    always @(negedge mclk)begin
        if($test$plusargs("INJECT_AUDIO_BINDING") && PHASE==0 && sel_update && !binding_fault)begin
            force audio_cdc.selection_image=2'd3;binding_fault=1;
        end
    end
    always @(posedge mclk)begin
        #0.1;
        if(!reset && song_start)begin
            if(!display_valid || active_image!==display_image)begin
                $display("IMAGE_AUDIO_CHECKER_REJECT BINDING image=%0d melody=%0d",display_image,active_image);
                $fatal(1,"music did not follow actual committed image");
            end
            starts++;
        end
    end
    // Independent I2S wire decoder. It does not read TX sample/shift registers.
    reg serial_started=0,previous_lr=0,serial_ready=0;
    reg [63:0] lbits=0,rbits=0;
    reg [23:0] completed_left=0,wire_left=0,wire_right=0;
    integer bclks=0,last_slot=0,last_frame=0,slots=0,serial_frames=0;
    always @(posedge bclk)begin
        if(!reset)begin
            bclks++;
            if(!serial_started)begin serial_started=1;previous_lr=lrclk;last_slot=bclks;end
            else if(lrclk!=previous_lr)begin
                if(slots>0 && bclks-last_slot!=64)$fatal(1,"channel slot changed");
                slots++;last_slot=bclks;
                if(!previous_lr)begin lbits={lbits[62:0],dout};completed_left=lbits[63:40];lbits=0;end
                else begin
                    rbits={rbits[62:0],dout};wire_left=completed_left;wire_right=rbits[63:40];rbits=0;
                    serial_ready=1;
                    if(serial_frames>0 && bclks-last_frame!=128)$fatal(1,"stereo frame changed");
                    serial_frames++;last_frame=bclks;
                end
                previous_lr=lrclk;
            end else if(!lrclk)lbits={lbits[62:0],dout};else rbits={rbits[62:0],dout};
        end
    end
    function integer quantize(input [23:0] bits);
        integer signed_value,q;
        begin
            signed_value=(bits>=24'h800000)?bits-16777216:bits;
            q=(signed_value>=0)?signed_value/65536:-((-signed_value+65535)/65536);
            quantize=(q>45)?45:(q< -45)?-45:q;
        end
    endfunction
    integer banks[0:511],collected=0,skip=0,wb=0,db=1,windows=0,reads=0,pcm_events=0;
    integer old_bank,old_index;
    reg held=0,published=0,old_held,old_published,old_boundary;
    always @(negedge video_clk)read_index=read_index+1;
    always @(posedge video_clk)begin
        if(reset)begin
            collected=0;skip=0;wb=0;db=1;held=0;published=0;
            serial_started=0;previous_lr=0;serial_ready=0;lbits=0;rbits=0;completed_left=0;
            bclks=0;last_slot=0;last_frame=0;slots=0;serial_frames=0;
        end else begin
            old_bank=db;old_index=read_index;old_held=held;old_published=published;old_boundary=boundary;
            if(pcm_valid)begin
                pcm_events++;
                if(skip>=2 && (!serial_ready || left_pcm!==wire_left ||
                   right_pcm!==wire_right || left_pcm!==right_pcm))
                    $fatal(1,"HDMI PCM not equal to transmitted stereo");
                serial_ready=0;
                if(skip<2)skip++;
                else if(!held)begin
                    banks[wb*256+collected]=quantize(left_pcm);
                    collected++;if(collected==256)held=1;
                end
            end
            if(boundary && old_held)begin db=wb;wb=1-wb;collected=0;held=0;published=1;windows++;end
            #0.1;
            if(sample_valid!==old_published)$fatal(1,"wave snapshot validity mismatch");
            if(old_published)begin
                if($signed(amplitude)!==banks[old_bank*256+old_index])
                    $fatal(1,"wave does not reflect real HDMI PCM");
                reads++;
            end
            if(wave_commit!==(old_boundary && old_held))$fatal(1,"wave snapshot not frame atomic");
        end
    end
    task press_next;
        begin @(negedge sd_clk);k2=0;repeat(20050)@(negedge sd_clk);k2=1;repeat(20050)@(negedge sd_clk);end
    endtask
    task press_mode;
        begin @(negedge sd_clk);k4=0;repeat(20050)@(negedge sd_clk);k4=1;repeat(20050)@(negedge sd_clk);end
    endtask
    task settled(input integer wanted);
        begin
            wait(display_valid && display_image==wanted && !busy && !source.load_busy);
            wait(active && active_image==wanted && tx.pcm.envelope==2000000);
            repeat(8)@(negedge video_clk);
        end
    endtask
    task reboot;
        begin
            @(negedge sd_clk);reset=1;k2=1;k4=1;
            repeat(40)@(negedge sd_clk);reset=0;
        end
    endtask
    integer before_swaps,before_starts,i,wanted;
    initial begin
        reboot;settled(0);
        for(i=1;i<4;i++)begin press_next;settled(i);end
        if(swaps!=4 || starts!=4)$fatal(1,"four manual image/melody mappings not one-to-one");
        $display("IMAGE_AUDIO_LINK_MANUAL_PASS phase=%0d images=4 melodies=4",PHASE);
        // Busy next is ignored by the actual existing key/buffer manager.
        before_swaps=swaps;press_next;wait(source.load_busy);press_next;settled(0);
        repeat(125000)@(negedge sd_clk);
        if(swaps!=before_swaps+1 || starts!=5)$fatal(1,"busy key queued an unwanted song/image");
        // Mode toggle alone must neither commit nor restart music.
        before_swaps=swaps;before_starts=starts;
        press_mode;wait(auto_mode);repeat(200000)@(negedge sd_clk);press_mode;wait(!auto_mode);
        if(swaps!=before_swaps || starts!=before_starts)$fatal(1,"mode toggle switched melody");
        press_mode;wait(auto_mode);
        for(i=0;i<4;i++)begin
            wanted=(i+1)%4;wait(swaps==before_swaps+i+1);settled(wanted);
        end
        press_mode;wait(!auto_mode);
        if(swaps!=before_swaps+4 || starts!=before_starts+4)$fatal(1,"auto image/song mismatch");
        $display("IMAGE_AUDIO_LINK_AUTO_PASS phase=%0d switches=4 mode_no_restart busy_ignored",PHASE);
        if(windows<2 || pcm_events<512 || reads<256)$fatal(1,"insufficient actual PCM/wave verification");
        // Reset during a load/fade, not just while idle.
        press_next;wait(source.load_busy);reboot;settled(0);
        if(auto_mode || display_image!=0 || active_image!=0)$fatal(1,"K1 did not reinitialize image/audio");
        $display("IMAGE_AUDIO_LINK_PHASE_PASS phase=%0d pcm_events=%0d windows=%0d reads=%0d reset_during_load",PHASE,pcm_events,windows,reads);
        done=1;
    end
endmodule

// Four physically-contiguous tiny BMP headers for the isolated manager test.
module sd_card_top (
    input clk,rst,SD_MISO,sd_sec_read,sd_sec_write,
    input [31:0] sd_sec_read_addr,sd_sec_write_addr,
    output SD_nCS,SD_DCLK,SD_MOSI,
    output reg sd_init_done=0,
    output reg [7:0] sd_sec_read_data=0,
    output reg sd_sec_read_data_valid=0,sd_sec_read_end=0,
    input [7:0] sd_sec_write_data,
    output sd_sec_write_data_req,sd_sec_write_end
);
    integer pos=0,pace=0,init_count=0;
    reg packet=0;
    reg [31:0] sector;
    assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=0;
    assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
    function [7:0] byte_at(input integer n,input [31:0] s);
        begin
            byte_at=0;
            if(s<4)case(n)
                0:byte_at="B";1:byte_at="M";2:byte_at=78;
                10:byte_at=54;14:byte_at=40;18:byte_at=4;
                22:byte_at=2;26:byte_at=1;28:byte_at=24;
                default:if(n>=54 && n<78)case((n-54)%3)
                    0:byte_at=8'h20;1:byte_at=8'h40;2:byte_at=8'h80+s[7:0];
                endcase
            endcase
        end
    endfunction
    always @(posedge clk)begin
        sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
        if(rst)begin sd_init_done<=0;init_count=0;packet=0;pos=0;pace=0;end
        else begin
            if(init_count<5)init_count++;else sd_init_done<=1;
            if(!packet && sd_sec_read && !sd_sec_read_end)begin
                packet=1;sector=sd_sec_read_addr;pos=0;pace=0;
            end else if(packet)begin
                if(pace==2)begin
                    pace=0;
                    if(pos<512)begin sd_sec_read_data<=byte_at(pos,sector);sd_sec_read_data_valid<=1;pos++;end
                    else begin sd_sec_read_end<=1;packet=0;end
                end else pace++;
            end
        end
    end
endmodule
module tb_image_audio_link;
    wire [1:0] done;
    image_audio_link_case #(.PHASE(0)) c0(done[0]);
    image_audio_link_case #(.PHASE(13)) c1(done[1]);
    initial begin wait(&done);$display("IMAGE_AUDIO_LINK_TEST_PASS actual_keys_scan_scale_black_commit_I2S_PCM_wave");$finish;end
    // Four AUTO dwells now use the specified 5s default (50ms in this 1MHz
    // accelerated fixture), not the removed 1s legacy default. Keep all four
    // image/music and exact commit checks; bound exceeds 4*50ms plus recovery.
    initial begin #350000000;$fatal(1,"image audio link timeout");end
endmodule
