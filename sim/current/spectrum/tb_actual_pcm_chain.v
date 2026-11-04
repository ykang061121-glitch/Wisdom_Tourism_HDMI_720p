`timescale 1ns/1fs
// Actual unchanged D1 serializer and receiver, with a parallel no-analysis copy.
module tb_actual_pcm_chain;
    reg video_clk=0,audio_clk=0;
    always #(1000000000.0/(2.0*74250000.0)) video_clk=~video_clk;
    always #(1000000000.0/(2.0*12295081.967104)) audio_clk=~audio_clk;
    reg reset=1,selection_update=0,selection_valid=0;
    reg [1:0] selection_image=0;
    wire a_bclk,a_lrck,a_data,b_bclk,b_lrck,b_data;
    wire a_active,b_active,a_start,b_start;
    wire [1:0] a_image,b_image;
    wire [9:0] a_status,b_status;
    wire a_valid,b_valid;
    wire [23:0] a_left,a_right,b_left,b_right;
    image_melody_i2s tx_a(.I_mclk(audio_clk),.I_rst(reset),
        .selection_update(selection_update),.selection_valid(selection_valid),
        .selection_image(selection_image),.O_i2s_BCLK(a_bclk),.O_i2s_LRCK(a_lrck),
        .O_i2s_DOUT(a_data),.active_valid(a_active),.active_image(a_image),
        .song_start(a_start),.playback_status(a_status));
    image_melody_i2s tx_b_no_analysis(.I_mclk(audio_clk),.I_rst(reset),
        .selection_update(selection_update),.selection_valid(selection_valid),
        .selection_image(selection_image),.O_i2s_BCLK(b_bclk),.O_i2s_LRCK(b_lrck),
        .O_i2s_DOUT(b_data),.active_valid(b_active),.active_image(b_image),
        .song_start(b_start),.playback_status(b_status));
    I2S_receiver rx_a(.I_clk(video_clk),.I_rst(reset),.I_i2s_BCLK(a_bclk),
        .I_i2s_LRCK(a_lrck),.I_i2s_DOUT(a_data),.O_audio_valid(a_valid),
        .O_audio_left_data(a_left),.O_audio_right_data(a_right));
    I2S_receiver rx_b_no_analysis(.I_clk(video_clk),.I_rst(reset),.I_i2s_BCLK(b_bclk),
        .I_i2s_LRCK(b_lrck),.I_i2s_DOUT(b_data),.O_audio_valid(b_valid),
        .O_audio_left_data(b_left),.O_audio_right_data(b_right));
    wire snapshot_valid,busy,overrun;
    wire [127:0] levels;
    wire [511:0] powers;
    pcm_spectrum_dft512 core(.clk(video_clk),.reset(reset),
        .sample_valid(a_valid),.pcm_sample($signed(a_left)),
        .snapshot_valid(snapshot_valid),.snapshot_levels(levels),
        .snapshot_power(powers),.busy(busy),.overrun(overrun));
    integer pcm_fd,snapshot_fd,event_fd,epoch=0,input_count=0,snapshots=0;
    integer i,k,target,tx_checks=0,rx_checks=0,valid_checks=0;
    reg [4:0] states_seen=0;
    reg [3:0] steady_images_seen=0;
    reg [127:0] previous_levels=0;
    reg [511:0] previous_powers=0;
    // Check all transmitter outputs against the independent uninstrumented copy.
    always @(posedge audio_clk) begin
        #0.000001;
        if(!reset) begin
            if({a_bclk,a_lrck,a_data,a_active,a_image,a_start,a_status} !==
               {b_bclk,b_lrck,b_data,b_active,b_image,b_start,b_status})
                $fatal(1,"audio/I2S output changed with analyzer attached");
            tx_checks=tx_checks+1;
            if(tx_a.sample_tick) begin
                states_seen[tx_a.pcm.state]=1;
                if(tx_a.pcm.state==2 && tx_a.pcm.envelope==2000000)
                    steady_images_seen[a_image]=1;
            end
        end
    end
    // These are precisely the PRE-edge PCM/valid values consumed by the core.
    always @(posedge video_clk) begin
        if(reset) begin input_count=0;previous_levels=0;previous_powers=0;end
        else begin
            if(a_valid===1'b1) begin
                if((input_count%2048)<512)
                    $fdisplay(pcm_fd,"%0d,%0d,%0d,%0d",epoch,input_count/2048,input_count%2048,$signed(a_left));
                input_count=input_count+1;
            end
            if(snapshot_valid) begin
                $fwrite(snapshot_fd,"%0d,%0d,%0d,%0t",epoch,input_count/2048,snapshots,$time);
                for(k=0;k<16;k=k+1) $fwrite(snapshot_fd,",%0d",powers[k*32+:32]);
                for(k=0;k<16;k=k+1) $fwrite(snapshot_fd,",%0d",levels[k*8+:8]);
                $fwrite(snapshot_fd,"\n");
                snapshots=snapshots+1;
                $display("PASS actual receiver snapshot %0d epoch %0d hop %0d",snapshots,epoch,input_count/2048);
            end
            if(!snapshot_valid && (levels!==previous_levels || powers!==previous_powers))
                $fatal(1,"actual-chain output changed outside snapshot");
            if(overrun) $fatal(1,"actual-chain sample cadence overrun");
            previous_levels=levels;previous_powers=powers;
        end
        #0.000001;
        if(!reset) begin
            if({a_valid,a_left,a_right} !== {b_valid,b_left,b_right})
                $fatal(1,"HDMI receiver PCM/valid differs with analyzer attached");
            rx_checks=rx_checks+1;
            if(a_valid===1'b1) valid_checks=valid_checks+1;
        end
    end
    task select_song;
        input integer image;
        input integer valid;
        begin
            @(negedge audio_clk);selection_image=image;selection_valid=valid;selection_update=1;
            $fdisplay(event_fd,"%0t,select,%0d,%0d",$time,image,valid);
            @(negedge audio_clk);selection_update=0;
        end
    endtask
    initial begin
        pcm_fd=$fopen("actual_chain_pcm.csv","w");
        snapshot_fd=$fopen("actual_chain_snapshots.csv","w");
        event_fd=$fopen("actual_chain_events.csv","w");
        $fdisplay(pcm_fd,"epoch,hop,index,pcm");
        repeat(40) @(negedge audio_clk);reset=0;
        for(i=0;i<4;i=i+1) begin
            select_song(i,1);target=snapshots+4;wait(snapshots>=target);
        end
        // Actual release envelope, silence gap, then persistent zero PCM.
        select_song(3,0);target=snapshots+4;wait(snapshots>=target);
        if(powers!==0) $fatal(1,"mute did not settle to a zero spectrum");
        select_song(0,1);target=snapshots+2;wait(snapshots>=target);
        // Reset after a complete window, while DFT is active, then restart song 4.
        wait((input_count%2048)==600 && busy);
        @(negedge audio_clk);reset=1;epoch=epoch+1;
        $fdisplay(event_fd,"%0t,reset,%0d,1",$time,epoch);
        repeat(40) @(negedge audio_clk);
        reset=0;select_song(3,1);target=snapshots+2;wait(snapshots>=target);
        repeat(4) @(negedge video_clk);
        if(states_seen!==5'b11111 || steady_images_seen!==4'b1111)
            $fatal(1,"missing real envelope/steady-song coverage states=%b songs=%b",states_seen,steady_images_seen);
        $fdisplay(event_fd,"%0t,counts,%0d,%0d,%0d",$time,tx_checks,rx_checks,valid_checks);
        $fdisplay(event_fd,"%0t,coverage,%0d,%0d",$time,states_seen,steady_images_seen);
        $fclose(pcm_fd);$fclose(snapshot_fd);$fclose(event_fd);
        $display("PASS actual PCM chain: %0d snapshots; %0d TX comparisons, %0d RX comparisons, %0d valid samples",snapshots,tx_checks,rx_checks,valid_checks);
        $display("PASS all four original songs, attack/play/release/silence/idle, mute, active-DFT reset and restart");
        $finish;
    end
    initial begin #1200000000; $fatal(1,"actual PCM chain watchdog"); end
endmodule
