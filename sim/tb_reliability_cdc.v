`timescale 1ns/1ps
// Digital reliability stress, not a metastability/MTBF or chip timing model.
module tb_reliability_cdc;
    reg sd_clk=0,video_clk=0,audio_clk=0;
    integer phase=0;
    always #5 sd_clk=~sd_clk;
    initial begin
        if(!$value$plusargs("PHASE=%d",phase))phase=0;
        #(phase); forever #20 video_clk=~video_clk;
    end
    initial begin #3.117; forever #40.667 audio_clk=~audio_clk;end
    reg rst_n=0,pll_lock=0;
    wire reset=~rst_n | ~pll_lock; // Same Boolean source as formal top.
    reg [5:0] source_status=0;
    wire [5:0] video_status;
    osd_status_cdc #(.WIDTH(6)) osd(.src_clk(sd_clk),.src_reset(reset),
        .src_status(source_status),.dst_clk(video_clk),.dst_reset(reset),.dst_status(video_status));
    reg [9:0] audio_status=0;
    wire [9:0] received_status;
    melody_status_cdc metadata(.audio_clk(audio_clk),.video_clk(video_clk),
        .reset(reset),.audio_status(audio_status),.video_status(received_status));
    reg start=0,cancel=0,arm=0,source_done=0,scale_done=0,memory_done=0;
    wire ss,sc,ms,ready;
    frame_completion_guard guard(.clk(sd_clk),.reset(reset),.start(start),.cancel(cancel),
        .memory_arm(arm),.source_done(source_done),.scale_done(scale_done),.memory_done(memory_done),
        .source_seen(ss),.scale_seen(sc),.memory_seen(ms),.ready_pulse(ready));
    reg request_toggle=0,ready_toggle=0,cancel_toggle=0;
    reg [3:0] payload=0;
    wire commit_sd,done_sd,request_video,cancel_video,ready_video;
    wire [3:0] payload_video;
    wire commit_video,done_video;
    fade_transition_cdc bridge(.src_clk(sd_clk),.src_reset(reset),
        .src_request_toggle(request_toggle),.src_ready_toggle(ready_toggle),
        .src_cancel_toggle(cancel_toggle),.src_pending_payload(payload),
        .src_commit_pulse(commit_sd),.src_transition_done_pulse(done_sd),
        .dst_clk(video_clk),.dst_reset(reset),.dst_request_pulse(request_video),
        .dst_cancel_pulse(cancel_video),.dst_next_frame_ready(ready_video),
        .dst_pending_payload(payload_video),.dst_commit_pulse(commit_video),
        .dst_transition_done_pulse(done_video));
    reg frame_boundary=0;
    integer pixel=0;
    // Accelerated blanking frame events. Not a complete 800x525 video raster.
    always @(negedge video_clk)begin
        if(reset)begin pixel=0;frame_boundary=0;end
        else begin frame_boundary=(pixel==36);pixel=(pixel==36)?0:pixel+1;end
    end
    wire [1:0] display_buf,display_image;
    wire display_valid,busy;
    wire [2:0] fade,state;
    fade_transition_ctrl #(.FRAMES_PER_STEP(2)) transition(.video_clk(video_clk),.reset(reset),
        .frame_start_pulse(frame_boundary),.transition_request_pulse(request_video),
        .transition_cancel_pulse(cancel_video),.next_frame_ready(ready_video),
        .pending_buf_idx(payload_video[3:2]),.pending_image_idx(payload_video[1:0]),
        .display_buf_idx(display_buf),.display_image_idx(display_image),.display_valid(display_valid),
        .fade_level(fade),.transition_busy(busy),.transition_state(state),
        .swap_commit_pulse(commit_video),.transition_done_pulse(done_video));
    wire selection_update,selection_valid;
    wire [1:0] selection_image;
    image_audio_cdc selection(.video_clk(video_clk),.video_reset(reset),
        .display_valid(display_valid),.display_image(display_image),.audio_clk(audio_clk),
        .audio_reset(reset),.selection_update(selection_update),.selection_valid(selection_valid),
        .selection_image(selection_image));
    integer published=0,commits=0,acks=0,completed=0,resets=0,cancelled=0;
    reg expected_complete=0;
    reg old_boundary,old_ready;
    reg [2:0] old_fade,old_state;
    reg [1:0] target_image=0,target_buf=0;
    reg [5:0] hold_osd;
    reg [9:0] hold_audio;
    reg check_osd_hold=0,check_audio_hold=0;
    reg fault_injected=0;
    always @(posedge sd_clk)begin
        if(reset)begin ready_toggle<=0;end
        else begin
            if(ready)begin
                if(!expected_complete || !(ss&&sc&&ms))begin
                    $display("RELIABILITY_CHECKER_REJECT EARLY_READY");
                    $fatal(1,"frame published before all three completion events");
                end
                ready_toggle<=~ready_toggle;published=published+1;
            end
            if(commit_sd)acks=acks+1;
            if(done_sd)completed=completed+1;
        end
    end
    always @(posedge video_clk)begin
        old_boundary=frame_boundary;old_ready=ready_video;old_fade=fade;old_state=state;
        #0.1;
        if(!reset && commit_video)begin
            if(!old_boundary || !old_ready || old_fade!=0 || old_state!=3 ||
               display_image!==target_image || display_buf!==target_buf)begin
                $display("RELIABILITY_CHECKER_REJECT UNSAFE_COMMIT");
                $fatal(1,"commit violated black/frame/ready/payload rules");
            end
            commits=commits+1;
        end
        if(!reset && check_osd_hold && video_status!==hold_osd)begin
            $display("RELIABILITY_CHECKER_REJECT TORN_OSD");$fatal(1,"quiescent OSD bundle mismatch");end
        if(!reset && check_audio_hold && received_status!==hold_audio)begin
            $display("RELIABILITY_CHECKER_REJECT TORN_AUDIO");$fatal(1,"quiescent melody bundle mismatch");end
    end
    task pulse(input integer event_id);
        begin @(negedge sd_clk);
            case(event_id)0:start=1;1:arm=1;2:source_done=1;3:scale_done=1;4:memory_done=1;5:cancel=1;endcase
            @(negedge sd_clk);start=0;arm=0;source_done=0;scale_done=0;memory_done=0;cancel=0;
            repeat(3)@(negedge sd_clk);
        end
    endtask
    task common_reset(input bit lose_lock);
        begin
            check_osd_hold=0;check_audio_hold=0;expected_complete=0;
            if(lose_lock)pll_lock=0;else rst_n=0;
            request_toggle=0;cancel_toggle=0;payload=0;source_status=0;audio_status=0;
            start=0;arm=0;source_done=0;scale_done=0;memory_done=0;cancel=0;
            #223.337;
            if(display_valid || busy || ready || selection_valid || video_status || received_status)
                $fatal(1,"common reset did not clear stale transaction/CDC state");
            rst_n=1;pll_lock=1;resets=resets+1;
            repeat(30)@(negedge audio_clk);
            if(display_valid || busy || ready || selection_valid || video_status || received_status)
                $fatal(1,"reset release manufactured an event");
        end
    endtask
    task status_transfer(input integer serial);
        begin
            check_osd_hold=0;check_audio_hold=0;
            // Rapid changes may coalesce; only final stable snapshot is required.
            repeat(7)begin @(negedge sd_clk);source_status=source_status+7;end
            source_status=(serial*13+5)&63;
            @(negedge audio_clk);audio_status=(serial*173+93)&1023;
            repeat(35)@(negedge audio_clk);
            hold_osd=source_status;hold_audio=audio_status;
            check_osd_hold=1;check_audio_hold=1;
            if(!fault_injected && $test$plusargs("INJECT_TORN_CDC"))begin
                force metadata.video_status=10'd0;fault_injected=1;end
            repeat(5)@(negedge video_clk);
        end
    endtask
    task prepare_transition(input integer number,input bit complete_frame);
        begin
            target_image=number%4;target_buf=display_valid ? (display_buf^1) : 0;
            payload={target_buf,target_image};expected_complete=0;pulse(0);
            @(negedge sd_clk);request_toggle=~request_toggle;
            pulse(1);pulse(2);pulse(3);
            if(complete_frame)begin expected_complete=1;pulse(4);end
        end
    endtask
    integer epoch,number,before_commit,before_ready,before_done,order;
    initial begin
        common_reset(0);
        for(epoch=0;epoch<8;epoch=epoch+1)begin
            for(number=0;number<16;number=number+1)begin
                status_transfer(epoch*16+number);
                target_image=number%4;target_buf=display_valid ? (display_buf^1) : 0;
                payload={target_buf,target_image};
                before_commit=commits;before_ready=published;before_done=completed;
                expected_complete=0;pulse(0);
                @(negedge sd_clk);request_toggle=~request_toggle;
                // A stale memory finish before arming must never complete a frame.
                pulse(4);pulse(1);
                order=number%6;
                case(order)
                    0:begin pulse(2);pulse(3);end
                    1:begin pulse(2);pulse(4);end
                    2:begin pulse(3);pulse(2);end
                    3:begin pulse(3);pulse(4);end
                    4:begin pulse(4);pulse(2);end
                    5:begin pulse(4);pulse(3);end
                endcase
                repeat(80)@(negedge video_clk);
                if(commits!=before_commit || published!=before_ready ||
                   (display_valid && fade!=4))$fatal(1,"incomplete frame faded or committed");
                if(number%5==4)begin
                    pulse(5);@(negedge sd_clk);cancel_toggle=~cancel_toggle;
                    pulse(2);pulse(3);pulse(4);repeat(80)@(negedge video_clk);
                    if(commits!=before_commit || published!=before_ready || busy)
                        $fatal(1,"cancel published or retained a transaction");
                    cancelled=cancelled+1;
                end else begin
                    expected_complete=1;
                    if(!fault_injected && $test$plusargs("INJECT_EARLY_READY"))begin
                        force guard.ready_pulse=1'b1;fault_injected=1;expected_complete=0;
                        repeat(2)@(negedge sd_clk);
                    end
                    case(order)0,2:pulse(4);1,4:pulse(3);3,5:pulse(2);endcase
                    wait(completed==before_done+1);
                    repeat(35)@(negedge audio_clk);
                    if(commits!=before_commit+1 || published!=before_ready+1 ||
                       selection_image!==target_image || !selection_valid || fade!=4 || busy)
                        $fatal(1,"completed transition or audio selection mismatch");
                    // Duplicate source notifications must not publish a second frame.
                    pulse(2);pulse(3);pulse(4);repeat(10)@(negedge video_clk);
                    if(commits!=before_commit+1 || published!=before_ready+1)
                        $fatal(1,"duplicate completion generated an extra swap");
                end
            end
            // Reset/lock loss while a transaction and metadata transfer are pending.
            expected_complete=0;pulse(0);pulse(1);pulse(2);
            @(negedge sd_clk);request_toggle=~request_toggle;source_status=~source_status;
            check_osd_hold=0;check_audio_hold=0;audio_status=~audio_status;
            #11.193;common_reset(epoch%2);
        end
        if(commits!=104 || published!=104 || completed!=104 || acks!=104 ||
           cancelled!=24 || resets!=9)$fatal(1,"insufficient reliability scenario coverage");
        // Explicitly abort at each transition stage, including immediately
        // after a black-frame commit. No stale mailbox event may survive reset.
        for(number=1;number<=4;number=number+1)begin
            before_done=completed;prepare_transition(0,1);wait(completed==before_done+1);
            repeat(35)@(negedge audio_clk);
            prepare_transition(number,number!=1);wait(state==number);
            #0.217;common_reset(number%2);
        end
        if(commits!=109 || published!=111 || completed!=108 || resets!=13)
            $fatal(1,"transition-stage reset coverage incomplete");
        $display("RELIABILITY_CDC_TEST_PASS phase=%0d commits=%0d published=%0d complete=%0d cancels=%0d resets=%0d all_six_completion_orders reset_states_1_2_3_4",phase,commits,published,completed,cancelled,resets);
        $finish;
    end
    initial begin #10000000;$fatal(1,"reliability CDC timeout");end
endmodule
