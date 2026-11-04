`timescale 1ns/1ps
module image_cdc_case #(parameter PHASE=0)(output reg done=0);
    reg video_clk=0,audio_clk=0,reset=1,valid=0,run_audio=1;
    reg [1:0] image=0;
    wire update,out_valid;
    wire [1:0] out_image;
    reg [2:0] flight=0,old_payload,old_wanted;
    reg old_request,old_busy,previous_update=0;
    integer launched=0,captured=0,i;
    always #20 video_clk=~video_clk;
    initial begin #(PHASE);forever begin #40.666667;if(run_audio)audio_clk=~audio_clk;end end
    image_audio_cdc dut(.video_clk(video_clk),.video_reset(reset),.display_valid(valid),
        .display_image(image),.audio_clk(audio_clk),.audio_reset(reset),
        .selection_update(update),.selection_valid(out_valid),.selection_image(out_image));
    always @(posedge video_clk)begin
        if(!reset)begin
            old_request=dut.request_toggle;old_busy=dut.busy;old_payload=dut.held_status;
            old_wanted=valid?{1'b1,image}:3'b000;
            #0.1;
            if(dut.request_toggle!=old_request)begin
                if(old_busy || dut.held_status!==old_wanted)$fatal(1,"mailbox source transaction incoherent");
                flight=dut.held_status;launched++;
            end else if(old_busy && dut.held_status!==old_payload)$fatal(1,"payload changed while awaiting ack");
        end
    end
    always @(posedge audio_clk)begin
        #0.1;
        if(reset)previous_update=0;
        else begin
            if(update)begin
                if(previous_update || {out_valid,out_image}!==flight)$fatal(1,"torn, duplicated or wrong CDC snapshot");
                captured++;
            end
            previous_update=update;
        end
    end
    initial begin
        repeat(10)@(negedge video_clk);reset=0;
        for(i=0;i<4;i++)begin
            @(negedge video_clk);valid=1;image=i;
            wait(out_valid && out_image==i);repeat(12)@(negedge audio_clk);
        end
        // Stalled audio clock: in-flight payload may not be overwritten.
        @(negedge audio_clk);run_audio=0;
        for(i=0;i<20;i++)begin @(negedge video_clk);image=i%4;end
        image=2;repeat(12)@(negedge video_clk);run_audio=1;
        wait(out_valid && out_image==2);repeat(20)@(negedge audio_clk);
        @(negedge video_clk);valid=0;
        wait(!out_valid);repeat(12)@(negedge audio_clk);
        if(out_image!=0)$fatal(1,"invalid status not canonical");
        @(negedge video_clk);reset=1;valid=0;repeat(10)@(negedge video_clk);reset=0;
        repeat(16)@(negedge audio_clk);
        if(out_valid || update)$fatal(1,"reset published stale status");
        @(negedge video_clk);valid=1;image=3;
        wait(out_valid && out_image==3);repeat(16)@(negedge audio_clk);
        if(launched!=captured)$fatal(1,"mailbox event lost or duplicated");
        $display("IMAGE_AUDIO_CDC_PHASE_PASS phase=%0d transfers=%0d coherent_hold_latest_reset",PHASE,captured);
        done=1;
    end
endmodule
module tb_image_audio_cdc;
    wire [3:0] done;
    image_cdc_case #(.PHASE(0)) c0(done[0]);
    image_cdc_case #(.PHASE(7)) c1(done[1]);
    image_cdc_case #(.PHASE(13)) c2(done[2]);
    image_cdc_case #(.PHASE(31)) c3(done[3]);
    initial begin wait(&done);$display("IMAGE_AUDIO_CDC_TEST_PASS phases=4");$finish;end
    initial begin #1000000;$fatal(1,"image audio CDC timeout");end
endmodule
