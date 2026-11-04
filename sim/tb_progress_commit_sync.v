`timescale 1ns/1ps
// Real SD manager, timer, BMP/scaler/guard and original transition CDC/FSM.
// Controlled CMD17 bytes and memory completion, no ideal replacement timer.
module progress_commit_case #(parameter VIDEO_PHASE=0, RUN_AUTOMATIC_CASE=1)(output reg finished=0);
    reg clk=0,vclk=0,reset=1,k2=1,k3=1,k4=1,frame=0;
    always #5 clk=~clk;
    initial begin #(VIDEO_PHASE);forever #20 vclk=~vclk;end
    wire req,we,auto_mode,sd_valid,commit_sd,done_sd;
    wire [31:0] data;
    reg ack=0,finish_toggle=0;
    wire [7:0] error;
    wire [9:0] raw_progress;
    wire [1:0] period,sd_image,wb,pb,pi;
    wire rt,nt,ct,vrq,vready,vcancel,commit,tdone,valid,busy;
    wire [3:0] payload;
    wire [2:0] level,state;
    wire [1:0] bank,image,effect;
    wire [3:0] reveal;
    wire [23:0] mask;
    wire bar_visible,onset;
    wire [8:0] bar_units;
    wire [1:0] phase;
    wire raw_read,raw_end,raw_valid,init_done;
    wire [31:0] raw_addr;
    wire [7:0] raw_byte;
    reg hold_fetch=0,bad=0;
    integer swaps=0,onsets=0,ticks=0,pixels=0,mem_wait=-1;
    reg prior_req=0;
    sd_card_bmp #(.CLK_FREQ_HZ(10000),.DEFAULT_INTERVAL_CODE(2),.TEST_ALLOW_SIZE(1),
        .OUTPUT_WIDTH(4),.OUTPUT_HEIGHT(2),.SCAN_MAX_SECTOR(3)) source(
        .clk(clk),.rst(reset),.cancel(1'b0),.key_next(k2),.key_auto(k4),.key_interval(k3),
        .osd_interval_code(period),.playback_progress(raw_progress),.playback_error(error),
        .state_code(),.debug_status_code(),.debug_image_number(),.debug_image_valid(),
        .osd_image_index(sd_image),.osd_auto_play_enable(auto_mode),.bmp_width(16'd4),.bmp_height(16'd2),
        .display_valid(sd_valid),.write_finish_toggle(finish_toggle),
        .display_swap_commit_pulse(commit_sd),.transition_done_pulse(done_sd),
        .write_buf_idx(wb),.pending_buf_idx(pb),.pending_image_idx(pi),.transition_request_toggle(rt),
        .next_frame_ready_toggle(nt),.transition_cancel_toggle(ct),.write_req(req),.write_req_ack(ack),
        .write_ready(1'b1),.write_en(we),.write_data(data),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
    // The real source's card module is a bounded byte fixture below. It uses
    // hierarchical configuration only in simulation, never in synthesis.
    always @* begin source.sd_card_top_m0.hold_fetch=hold_fetch;source.sd_card_top_m0.bad=bad;end
    fade_transition_cdc cdc(.src_clk(clk),.src_reset(reset),.src_request_toggle(rt),
        .src_ready_toggle(nt),.src_cancel_toggle(ct),.src_pending_payload({pi,pb}),
        .src_commit_pulse(commit_sd),.src_transition_done_pulse(done_sd),
        .dst_clk(vclk),.dst_reset(reset),.dst_request_pulse(vrq),.dst_cancel_pulse(vcancel),
        .dst_next_frame_ready(vready),.dst_pending_payload(payload),.dst_commit_pulse(commit),.dst_transition_done_pulse(tdone));
    fade_transition_ctrl ctrl(.video_clk(vclk),.reset(reset),.frame_start_pulse(frame),
        .transition_request_pulse(vrq),.transition_cancel_pulse(vcancel),.next_frame_ready(vready),
        .pending_buf_idx(payload[1:0]),.pending_image_idx(payload[3:2]),.display_buf_idx(bank),
        .display_image_idx(image),.display_valid(valid),.fade_level(level),.transition_busy(busy),
        .transition_state(state),.swap_commit_pulse(commit),.transition_done_pulse(tdone));
    picture_transition picture(.pixel_clk(vclk),.reset(reset),.frame_boundary(frame),.de(1'b1),
        .x(10'd0),.y(10'd0),.rgb_in(24'hC86432),.fade_level(level),.transition_state(state),
        .pending_image_index(payload[3:2]),.scene_commit(commit),.display_valid(valid),
        .rgb_out(mask),.effect_mode(effect),.reveal_step(reveal));
    playback_progress_display display(.src_clk(clk),.src_reset(reset),.src_progress(raw_progress),
        .src_auto(auto_mode),.src_interval(period),.src_error(error),.src_commit_pulse(commit_sd),
        .video_clk(vclk),.video_reset(reset),.frame_boundary(frame),.video_commit(commit),.video_valid(valid),
        .video_busy(busy),.video_fade_level(level),.video_state(state),.visible(bar_visible),
        .display_units(bar_units),.scene_start_pulse(onset),.display_phase(phase));
    task reject(input string reason);
        begin $display("POLISH_CHECKER_REJECT %s",reason);$fatal(1,"progress scene synchronization");end
    endtask
    integer expected_x,expected_y;
    always @(posedge clk)begin
        if(reset)begin ack<=0;finish_toggle<=0;pixels=0;mem_wait=-1;prior_req=0;end
        else begin
            ack<=req;
            if(req&&!prior_req)begin pixels=0;mem_wait=-1;end
            prior_req=req;
            if(we)begin
                if(req || ack || pixels>=8 || data!=={8'h80+{6'd0,pi},16'h4020,8'h00})
                    reject("data/ACK changed by display observer");
                pixels++;if(pixels==8)mem_wait=31;
            end
            if(mem_wait==0)begin finish_toggle<=~finish_toggle;mem_wait=-1;end
            else if(mem_wait>0)mem_wait--;
            if(source.auto_tick)ticks++;
        end
    end
    reg pre_boundary;
    reg [2:0] pre_state;
    reg [10:0] previous_bar;
    reg previous_check;
    always @(posedge vclk)begin
        pre_boundary=frame;pre_state=state;previous_bar={bar_visible,bar_units};previous_check=display.check_frame;
        #0.2;
        if(!reset)begin
            if(!previous_check && {bar_visible,bar_units}!==previous_bar)reject("bar changed outside blanking");
            if(commit)begin
                if(!pre_boundary || pre_state!=3 || level!=0 || mask!=0 || pixels!=8 ||
                   !source.source_done_seen || !source.scale_done_seen || !source.memory_done_seen)
                    reject("original black/complete commit violated");
                swaps++;
            end
            if(onset)begin
                if(!previous_check || !valid || level==0 || mask==0 || bar_units!=0)
                    reject("bar not reset at first actual scene pixels");
                onsets++;
            end
        end
    end
    task sd_ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
    task advance;
        begin @(negedge vclk);frame=1;@(negedge vclk);frame=0;repeat(8)@(negedge vclk);end
    endtask
    task next_key;begin @(negedge clk);k2=0;sd_ticks(220);k2=1;sd_ticks(220);end endtask
    task mode_key;begin @(negedge clk);k4=0;sd_ticks(220);k4=1;sd_ticks(220);end endtask
    task period_key;begin @(negedge clk);k3=0;sd_ticks(220);k3=1;sd_ticks(220);end endtask
    task settled(input integer target);
        integer watchdog;
        begin watchdog=0;
            while(!(valid && image==target && !busy && !source.load_busy))begin
                advance;watchdog++;if(watchdog>10000)reject("settle watchdog");
            end
            repeat(4)advance;
        end
    endtask
    task wait_ready;
        integer watchdog;
        begin watchdog=0;
            while(!source.frame_ready_waiting)begin
                sd_ticks(10);watchdog++;if(watchdog>10000)reject("load watchdog");
            end
            sd_ticks(30);
        end
    endtask
    task assert_full;
        reg [8:0] seen;
        reg seen_visible;
        begin
            seen=bar_units;seen_visible=bar_visible;
            if($test$plusargs("INJECT_HOLD_DROP"))begin seen=0;seen_visible=0;end
            if(!seen_visible || seen!=256)reject("bar disappeared before actual new scene");
        end
    endtask
    reg [15:0] old_packet;
    integer before_onset,before_swap,target,attempt;
    task complete_transfer;
        begin
            target=(image+1)%4;hold_fetch=0;wait_ready;
            attempt=0;
            while(state!=3)begin advance;assert_full;attempt++;if(attempt>20)reject("black phase missing");end
            before_onset=onsets;before_swap=swaps;
            advance;
            if($test$plusargs("INJECT_RESET_AT_COMMIT"))force display.display_units=0;
            if(swaps!=before_swap+1 || image!=target || level!=0)reject("actual commit mismatch");
            assert_full; // a BLACK commit must not end the visual bar lifecycle
            advance;assert_full;
            advance;
            if(onsets!=before_onset+1 || bar_units!=0 || !bar_visible || level==0)
                reject("new scene appeared with previous full bar");
            // Delayed OLD epoch/data must not resurrect a completed dwell.
            force display.mailbox.dst_status=old_packet;
            advance;
            if($test$plusargs("INJECT_STALE_BAR"))force display.display_units=128;
            if(bar_units!=0)reject("old scene progress reappeared after reveal");
            release display.mailbox.dst_status;
            settled(target);
        end
    endtask
    integer selection,selected_code,before_ticks,before_swaps,partial;
    initial if(RUN_AUTOMATIC_CASE) begin
        sd_ticks(12);reset=0;settled(0);
        mode_key;repeat(3)advance;
        for(selection=0;selection<4;selection++)begin
            // Real K3 presses select each code, not forced timer state.
            selected_code=(selection%3)+1; // 3/5/10s plus a repeated 3s epoch
            while(period!=selected_code)period_key;
            repeat(3)advance;hold_fetch=1;before_ticks=ticks;
            wait(ticks==before_ticks+1);wait(source.load_busy);sd_ticks(80);
            repeat(2)advance;assert_full;old_packet=display.snapshot;
            sd_ticks(5000);repeat(3)advance;assert_full;
            if(selection==0)begin period_key;repeat(2)advance;assert_full;end
            complete_transfer;
            $display("PROGRESS_PERIOD_PASS phase=%0d selected=%0d actual_scene=%0d",VIDEO_PHASE,selection,image);
        end
        // Early K2 in AUTO freezes the partial bar, never resets it on request.
        while(raw_progress[8:0]<80)sd_ticks(1);
        advance;partial=bar_units;hold_fetch=1;next_key;repeat(3)advance;
        if(partial==0 || bar_units!=partial || !bar_visible)reject("K2 reset partial dwell before commit");
        // Selecting MANUAL intentionally hides, even when loading is pending.
        mode_key;repeat(3)advance;
        if(bar_visible || bar_units!=0)reject("MANUAL failed to hide progress");
        hold_fetch=0;wait_ready;settled((image+1)%4);
        // A real corrupt header must preserve old image and stop/reset the bar.
        bad=1;hold_fetch=1;mode_key;before_ticks=ticks;
        wait(ticks==before_ticks+1);sd_ticks(80);repeat(2)advance;assert_full;
        before_swaps=swaps;hold_fetch=0;wait(error==8'hE0);repeat(4)advance;
        if(swaps!=before_swaps || bar_visible || bar_units!=0 || auto_mode)
            reject("error recovery progress/commit regression");
        bad=0;target=(image+1)%4;next_key;settled(target);
        mode_key;repeat(3)advance;
        if(!bar_visible || bar_units>8)reject("AUTO restart used previous dwell");
        // Global reset while FULL/loading: no retained expiration or epoch.
        hold_fetch=1;before_ticks=ticks;wait(ticks==before_ticks+1);sd_ticks(80);repeat(2)advance;assert_full;
        @(negedge clk);reset=1;hold_fetch=0;k2=1;k3=1;k4=1;sd_ticks(12);reset=0;settled(0);
        if(bar_visible || bar_units!=0 || auto_mode)reject("reset retained bar state");
        if(swaps<8 || onsets<8)reject("insufficient commit/onset coverage");
        $display("PROGRESS_COMMIT_PHASE_PASS phase=%0d swaps=%0d onsets=%0d ticks=%0d",VIDEO_PHASE,swaps,onsets,ticks);
        finished=1;
    end
    initial if(RUN_AUTOMATIC_CASE) begin #50000000;reject("progress lifecycle watchdog");end
endmodule

module tb_progress_commit_sync;
    wire done;
    progress_commit_case #(.VIDEO_PHASE(0)) test_case(done);
    initial begin wait(done);$display("PROGRESS_COMMIT_SYNC_TEST_PASS");$finish;end
endmodule
module tb_progress_commit_shift;
    wire done;
    progress_commit_case #(.VIDEO_PHASE(13)) test_case(done);
    initial begin wait(done);$display("PROGRESS_COMMIT_SYNC_TEST_PASS shifted");$finish;end
endmodule

module sd_card_top(
    input clk,rst,SD_MISO,sd_sec_read,sd_sec_write,
    input [31:0] sd_sec_read_addr,sd_sec_write_addr,
    output SD_nCS,SD_DCLK,SD_MOSI,output reg sd_init_done=0,
    output reg [7:0] sd_sec_read_data=0,
    output reg sd_sec_read_data_valid=0,sd_sec_read_end=0,
    input [7:0] sd_sec_write_data,output sd_sec_write_data_req,sd_sec_write_end);
    reg hold_fetch=0,bad=0,packet=0,packet_bad=0;
    integer pos=0,pace=0,init_count=0,sector=0;
    assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=0;
    assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
    function [7:0] byte_at(input integer p,input integer s);
        begin byte_at=0;
            if(s<4)case(p)
                0:byte_at=packet_bad?"X":"B";1:byte_at="M";2:byte_at=78;
                10:byte_at=54;14:byte_at=40;18:byte_at=4;22:byte_at=2;
                26:byte_at=1;28:byte_at=24;
                default:if(p>=54 && p<78)case((p-54)%3)
                    0:byte_at=8'h20;1:byte_at=8'h40;2:byte_at=8'h80+s;
                endcase
            endcase
        end
    endfunction
    always @(posedge clk)begin
        sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
        if(rst)begin init_count=0;packet=0;sd_init_done<=0;pos=0;pace=0;end
        else begin
            if(init_count<5)init_count++;else sd_init_done<=1;
            if(!hold_fetch)begin
                if(!packet && sd_sec_read && !sd_sec_read_end)begin
                    packet=1;sector=sd_sec_read_addr;pos=0;pace=0;packet_bad=bad;
                end else if(packet)begin
                    if(pace==2)begin
                        pace=0;
                        if(pos<512)begin sd_sec_read_data<=byte_at(pos,sector);sd_sec_read_data_valid<=1;pos++;end
                        else begin sd_sec_read_end<=1;packet=0;end
                    end else pace++;
                end
            end
        end
    end
endmodule
