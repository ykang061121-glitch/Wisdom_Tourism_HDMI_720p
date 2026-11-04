`timescale 1ns/1ps
// The four instances exercise actual transmitter -> serial synchronizers ->
// EXACT HDMI parallel interface -> capture, with different clock phases.
module wave_link_case #(parameter integer PHASE_NS=0)(output reg done=0);
    reg mclk=0,clk=0,reset=1;
    wire bclk,lrclk,dout,pcm_valid;
    wire [23:0] left_pcm,right_pcm;
    wire signed [7:0] amplitude;
    wire sample_valid,snapshot_valid,commit;
    reg [7:0] index=0;
    reg [16:0] frame_count=0;
    wire boundary=(frame_count==99999);
    // Actual generated PLL C2: 750 MHz / 61, not 12.288 MHz in old comments.
    always #40.666667 mclk=~mclk;
    initial begin #(PHASE_NS);forever #20 clk=~clk;end
    hdmi_audio_tone_i2s_64fs tx(.I_mclk(mclk),.I_rst(reset),.O_i2s_BCLK(bclk),
        .O_i2s_LRCK(lrclk),.O_i2s_DOUT(dout));
    I2S_receiver rx(.I_clk(clk),.I_rst(reset),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrclk),
        .I_i2s_DOUT(dout),.O_audio_valid(pcm_valid),.O_audio_left_data(left_pcm),.O_audio_right_data(right_pcm));
    audio_wave_capture capture(.pixel_clk(clk),.reset(reset),.audio_valid(pcm_valid),.audio_left(left_pcm),
        .frame_boundary(boundary),.video_de(1'b0),.read_index(index),.read_amplitude(amplitude),
        .read_valid(sample_valid),.snapshot_valid(snapshot_valid),.snapshot_commit(commit));

    // Independent I2S wire decoder, respecting this legacy 64-BCLK slot's
    // boundary bit. No hierarchical sample registers supply the reference.
    reg previous_lr=0,started=0,serial_ready=0;
    reg [63:0] lbits=0,rbits=0;
    reg [23:0] serial_left=0,expected_left=0,expected_right=0;
    integer stereo_bclks=0,last_frame_edges=0,serial_frames=0;
    always @(posedge bclk) begin
        if(!reset) begin
            stereo_bclks=stereo_bclks+1;
            if(!started) begin started=1;previous_lr=lrclk;end
            else if(lrclk!=previous_lr) begin
                if(!previous_lr) begin
                    lbits={lbits[62:0],dout};serial_left=lbits[63:40];lbits=0;
                end else begin
                    rbits={rbits[62:0],dout};expected_left=serial_left;expected_right=rbits[63:40];rbits=0;
                    serial_ready=1;
                    if(serial_frames>0 && stereo_bclks-last_frame_edges!=128) $fatal(1,"actual I2S frame length changed");
                    last_frame_edges=stereo_bclks;serial_frames=serial_frames+1;
                end
                previous_lr=lrclk;
            end else if(!lrclk) lbits={lbits[62:0],dout};else rbits={rbits[62:0],dout};
        end
    end

    function integer quant_reference;
        input [23:0] bits;
        integer value,q;
        begin
            value=(bits>=24'h800000)?bits-16777216:bits;
            q=(value>=0)?value/65536:-((-value+65535)/65536);
            quant_reference=(q>45)?45:(q< -45)?-45:q;
        end
    endfunction
    integer reference_banks[0:511];
    integer collected=0,skip=0,windows=0,samples=0,reads=0;
    integer wb=0,db=1,old_pending,old_valid,old_bank,old_index,old_boundary;
    reg held=0,displayed=0;
    always @(negedge clk) index=index+1;
    always @(posedge clk) begin
        if(reset) begin
            frame_count<=0; collected=0;skip=0;held=0;displayed=0;wb=0;db=1;windows=0;
        end else begin
            frame_count<=(boundary)?0:frame_count+1;
            old_pending=held;old_valid=displayed;old_bank=db;old_index=index;old_boundary=boundary;
            if(pcm_valid) begin
                if(!serial_ready || left_pcm!==expected_left || right_pcm!==expected_right || left_pcm!==right_pcm)
                    $fatal(1,"phase=%0d HDMI PCM differs from actual transmitted I2S",PHASE_NS);
                serial_ready=0;samples=samples+1;
                if(skip<2) skip=skip+1;
                else if(!held) begin
                    reference_banks[wb*256+collected]=quant_reference(left_pcm);
                    collected=collected+1;
                    if(collected==256) held=1;
                end
            end
            if(boundary && old_pending) begin db=wb;wb=1-wb;collected=0;held=0;displayed=1;windows=windows+1;end
            #1;
            if(sample_valid!==old_valid[0]) $fatal(1,"snapshot validity mismatch");
            if(old_valid) begin
                if($signed(amplitude)!==reference_banks[old_bank*256+old_index])
                    $fatal(1,"phase=%0d published snapshot differs from HDMI source index=%0d",PHASE_NS,old_index);
                reads=reads+1;
            end
            if(commit!==(old_boundary && old_pending)) $fatal(1,"CDC/window switch outside expected boundary");
        end
    end
    task reboot;
        begin
            @(negedge clk);reset=1;
            started=0;previous_lr=0;serial_ready=0;lbits=0;rbits=0;serial_left=0;
            stereo_bclks=0;last_frame_edges=0;serial_frames=0;
            repeat(16) @(negedge clk);
            if(snapshot_valid || sample_valid) $fatal(1,"unlock did not invalidate snapshot");
            reset=0;
        end
    endtask
    initial begin
        reboot;
        wait(windows>=2); // 256 continuous real PCM samples in EACH bank
        @(negedge clk);
        if(samples<512 || reads<256) $fatal(1,"insufficient actual source verification");
        reboot; // exact rst_all semantics on PLL unlock, without changing receiver
        wait(windows>=1);
        repeat(300) @(negedge clk);
        $display("AUDIO_WAVE_LINK_PHASE_PASS phase=%0d samples=%0d reads=%0d windows_before_reset=2 after_reset=1",PHASE_NS,samples,reads);
        done=1;
    end
endmodule
module tb_audio_wave_link;
    wire [3:0] done;
    wave_link_case #(.PHASE_NS(0)) p0(done[0]);
    wave_link_case #(.PHASE_NS(7)) p1(done[1]);
    wave_link_case #(.PHASE_NS(13)) p2(done[2]);
    wave_link_case #(.PHASE_NS(31)) p3(done[3]);
    initial begin wait(&done);$display("AUDIO_WAVE_LINK_TEST_PASS phases=4 actual_I2S_PCM_to_HDMI_to_wave");$finish;end
    initial begin #40000000;$fatal(1,"wave link timeout");end
endmodule
