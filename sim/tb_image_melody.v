`timescale 1ns/1ps
module tb_image_melody;
    localparam BASE=512;
    reg clk=0,reset=1,tick=0,update=0,valid=0;
    reg [1:0] image=0;
    wire signed [23:0] pcm;
    wire active,start;
    wire [1:0] playing;
    wire [2:0] note;
    wire [23:0] env;
    integer divider=0,samples=0,starts=0,silence_run=0,wraps[0:3],masks[0:3];
    reg [31:0] model_phase=0;
    integer model_note=0,model_count=0;
    reg pre_active,pre_tick;
    reg [1:0] pre_image;
    reg [23:0] pre_env;
    reg signed [23:0] wanted_pcm;
    reg [31:0] step;
    reg injected=0;
    integer before_starts,i;
    always #5 clk=~clk;
    always @(negedge clk) begin divider=(divider+1)%4;tick=(divider==0);end
    `include "image_audio_reference.vh"
    image_melody_pcm #(.BASE_NOTE_SAMPLES(BASE),.RAMP_HOLD_SAMPLES(2),.SILENCE_SAMPLES(3)) dut(
        .clk(clk),.reset(reset),.sample_tick(tick),.selection_update(update),
        .selection_valid(valid),.selection_image(image),.pcm_sample(pcm),
        .active_valid(active),.active_image(playing),.note_index(note),.envelope(env),.song_start(start));
    always @(posedge clk) begin
        if(reset) begin
            model_phase=0;model_note=0;model_count=0;silence_run=0;
            for(integer k=0;k<4;k++)begin wraps[k]=0;masks[k]=0;end
        end else begin
            pre_tick=tick;pre_active=active;pre_image=playing;pre_env=env;
            wanted_pcm=pre_active ? (model_phase[31]?$signed(env):-$signed(env)) : 24'sd0;
            step=reference_increment(pre_image,model_note);
            if(tick && pre_active)begin
                masks[pre_image]=masks[pre_image]|(1<<model_note);
                model_phase=model_phase+step;
                model_count++;
                if(model_count==reference_duration(pre_image,model_note,BASE))begin
                    model_count=0;
                    if(model_note==7)wraps[pre_image]++;
                    model_note=(model_note+1)%8;
                end
            end
            #0.1;
            if(pre_tick)begin
                samples++;
                if(pcm!==wanted_pcm)begin
                    $display("IMAGE_AUDIO_CHECKER_REJECT PCM sample=%0d",samples);
                    $fatal(1,"DDS PCM differs from independent phase/envelope math");
                end
                if(pcm==0)silence_run++;else silence_run=0;
                if(env>2000000 || ((env>pre_env)?env-pre_env:pre_env-env)>62500)
                    $fatal(1,"amplitude overflow or discontinuous ramp");
                if(start)begin
                    if(pre_env!=0 || env!=0 || pcm!=0 || note!=0 ||
                       (starts>0 && silence_run<3))
                        $fatal(1,"song changed without muted boundary");
                    starts++;model_phase=0;model_note=0;model_count=0;
                end
                if(dut.phase_acc!==model_phase || note!==model_note[2:0])begin
                    $display("IMAGE_AUDIO_CHECKER_REJECT DDS image=%0d note=%0d samples=%0d",playing,note,samples);
                    $fatal(1,"wrong frequency, note sequence or duration");
                end
            end else if(start)$fatal(1,"song changes outside stereo sample tick");
            if(dut.phase_increment!==reference_increment(playing,note))begin
                $display("IMAGE_AUDIO_CHECKER_REJECT NOTE image=%0d note=%0d",playing,note);
                $fatal(1,"wrong image-to-score mapping");
            end
        end
    end
    task select_image(input bit is_valid,input [1:0] idx);
        begin @(negedge clk);valid=is_valid;image=idx;update=1;@(negedge clk);update=0;end
    endtask
    task reboot;
        begin @(negedge clk);reset=1;update=0;valid=0;repeat(5)@(negedge clk);reset=0;end
    endtask
    initial begin
        reboot;repeat(120)@(negedge clk);
        if(pcm || active || env)$fatal(1,"audio before first displayed image");
        for(i=0;i<4;i++)begin
            select_image(1,i);
            wait(active && playing==i && env==2000000);
            if($test$plusargs("INJECT_MELODY_PITCH") && !injected)begin
                @(negedge clk);force dut.phase_increment=32'd1;injected=1;
            end
            wait(wraps[i]>=2);
            if(masks[i]!=255)$fatal(1,"not all eight notes were exercised");
            $display("IMAGE_MELODY_CASE_PASS image=%0d notes=8 loops=2",i+1);
        end
        before_starts=starts;select_image(1,3);repeat(1200)@(negedge clk);
        if(starts!=before_starts)$fatal(1,"same image restarted melody");
        // Changes arriving within one ramp: no deep queue, latest wins.
        select_image(1,0);select_image(1,1);select_image(1,3);select_image(1,2);
        wait(active && playing==2 && env==2000000);
        select_image(0,0);wait(!active && env==0);repeat(30)@(negedge clk);
        if(pcm!=0)$fatal(1,"invalid display did not mute");
        select_image(1,1);wait(active && env>0);reboot;
        repeat(160)@(negedge clk);
        if(active || pcm || env)$fatal(1,"reset left stale melody");
        select_image(1,0);wait(active && playing==0 && env==2000000);
        $display("IMAGE_MELODY_TEST_PASS samples=%0d starts=%0d ramp_step=62500 reset_latest_same_index",samples,starts);
        $finish;
    end
    initial begin #10000000;$fatal(1,"image melody timeout");end
endmodule
