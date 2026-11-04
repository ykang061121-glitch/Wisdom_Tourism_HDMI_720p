`timescale 1ns/1ps
module tb_audio_wave_capture;
    reg clk=0, reset=1, valid=0, boundary=0, de=0;
    reg signed [23:0] pcm=0;
    reg [7:0] index=0;
    wire signed [7:0] amplitude;
    wire read_valid, snapshot_valid, commit;
    integer expected[0:255];
    integer i, window, commit_count=0;
    reg inject;
    always #20 clk=~clk;
    audio_wave_capture dut(.pixel_clk(clk),.reset(reset),.audio_valid(valid),
        .audio_left(pcm),.frame_boundary(boundary),.video_de(de),.read_index(index),
        .read_amplitude(amplitude),.read_valid(read_valid),
        .snapshot_valid(snapshot_valid),.snapshot_commit(commit));
    function integer reference;
        input integer value;
        integer q;
        begin
            // Independent signed floor division, not DUT bit slicing.
            q=(value>=0)?value/65536:-((-value+65535)/65536);
            reference=(q>45)?45:(q< -45)?-45:q;
        end
    endfunction
    function integer stimulus;
        input integer n,w;
        begin
            case(n%10)
                0:stimulus=0; 1:stimulus=1; 2:stimulus=-1;
                3:stimulus=8388607; 4:stimulus=-8388608;
                5:stimulus=2000000; 6:stimulus=-2000000;
                default:stimulus=((n*17+w*13)%256-128)*65536;
            endcase
        end
    endfunction
    task send;
        input integer value;
        begin
            @(negedge clk);valid=1;pcm=value;
            @(negedge clk);valid=0;pcm=24'h123456;
        end
    endtask
    task frame;
        input integer active;
        begin
            @(negedge clk); boundary=1; de=active;
            @(negedge clk); boundary=0; de=0;
        end
    endtask
    task inspect;
        integer n,observed;
        begin
            for(n=0;n<256;n=n+1) begin
                @(negedge clk);index=n;
                @(posedge clk);#1;
                observed=$signed(amplitude);
                if(inject && n==5) observed=-observed;
                if(!read_valid || observed!==expected[n]) begin
                    $display("AUDIO_WAVE_CHECKER_REJECT index=%0d observed=%0d expected=%0d",n,observed,expected[n]);
                    $fatal(1,"snapshot amplitude or bank corruption");
                end
            end
        end
    endtask
    always @(posedge clk) begin
        #1;
        if(!reset && commit) begin
            if(!boundary || de) $fatal(1,"window published outside safe boundary");
            commit_count=commit_count+1;
        end
    end
    task restart;
        begin
            @(negedge clk);reset=1;valid=0;boundary=0;
            #1;if(snapshot_valid || read_valid) $fatal(1,"reset displays stale music");
            repeat(4) @(negedge clk);
            reset=0;
            send(8388607);send(-8388608); // receiver settling: deliberately discard
        end
    endtask
    initial begin
        inject=$test$plusargs("INJECT_SIGN");
        restart;
        for(window=0;window<3;window=window+1) begin
            for(i=0;i<256;i=i+1) begin
                expected[i]=reference(stimulus(i,window));send(stimulus(i,window));
                if(i==127) begin
                    frame(0);
                    if(commit_count!=window) $fatal(1,"half-window commit");
                end
            end
            // Hundreds of later samples must not overwrite a pending window.
            for(i=0;i<300;i=i+1) send(7777777);
            frame(1);
            if(commit_count!=window) $fatal(1,"active-video bank commit");
            frame(0);
            if(commit_count!=window+1) $fatal(1,"missing complete window commit");
            inspect;
            frame(0);
            if(commit_count!=window+1) $fatal(1,"duplicate bank commit");
        end
        // Reset while collecting, while pending, and while displaying.
        for(i=0;i<83;i=i+1) send(i*65536);
        restart; frame(0);
        if(snapshot_valid) $fatal(1,"partial pre-reset window resurrected");
        for(i=0;i<256;i=i+1) send(0);
        restart;frame(0);
        if(snapshot_valid) $fatal(1,"pending pre-reset window resurrected");
        for(i=0;i<256;i=i+1) begin expected[i]=0;send(0);end
        frame(0);inspect;
        frame(0);frame(0);
        repeat(2) @(negedge clk);
        if(snapshot_valid || read_valid) $fatal(1,"missing PCM leaves stale historical waveform");
        send(0);send(0);
        for(i=0;i<256;i=i+1) begin expected[i]=0;send(0);end
        frame(0);inspect;
        restart;
        $display("AUDIO_WAVE_CAPTURE_TEST_PASS windows=5 samples_per_window=256 missing_PCM_invalidated");
        $finish;
    end
    initial begin #2000000;$fatal(1,"capture timeout");end
endmodule
