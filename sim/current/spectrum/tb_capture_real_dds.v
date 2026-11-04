`timescale 1ns/1ps
module tb_capture_real_dds;
    reg clk=0; always #5 clk=~clk;
    reg reset=1, sample_tick=0, selection_update=0, selection_valid=0;
    reg [1:0] selection_image=0;
    wire signed [23:0] pcm;
    wire [2:0] note_index;
    wire [23:0] envelope;
    wire active_valid;
    integer song, n, fd;
    image_melody_pcm dut(.clk(clk),.reset(reset),.sample_tick(sample_tick),
        .selection_update(selection_update),.selection_valid(selection_valid),
        .selection_image(selection_image),.pcm_sample(pcm),.active_valid(active_valid),
        .active_image(),.note_index(note_index),.envelope(envelope),
        .song_start(),.pcm_status());
    initial begin
        fd=$fopen("real_dds_pcm.csv","w");
        $fdisplay(fd,"song,sample,note,envelope,pcm");
        for(song=0;song<4;song=song+1) begin
            @(negedge clk); reset=1; selection_update=0; sample_tick=0;
            repeat(3) @(negedge clk);
            reset=0; selection_valid=1; selection_image=song; selection_update=1;
            @(negedge clk); selection_update=0;
            // Enough real default-duration PCM for all eight notes of bass motif.
            for(n=0;n<194000;n=n+1) begin
                sample_tick=1; @(negedge clk); sample_tick=0;
                $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d",song,n,note_index,envelope,$signed(pcm));
                @(negedge clk);
            end
        end
        $fclose(fd); $display("PASS real original DDS PCM capture, four songs");
        $finish;
    end
endmodule
