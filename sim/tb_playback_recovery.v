`timescale 1ns/1ps
// Actual parser/scaler/guard, real dual-clock FIFO+reader/writer, transition
// CDC/FSM/effects and melody TX. Only CMD17 byte delivery and SDRAM storage
// are controlled models; this is not SDRAM/SD electrical verification.
module tb_playback_recovery;
    reg clk=0,mem_clk=0,video_clk=0,mclk=0,reset=1,cancel=0,k2=1,k3=1,k4=1;
    always #5 clk=~clk;
    always #4 mem_clk=~mem_clk;
    always #20 video_clk=~video_clk;
    always #40.666667 mclk=~mclk;
    wire req,ack,we,write_ready,sd_display,auto_mode;
    wire [31:0] data;
    wire [7:0] error;
    wire [9:0] progress;
    wire [1:0] sd_image,wb,pb,pi,interval;
    wire rt,nt,ct,commit_sd,done_sd,rq,ready,cx;
    wire [3:0] payload;
    wire [1:0] bank,image;
    wire display_valid,busy,commit,tdone;
    wire [2:0] fade,state;
    reg finish_toggle=0;
    wire finish_mem,wr_en,rd_en,read_ack,read_finish;
    wire [20:0] wr_addr,rd_addr;
    wire [31:0] wr_data,read_data;
    reg read_req=0;
    reg [1:0] response_valid=0;
    reg [31:0] response0=0,response1=0;
    reg [31:0] memory[0:767];
    integer raster=0,swaps=0,starts=0,total_writes=0,frame_writes=0;
    integer partial_aborts=0,recoveries=0,load_count=0,pcm_frames=0;
    wire boundary=(raster==1023);
    reg [2:0] pre_state;
    reg pre_boundary;
    reg previous_req=0;
    reg expected_commit=0;
    reg [1:0] expected_image=0;
    reg [1:0] old_image=0,old_bank=0;
    integer expected_x,expected_y,expected_address;
    reg [31:0] expected_data;
    reg [1:0] effects_seen=0;
    reg [9:0] ax=0;
    wire [23:0] masked;
    wire [1:0] effect;
    wire [3:0] reveal;

    sd_card_bmp #(.CLK_FREQ_HZ(100000),.DEFAULT_INTERVAL_CODE(2),
        .SCAN_START_SECTOR(4),.SCAN_MAX_SECTOR(12),.SCAN_TARGET_COUNT(4),
        .TEST_ALLOW_SIZE(1),.OUTPUT_WIDTH(32),.OUTPUT_HEIGHT(8),.SD_TIMEOUT_CYCLES(4096)) source(
        .clk(clk),.rst(reset),.cancel(cancel),.key_next(k2),.key_auto(k4),.key_interval(k3),
        .osd_interval_code(interval),.playback_progress(progress),.playback_error(error),
        .state_code(),.debug_status_code(),.debug_image_number(),.debug_image_valid(),
        .osd_image_index(sd_image),.osd_auto_play_enable(auto_mode),.bmp_width(16'd32),.bmp_height(16'd8),
        .display_valid(sd_display),.write_finish_toggle(finish_toggle),
        .display_swap_commit_pulse(commit_sd),.transition_done_pulse(done_sd),
        .write_buf_idx(wb),.pending_buf_idx(pb),.pending_image_idx(pi),
        .transition_request_toggle(rt),.next_frame_ready_toggle(nt),.transition_cancel_toggle(ct),
        .write_req(req),.write_req_ack(ack),.write_ready(write_ready),.write_en(we),.write_data(data),
        .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
    frame_read_write #(.BURST_SIZE(16),.FRAME_WIDTH(32),.FRAME_HEIGHT(8)) memio(
        .rst(reset),.mem_clk(mem_clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
        .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(response_valid[1]),.Sdr_rd_dout(response1),
        .read_clk(video_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(read_finish),
        .read_addr_0(21'd0),.read_addr_1(21'd512),.read_addr_2(21'd0),.read_addr_3(21'd512),
        .read_addr_index(bank),.read_len(21'd256),
        .read_en(display_valid && !memio.read_buf.empty_flag),.read_data(read_data),
        .App_wr_en(wr_en),.App_wr_addr(wr_addr),.App_wr_din(wr_data),.App_wr_dm(),
        .write_clk(clk),.write_req(req),.write_req_ack(ack),.write_ready(write_ready),
        .write_finish(finish_mem),.write_addr_0(21'd0),.write_addr_1(21'd512),
        .write_addr_2(21'd0),.write_addr_3(21'd512),.write_addr_index(wb),
        .write_len(21'd256),.write_en(we),.write_data(data));
    fade_transition_cdc crossing(.src_clk(clk),.src_reset(reset),.src_request_toggle(rt),
        .src_ready_toggle(nt),.src_cancel_toggle(ct),.src_pending_payload({pi,pb}),
        .src_commit_pulse(commit_sd),.src_transition_done_pulse(done_sd),
        .dst_clk(video_clk),.dst_reset(reset),.dst_request_pulse(rq),.dst_cancel_pulse(cx),
        .dst_next_frame_ready(ready),.dst_pending_payload(payload),.dst_commit_pulse(commit),
        .dst_transition_done_pulse(tdone));
    fade_transition_ctrl transition(.video_clk(video_clk),.reset(reset),.frame_start_pulse(boundary),
        .transition_request_pulse(rq),.transition_cancel_pulse(cx),.next_frame_ready(ready),
        .pending_buf_idx(payload[1:0]),.pending_image_idx(payload[3:2]),.display_buf_idx(bank),
        .display_image_idx(image),.display_valid(display_valid),.fade_level(fade),
        .transition_busy(busy),.transition_state(state),.swap_commit_pulse(commit),.transition_done_pulse(tdone));
    picture_transition effect_dut(.pixel_clk(video_clk),.reset(reset),.frame_boundary(boundary),
        .de(1'b1),.x(ax),.y(10'd200),.rgb_in(24'hC86432),.fade_level(fade),
        .transition_state(state),.pending_image_index(payload[3:2]),
        .scene_commit(commit),.display_valid(display_valid),
        .rgb_out(masked),.effect_mode(effect),.reveal_step(reveal));
    wire select_update,select_valid,active,song_start,bclk,lrclk,dout;
    wire [1:0] select_image,active_image;
    image_audio_cdc audio_cdc(.video_clk(video_clk),.video_reset(reset),.display_valid(display_valid),
        .display_image(image),.audio_clk(mclk),.audio_reset(reset),
        .selection_update(select_update),.selection_valid(select_valid),.selection_image(select_image));
    image_melody_i2s #(.BASE_NOTE_SAMPLES(16),.RAMP_HOLD_SAMPLES(1),.SILENCE_SAMPLES(4)) music(
        .I_mclk(mclk),.I_rst(reset),.selection_update(select_update),.selection_valid(select_valid),
        .selection_image(select_image),.O_i2s_BCLK(bclk),.O_i2s_LRCK(lrclk),.O_i2s_DOUT(dout),
        .active_valid(active),.active_image(active_image),.song_start(song_start),.playback_status());

    task reject(input [255:0] reason);
        begin $display("RECOVERY_CHECKER_REJECT %0s",reason);$fatal(1,"recovery invariant");end
    endtask
    function [31:0] pixel(input integer slot,input integer x,input integer row);
        begin pixel={8'h80+slot[7:0],8'h30+row[7:0],8'h10+x[7:0],8'h00};end
    endfunction
    // Same-clock memory command model. Real FIFO RTL supplies wr_data and
    // writer addresses; compare EVERY valid write, not just a completion pulse.
    always @(posedge mem_clk)begin
        if(reset)begin
            response_valid<=0;response0<=0;response1<=0;finish_toggle<=0;frame_writes=0;
        end else begin
            response_valid<={response_valid[0],rd_en};
            if(rd_en)begin
                if(rd_addr>767)reject("read address out of range");
                response0<=memory[rd_addr];
            end
            response1<=response0;
            if(memio.write_fifo_aclr)frame_writes=0;
            if(wr_en)begin
                expected_x=frame_writes%32;expected_y=frame_writes/32;
                expected_address=wb*512+(7-expected_y)*32+expected_x;
                expected_data=pixel(pi,expected_x,expected_y);
                if(frame_writes>=256 || wr_addr!==expected_address || wr_data!==expected_data)
                    reject("FIFO RGB/address/order corrupted");
                if(display_valid && wr_addr>=bank*512 && wr_addr<bank*512+256)
                    reject("overwrote valid display bank");
                memory[wr_addr]<=wr_data;frame_writes++;total_writes++;
            end
            if(finish_mem)begin
                if(frame_writes!=256)reject("memory finish before full frame");
                finish_toggle<=~finish_toggle;
            end
        end
    end
    always @(posedge clk)begin
        if(reset)begin previous_req=0;end
        else begin
            if(req && !previous_req)load_count++;
            previous_req=req;
            if(we && (!write_ready || req || ack))reject("write before ACK zero/ready");
            #0.1;
            if(error!=0 && progress!==0)reject("progress grew in error state");
        end
    end
    always @(posedge video_clk)begin
        if(reset)begin raster<=0;read_req<=0;ax<=0;end
        else begin
            raster<=boundary?0:raster+1;ax<=ax==639?0:ax+1;
            if(boundary && display_valid)read_req<=1;
            else if(read_ack)read_req<=0;
            pre_state=state;pre_boundary=boundary;
            #0.1;
            // Mutate the observed commit wire, then run the SAME safety checker.
            if(commit || ($test$plusargs("INJECT_BAD_COMMIT") && error!=0))begin
                if(!expected_commit || image!==expected_image || !pre_boundary || pre_state!=3 ||
                   fade!=0 || masked!=0 || frame_writes!=256 || !source.source_done_seen ||
                   !source.scale_done_seen || !source.memory_done_seen)
                    reject("incomplete/unsafe/unexpected commit");
                swaps++;expected_commit=0;
            end
            if(effect>1)reject("deleted third transition reappeared");
            if(state==2 && reveal<8)effects_seen[effect]=1;
        end
    end
    always @(posedge mclk)begin
        #0.1;
        if(!reset && song_start)begin
            if(!display_valid || active_image!==image)reject("music changed before actual image");
            starts++;
        end
    end
    always @(posedge lrclk)if(!reset)pcm_frames++;

    task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
    task press_next;begin @(negedge clk);k2=0;tick(2020);k2=1;tick(2020);end endtask
    task press_mode;begin @(negedge clk);k4=0;tick(2020);k4=1;tick(2020);end endtask
    task press_interval;begin @(negedge clk);k3=0;tick(2020);k3=1;tick(2020);end endtask
    task pulse_cancel;begin @(negedge clk);cancel=1;tick(1);cancel=0;end endtask
    task allow_image(input integer wanted);
        begin expected_image=wanted;expected_commit=1;end
    endtask
    task settled(input integer wanted);
        integer budget;
        begin
            budget=0;
            while(!(display_valid && image==wanted && !busy && !source.load_busy && sd_image==wanted))begin
                tick(10);budget+=10;if(budget>300000)reject("recovery deadlock / wrong target");
            end
            budget=0;
            while(!(active && active_image==wanted && music.pcm.envelope==2000000))begin
                tick(10);budget+=10;if(budget>300000)reject("melody recovery deadlock");
            end
            if(error!=0)reject("error did not clear after explicit recovery");
            recoveries++;
        end
    endtask
    task wait_error(input [7:0] wanted);
        integer budget,limit;
        begin
            budget=0;
            // Waiting from an AUTO enable includes the selected stable dwell.
            // Keep the original 150000-cycle response bound AFTER that dwell.
            limit=150000;
            if(auto_mode)case(interval)1:limit=limit+300000;3:limit=limit+1000000;default:limit=limit+500000;endcase
            while(error!==wanted)begin
                tick(5);budget+=5;if(budget>limit)reject("missing error / recovery deadlock");
            end
            tick(400);
            if(source.load_busy || busy || progress!=0 || auto_mode ||
               (display_valid && (image!==old_image || bank!==old_bank || sd_image!==old_image)))
                reject("failed load changed image/timer/busy");
        end
    endtask
    task reboot;
        begin
            @(negedge clk);reset=1;cancel=0;k2=1;k3=1;k4=1;
            expected_commit=0;tick(12);reset=0;
        end
    endtask
    task fail_then_retry(input integer slot,input integer fault,input [7:0] wanted);
        integer before_swaps,before_starts,before_loads;
        begin
            old_image=image;old_bank=bank;before_swaps=swaps;before_starts=starts;
            source.sd_card_top_m0.fault_slot=slot;source.sd_card_top_m0.fault=fault;
            press_next;wait_error(wanted);
            before_loads=load_count;tick(30000);
            if(swaps!=before_swaps || starts!=before_starts || load_count!=before_loads)
                reject("automatic retry/skip or wrong song");
            source.sd_card_top_m0.fault=0;
            if($test$plusargs("INJECT_BAD_SKIP"))force source.load_sector=32'd12;
            if($test$plusargs("INJECT_RECOVERY_DEADLOCK"))force source.next_req_pending=0;
            allow_image(slot);press_next;settled(slot);
            $display("RECOVERY_CASE_PASS fault=%0d error=%h target=%0d",fault,wanted,slot);
        end
    endtask
    integer i,before_swaps,before_loads,before_ready;
    integer test_stage=0;
    initial begin
        source.sd_card_top_m0.available=4;source.sd_card_top_m0.fault=1;
        source.sd_card_top_m0.fault_slot=0;
        reboot;old_image=0;old_bank=0;wait_error(8'hE0);
        if(display_valid || active)reject("invalid first image displayed/played");
        source.sd_card_top_m0.fault=0;allow_image(0);press_next;settled(0);
        // Valid initial image survives later corrupt file candidates.
        test_stage=1;fail_then_retry(1,1,8'hE0);
        fail_then_retry(2,2,8'hE1);
        fail_then_retry(3,3,8'hE2);
        fail_then_retry(0,4,8'hE3); // short second data sector, partial SDRAM writes
        partial_aborts++;
        // AUTO failure stops once; changing K3/K4 cannot clear the error or
        // manufacture a request. K2 explicitly retries that SAME cached slot.
        test_stage=2;old_image=image;old_bank=bank;source.sd_card_top_m0.fault_slot=1;
        source.sd_card_top_m0.fault=1;press_interval;press_interval;press_mode;wait_error(8'hE0);
        before_loads=load_count;before_swaps=swaps;press_interval;press_mode;tick(120000);
        if(load_count!=before_loads || swaps!=before_swaps || error!=8'hE0 || progress!=0)
            reject("K3/K4 bypassed latched error");
        press_mode;source.sd_card_top_m0.fault=0;allow_image(1);press_next;settled(1);
        // Cancel a real partial stream; late memory events must not complete it.
        test_stage=3;old_image=image;old_bank=bank;press_next;
        wait(total_writes>0 && source.load_busy && source.scaler.busy && frame_writes>32);
        pulse_cancel;wait_error(8'hEF);partial_aborts++;
        allow_image(2);press_next;settled(2);
        // Same-cycle ready/cancel: no ready toggle may escape.
        test_stage=4;old_image=image;old_bank=bank;before_ready=nt;press_next;
        wait(source.completion_ready);pulse_cancel;wait_error(8'hEF);
        if($test$plusargs("INJECT_READY_CANCEL_RACE"))begin
            if(before_ready==0)force source.next_frame_ready_toggle=1'b1;
            else force source.next_frame_ready_toggle=1'b0;
        end
        if(nt!==before_ready[0])reject("ready published in same cycle as cancel");
        allow_image(3);press_next;settled(3);
        // Once all three events have published ready the transaction is
        // irrevocable. Cancel at OUT, BLACK and IN must finish both mirrors,
        // never strand an SD index while video/audio already switched.
        test_stage=5;for(i=2;i<=4;i=i+1)begin
            allow_image((image+1)%4);press_next;wait(state==i);pulse_cancel;
            // Fault injection at the inactive byte producer AFTER proven EOF:
            // this stale notification cannot revoke an irrevocable full frame.
            if(i==3)begin
                @(negedge clk);force source.load_error=1'b1;tick(2);release source.load_error;
            end
            settled(expected_image);
        end
        source.sd_card_top_m0.fault_slot=(image+1)%4;source.sd_card_top_m0.fault=6;
        allow_image((image+1)%4);press_next;settled(expected_image);
        source.sd_card_top_m0.fault=0;
        // A delayed CMD17 may drain later; no request is allowed before end.
        test_stage=6;old_image=image;old_bank=bank;source.sd_card_top_m0.fault_slot=(image+1)%4;
        source.sd_card_top_m0.fault=5;before_loads=source.sd_card_top_m0.requests;
        press_next;wait_error(8'hE3);tick(1000);
        if(source.bmp_ready || source.sd_card_top_m0.requests!=before_loads+3)
            reject("timeout reused un-drained packet");
        press_next;tick(10000);
        if(source.sd_card_top_m0.requests!=before_loads+3)reject("timeout reissued CMD17");
        source.sd_card_top_m0.release_packet=1;tick(5);source.sd_card_top_m0.release_packet=0;
        wait(source.bmp_ready);source.sd_card_top_m0.fault=0;
        allow_image((image+1)%4);press_next;settled(expected_image);
        // Same persistent timeout with NO eventual end: only global K1 resets
        // the lower transaction. The checker requires finite safe stopping.
        test_stage=7;old_image=image;old_bank=bank;source.sd_card_top_m0.fault_slot=(image+1)%4;
        source.sd_card_top_m0.fault=5;press_next;wait_error(8'hE3);tick(10000);
        if(source.bmp_ready)reject("stuck SPI falsely advertised ready");
        source.sd_card_top_m0.fault=0;reboot;allow_image(0);settled(0);
        // Fewer than four images: compact scan index wraps at actual count.
        source.sd_card_top_m0.available=2;reboot;allow_image(0);settled(0);
        if(source.img_found_count!=2)reject("wrong partial scan count");
        allow_image(1);press_next;settled(1);allow_image(0);press_next;settled(0);
        source.sd_card_top_m0.available=0;reboot;old_image=0;old_bank=0;wait_error(8'hE4);
        before_loads=load_count;press_next;press_mode;tick(30000);
        if(display_valid || active || load_count!=before_loads)reject("empty scan fabricated image");
        source.sd_card_top_m0.available=1;reboot;allow_image(0);settled(0);
        if(source.img_found_count!=1 || effects_seen!=2'b11 || partial_aborts<2 || pcm_frames<20)
            reject("insufficient recovery/effect/PCM coverage");
        // Reset while loading also restores the first known scene/music.
        source.sd_card_top_m0.available=4;reboot;allow_image(0);settled(0);
        press_next;wait(source.load_busy);reboot;allow_image(0);settled(0);
        $display("PLAYBACK_RECOVERY_TEST_PASS commits=%0d songs=%0d writes=%0d recovered=%0d effects=%b PCM=%0d",swaps,starts,total_writes,recoveries,effects_seen,pcm_frames);
        $finish;
    end
    initial begin #50000000;
        $display("RECOVERY_DEBUG stage=%0d image=%0d error=%h busy=%b state=%0d load=%b parser=%0d frame_writes=%0d auto=%b interval=%0d swaps=%0d",test_stage,image,error,busy,state,source.load_busy,source.bmp_read_m0.state,frame_writes,auto_mode,interval,swaps);
        reject("test watchdog / abnormal deadlock");end
endmodule

// Contiguous RAW images: bases 4/6/8/10, two sectors per file, real BMP bytes.
// Faults affect loading ONLY; scan-time header addresses remain independently
// verifiable. No actual low-level SPI/card electrical behavior is claimed.
module sd_card_top(
    input clk,rst,SD_MISO,sd_sec_read,sd_sec_write,
    input [31:0] sd_sec_read_addr,sd_sec_write_addr,
    output SD_nCS,SD_DCLK,SD_MOSI,output reg sd_init_done=0,
    output reg [7:0] sd_sec_read_data=0,
    output reg sd_sec_read_data_valid=0,sd_sec_read_end=0,
    input [7:0] sd_sec_write_data,output sd_sec_write_data_req,sd_sec_write_end);
    integer available=4,fault=0,fault_slot=0,requests=0;
    integer position=0,pace=0,delay_count=0,init_count=0,packet_sector=0;
    integer slot,relative_sector,packet_fault,packet_loading;
    reg packet=0,release_packet=0;
    reg [31:0] seed=32'hBA0123CD;
    assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=0;
    assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
    function [7:0] byte_at(input integer absolute_sector,input integer offset,input integer bad);
        integer p,s,rel,value,row,col;
        begin
            s=(absolute_sector-4)/2;rel=(absolute_sector-4)%2;p=rel*512+offset;
            byte_at=0;
            if(absolute_sector>=4 && s<available && s<4)case(p)
                0:byte_at=bad==1?"X":"B";1:byte_at="M";
                2,3,4,5:begin value=bad==3?821:822;byte_at=value>>((p-2)*8);end
                10:byte_at=54;14:byte_at=40;18:byte_at=bad==2?33:32;
                22:byte_at=8;26:byte_at=1;28:byte_at=24;
                default:if(p>=54 && p<822)begin
                    row=(p-54)/96;col=((p-54)%96)/3;
                    case((p-54)%3)
                        0:byte_at=8'h10+col;1:byte_at=8'h30+row;2:byte_at=8'h80+s;
                    endcase
                end
            endcase
        end
    endfunction
    always @(posedge clk)begin
        sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
        if(rst)begin init_count=0;packet=0;sd_init_done<=0;position=0;requests=0;end
        else begin
            seed={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]};
            if(init_count<8)init_count++;else sd_init_done<=1;
            if(packet && release_packet)begin packet=0;sd_sec_read_end<=1;end
            else if(!packet && sd_sec_read && !sd_sec_read_end)begin
                packet=1;packet_sector=sd_sec_read_addr;position=0;pace=0;
                slot=(packet_sector-4)/2;relative_sector=(packet_sector-4)%2;
                packet_loading=!tb_playback_recovery.source.bmp_read_m0.scan_mode;
                packet_fault=(packet_loading && slot==fault_slot)?fault:0;
                delay_count=packet_fault==6?2200:11;
                requests++;
                if(packet_sector<4 || packet_sector>12 || (packet_loading && slot>3))
                    tb_playback_recovery.reject("guessed/invalid sector request");
                if(packet_loading && slot!==tb_playback_recovery.pi)
                    tb_playback_recovery.reject("request did not use cached target slot");
            end else if(packet)begin
                if(packet_fault==5 && relative_sector==1)begin end
                else if(delay_count>0)delay_count--;
                else if(pace>0)pace--;
                else if(position==((packet_fault==4 && relative_sector==1)?510:512))begin
                    packet=0;sd_sec_read_end<=1;
                end else begin
                    sd_sec_read_data_valid<=1;
                    sd_sec_read_data<=byte_at(packet_sector,position,packet_fault);
                    position++;pace=seed[1:0];
                end
            end
        end
    end
endmodule
