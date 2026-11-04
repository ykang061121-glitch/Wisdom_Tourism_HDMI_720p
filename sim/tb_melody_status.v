`timescale 1ns/1ps
module melody_status_case #(parameter PHASE=0)(output reg done=0);
    reg aclk=0,vclk=0,reset=1,update=0,valid=0;
    reg [1:0] image=0;
    initial begin #(PHASE);forever #40.666667 aclk=~aclk;end
    always #20 vclk=~vclk;
    wire b,l,d,rb,rl,rd,start;
    wire [9:0] status,video_status;
    image_melody_i2s #(.BASE_NOTE_SAMPLES(64),.RAMP_HOLD_SAMPLES(1),.SILENCE_SAMPLES(4)) tx(
        .I_mclk(aclk),.I_rst(reset),.selection_update(update),.selection_valid(valid),
        .selection_image(image),.O_i2s_BCLK(b),.O_i2s_LRCK(l),.O_i2s_DOUT(d),
        .active_valid(),.active_image(),.song_start(start),.playback_status(status));
    image_melody_i2s_showcase_baseline #(.BASE_NOTE_SAMPLES(64),.RAMP_HOLD_SAMPLES(1),.SILENCE_SAMPLES(4)) original(
        .I_mclk(aclk),.I_rst(reset),.selection_update(update),.selection_valid(valid),
        .selection_image(image),.O_i2s_BCLK(rb),.O_i2s_LRCK(rl),.O_i2s_DOUT(rd),
        .active_valid(),.active_image(),.song_start());
    melody_status_cdc cdc(.audio_clk(aclk),.video_clk(vclk),.reset(reset),
        .audio_status(status),.video_status(video_status));
    `include "image_audio_reference.vh"
    reg [9:0] produced=0,expected=0,capture_expected=0;
    reg observing_valid,old_tick,capture;
    reg [9:0] held=0;
    reg old_busy=0,injected=0;
    reg send_event;
    reg [9:0] send_expected,latest_status=0;
    time changed_at=0;
    always @(negedge aclk)begin
        if(reset)begin latest_status=0;changed_at=$time;end
        else if(status!==latest_status)begin latest_status=status;changed_at=$time;end
    end
    integer samples=0,serial_cycles=0,transfers=0,starts=0,phases=0,mask[0:3];
    always @(posedge aclk)begin
        if(reset)begin produced=0;expected=0;held=0;old_busy=0;end
        else begin
            send_event=(cdc.request_toggle==cdc.ack_sync[1] && status!=cdc.sent_status);
            send_expected=status;
            old_tick=original.sample_tick;
            if(old_tick)begin
                expected=produced;
                observing_valid=original.pcm.active_valid &&
                    (original.pcm.state==1 || original.pcm.state==2 ||
                     (original.pcm.state==3 && original.pcm.envelope!=0));
                produced={observing_valid,original.pcm.active_image,original.pcm.note_index,
                          original.pcm.state,(observing_valid && original.pcm.envelope!=0)};
                samples++;
            end
            if(old_busy && cdc.held_status!==held)$fatal(1,"audio payload overwritten before ack");
            #0.1;
            serial_cycles++;
            if(send_event && cdc.held_status!==send_expected)$fatal(1,"mailbox did not hold the source status bundle");
            if({b,l,d}!=={rb,rl,rd})$fatal(1,"visualization changed legacy I2S bits or rhythm");
            if(!injected && PHASE==0 && status[9] && status[6:4]==0)begin
                if($test$plusargs("INJECT_VIS_STEP"))begin force tx.playback_status[6:4]=3'd1;injected=1;end
                if($test$plusargs("INJECT_VIS_MELODY"))begin force tx.playback_status[8:7]=2'd3;injected=1;end
            end
            if(status!==expected)begin
                $display("SHOWCASE_CHECKER_REJECT AUDIO_META got=%b expected_serial_sample_label=%b",status,expected);
                $fatal(1,"current melody/note not aligned to actual serialized PCM");
            end
            if(status[9])mask[status[8:7]]=mask[status[8:7]] | (1<<status[6:4]);
            phases=phases | (1<<status[3:1]);
            if(start)starts++;
            old_busy=(cdc.request_toggle!=cdc.ack_sync[1]);held=cdc.held_status;
        end
    end
    always @(posedge vclk)begin
        if(!reset)begin
            capture=cdc.capture_wait;capture_expected=capture?cdc.held_status:video_status;
            #0.1;
            if(video_status!==capture_expected)$fatal(1,"torn/unsolicited video status");
            if($time-changed_at>2000 && video_status!==latest_status)
                $fatal(1,"audio/video status mismatch exceeded explicit 2us mailbox bound");
            if(capture)transfers++;
        end
    end
    task select_song(input integer number,input bit enabled);
        begin @(negedge aclk);image=number;valid=enabled;update=1;
            @(negedge aclk);update=0;end
    endtask
    integer i,j,n,total,before_starts;
    initial begin
        for(i=0;i<4;i++)mask[i]=0;
        repeat(10)@(negedge aclk);reset=0;
        for(i=0;i<4;i++)begin
            select_song(i,1);wait(original.pcm.state==2 && original.pcm.active_image==i);
            total=0;for(j=0;j<8;j++)total+=reference_duration(i,j,64);
            n=samples;wait(samples>=n+total*2);
            before_starts=starts;select_song(i,1);n=samples;wait(samples>=n+40);
            if(starts!=before_starts)$fatal(1,"same picture restarted music");
            if(mask[i]!=255)$fatal(1,"did not observe all eight actual notes");
        end
        select_song(0,0);wait(original.pcm.state==0);repeat(30)@(negedge vclk);
        if(video_status[9])$fatal(1,"silent/idle display retained valid highlight");
        select_song(1,1);select_song(2,1);select_song(3,1);
        wait(original.pcm.state==2 && original.pcm.active_image==3);
        @(negedge aclk);reset=1;repeat(6)@(negedge aclk);reset=0;
        repeat(20)@(negedge vclk);
        if(status!=0 || video_status!=0)$fatal(1,"common reset left stale music state");
        if((phases & 31)!=31 || transfers<60 || serial_cycles<100000)
            $fatal(1,"insufficient phase/CDC/bitstream equivalence coverage");
        $display("MELODY_STATUS_PHASE_PASS phase=%0d samples=%0d equivalent_serial_cycles=%0d mailbox_transfers=%0d all_32_notes_nonuniform_rhythm",PHASE,samples,serial_cycles,transfers);
        done=1;
    end
endmodule
module tb_melody_status;
    wire [3:0] done;
    melody_status_case #(.PHASE(0)) c0(done[0]);
    melody_status_case #(.PHASE(7)) c1(done[1]);
    melody_status_case #(.PHASE(13)) c2(done[2]);
    melody_status_case #(.PHASE(31)) c3(done[3]);
    initial begin wait(&done);$display("MELODY_STATUS_TEST_PASS");$finish;end
    initial begin #160000000;$fatal(1,"melody state test timeout");end
endmodule
