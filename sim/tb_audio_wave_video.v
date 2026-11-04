`timescale 1ns/1ps
module tb_audio_wave_video;
    reg clk=0,reset=1,req_d=0;
    wire req,hs0,vs0,de0,unused_read_en;
    wire [23:0] video_background;
    wire hs,vs,de,oh,ov,od;
    wire [9:0] x,y,ox,oy;
    wire [7:0] addr;
    wire signed [7:0] amplitude;
    wire sample_valid,snapshot_valid,commit;
    wire [23:0] wave;
    // Use the EXACT top-level frame event, not a software frame timer.
    wire boundary=req && !req_d;
    reg [9:0] audio_count=0;
    integer sample_number=0;
    wire audio_valid=(audio_count==520);
    wire signed [23:0] pcm=((sample_number%128)-64)*65536;
    wire [23:0] bg=video_background ^ {x[7:0],y[7:0],8'h5A};
    always #20 clk=~clk;
    video_timing_data timing(.video_clk(clk),.rst(reset),.read_req(req),.read_req_ack(1'b1),.hs(hs0),.vs(vs0),.de(de0));
    video_delay delay(.video_clk(clk),.rst(reset),.read_en(unused_read_en),.read_data(24'h345678),
        .hs(hs0),.vs(vs0),.de(de0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(video_background));
    video_active_position pos(.pixel_clk(clk),.reset(reset),.vs(vs),.de(de),.x(x),.y(y));
    always @(posedge clk) if(reset) begin req_d<=0;audio_count<=0;sample_number<=0;end
        else begin req_d<=req;audio_count<=audio_valid?0:audio_count+1; if(audio_valid) sample_number<=sample_number+1;end
    audio_wave_capture capture(.pixel_clk(clk),.reset(reset),.audio_valid(audio_valid),.audio_left(pcm),
        .frame_boundary(boundary),.video_de(de),.read_index(addr),.read_amplitude(amplitude),.read_valid(sample_valid),
        .snapshot_valid(snapshot_valid),.snapshot_commit(commit));
    audio_wave_overlay overlay(.pixel_clk(clk),.reset(reset),.hs(hs),.vs(vs),.de(de),.x(x),.y(y),.background_rgb(bg),
        .sample_amplitude(amplitude),.sample_valid(sample_valid),.sample_index(addr),.out_hs(oh),.out_vs(ov),.out_de(od),
        .out_x(ox),.out_y(oy),.wave_rgb(wave));

    integer banks[0:511];
    integer skipped=0,collected=0,wb=0,db=1,commits=0,checks=0,frames=0,frame_pixels=0;
    reg held=0,published=0,old_held,old_pub,old_boundary;
    reg monitor_enable=0;
    reg [9:0] px,py;
    reg ph,pv,pd,last_de=0,last_vs=0;
    reg [23:0] pre_bg,expected;
    integer old_db,ri,value,q,ty;
    always @(posedge clk) begin
        if(!reset && monitor_enable) begin
            old_held=held;old_pub=published;old_db=db;old_boundary=boundary;
            px=x;py=y;ph=hs;pv=vs;pd=de;pre_bg=bg;
            if(boundary) begin
                if(de) $fatal(1,"actual frame event occurs in active video");
                if(frames>0 && frame_pixels!=307200) $fatal(1,"pixel count changed by wave layer");
                frames=frames+1;frame_pixels=0;
            end
            if(audio_valid) begin
                if(skipped<2) skipped=skipped+1;
                else if(!held) begin
                    value=(sample_number%128)-64;
                    q=(value>45)?45:(value< -45)?-45:value;
                    banks[wb*256+collected]=q;collected=collected+1;
                    if(collected==256) held=1;
                end
            end
            if(boundary && old_held) begin db=wb;wb=1-wb;collected=0;held=0;published=1;commits=commits+1;end
            #1;
            if({oh,ov,od,ox,oy}!=={ph,pv,pd,px,py}) $fatal(1,"actual video metadata delayed inconsistently");
            if(commit!==(old_boundary && old_held)) $fatal(1,"frame-atomic publication failure");
            if(commit && od) $fatal(1,"display window changed during DE");
            expected=pd?pre_bg:0;
            if(pd && px>=16 && px<=623 && py>=330 && py<=455) begin
                expected=24'h18202A;
                if(px==16 || px==623 || py==330 || py==455) expected=24'h608090;
                else begin
                    if(py==392) expected=24'h405060;
                    if(old_pub && px>=64 && px<=575) begin
                        ri=(px-64)/2;ty=392-banks[old_db*256+ri];
                        if(py>=ty-1 && py<=ty+1) expected=24'h00FF80;
                    end
                end
            end
            if(wave!==expected) $fatal(1,"real-video pixel mismatch frame=%0d x=%0d y=%0d observed=%h expected=%h",frames,px,py,wave,expected);
            if(pd) begin frame_pixels=frame_pixels+1;checks=checks+1;end
        end
    end
    initial begin
        repeat(8) @(negedge clk);reset=0;
        // Legacy timing_data does not reset its d1 registers. Allow the
        // existing 2+21-cycle video pipeline to flush UNKNOWN startup blanking.
        // No active pixel exists yet; all subsequent pixels/timing are checked.
        repeat(32) @(negedge clk);monitor_enable=1;
        wait(frames>=4);
        @(negedge clk);
        if(commits<3 || checks<921600) $fatal(1,"fewer than three complete frame checks");
        $display("AUDIO_WAVE_VIDEO_TEST_PASS boundary_intervals=3 active_pixels=%0d commits=%0d real_800x525_timing",checks,commits);$finish;
    end
    initial begin #70000000;$fatal(1,"real video timeout");end
endmodule
