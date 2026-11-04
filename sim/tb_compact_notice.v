`timescale 1ns/1ps
module tb_compact_notice;
    reg clk=0,reset=1,boundary=0,commit=0,valid=0,auto_mode=0,sub=1,vis=1;
    reg [1:0] image=0,interval=2,preset=0;
    wire [23:0] rgb;
    wire hs,vs,de;
    wire [9:0] x,y;
    integer cards=0;
    always #20 clk=~clk;
    showcase_presentation dut(.pixel_clk(clk),.reset(reset),.frame_boundary(boundary),
        .hs(1'b1),.vs(1'b1),.de(1'b0),.x(10'd0),.y(10'd0),.background_rgb(24'h123456),
        .subtitles_visible(sub),.visual_visible(vis),.sample_amplitude(8'sd0),.sample_valid(1'b0),
        .sample_index(),.audio_status(10'd0),.display_commit(commit),.display_valid(valid),
        .auto_play_enable(auto_mode),.image_index(image),.interval_code(interval),.preset_mode(preset),
        .brightness(8'sd0),.contrast(2'd1),.fade_level(3'd4),
        .out_hs(hs),.out_vs(vs),.out_de(de),.out_x(x),.out_y(y),.output_rgb(rgb));
    task check(input integer hint,kind,card,scene);
        begin #0.1;
            if((dut.hint_remaining!=0)!==1'(hint) || (hint && dut.hint_kind!=kind) ||
               dut.notice_visible!==1'(card) || (card && dut.notice_index!=scene))begin
                $display("COMPACT_CHECKER_REJECT hint=%0d kind=%0d card=%b scene=%0d expected=%0d/%0d/%0d/%0d",
                    dut.hint_remaining,dut.hint_kind,dut.notice_visible,dut.notice_index,hint,kind,card,scene);
                $fatal(1,"parameter feedback or commit-only notice mismatch");
            end
        end
    endtask
    task frame;
        begin @(negedge clk);boundary=1;@(negedge clk);boundary=0;repeat(4)@(negedge clk);end
    endtask
    task show(input integer scene);
        begin frame;image=scene;valid=1;commit=1;@(negedge clk);commit=0;cards++;end
    endtask
    integer i,k,kind;
    initial begin
        repeat(5)@(negedge clk);reset=0;frame;check(0,0,0,0);
        // A mid-frame control change must wait for the next blanking sample.
        interval=3;repeat(9)@(negedge clk);check(0,0,0,0);
        frame;
        if($test$plusargs("INJECT_PROMPT_FLICKER"))force dut.hint_remaining=7'd0;
        check(1,1,0,0);
        repeat(71)frame;check(1,1,0,0);frame;
        if($test$plusargs("INJECT_HINT_STUCK"))force dut.hint_remaining=7'd1;
        check(0,0,0,0);repeat(3)frame;check(0,0,0,0);
        // Both directions of each change; no setting has a scene-commit input.
        for(k=0;k<2;k++)begin
            auto_mode=!auto_mode;frame;check(1,2,0,0);
            for(i=0;i<4;i++)begin preset=(preset+1)%4;frame;check(1,3,0,0);end
            sub=!sub;frame;check(1,4,0,0);
            vis=!vis;frame;check(1,5,0,0);
        end
        // All four physical switches at once: deterministic VIS priority.
        preset=1;sub=0;vis=0;interval=0;auto_mode=1;frame;check(1,5,0,0);
        repeat(72)frame;check(0,0,0,0);
        // Pending display_index without commit never announces a future frame.
        for(i=0;i<4;i++)begin image=i;frame;check(0,0,0,0);end
        show(0);check(0,0,1,0);
        repeat(71)frame;check(0,0,1,0);frame;check(0,0,0,0);
        show(1);repeat(3)frame;show(2);check(0,0,1,2);
        // UI changes may not reset the scene-card's independent 72-frame timer.
        interval=1;auto_mode=0;frame;check(1,2,1,2);
        repeat(53)frame;check(1,2,1,2);
        repeat(18)frame;check(1,2,0,0);
        valid=0;show(3);check(0,0,1,3);
        reset=1;repeat(3)@(negedge clk);reset=0;frame;check(0,0,0,0);
        if(cards!=4)$fatal(1,"missing rapid successful commits");
        // No unmodified setting may retrigger a prompt, including startup.
        repeat(80)frame;check(0,0,0,0);
        interval=2;repeat(9)@(negedge clk);
        if(dut.ui_settings[1:0]!=1)$fatal(1,"mid-frame live setting tore prompt");
        frame;check(1,1,0,0);
        interval=3;repeat(9)@(negedge clk);
        if(dut.ui_settings[1:0]!=2)$fatal(1,"snapshot not stable until next frame");
        frame;check(1,1,0,0);
        repeat(71)frame;check(1,1,0,0);frame;check(0,0,0,0);
        for(i=0;i<4;i++)begin show(i);repeat(10)frame;check(0,0,1,i);end
        interval=0;auto_mode=0;frame;check(1,1,1,3);
        repeat(61)frame;check(1,1,0,0);
        repeat(11)frame;check(0,0,0,0);
        if(cards!=8)$fatal(1,"rapid commit queue or lost cards");
        $display("COMPACT_NOTICE_TEST_PASS hint_72_frames card_72_frames snapshot_stable rapid_latest no_repeat frame_atomic five_controls simultaneous latest reset no_premature_scene");$finish;
    end
    initial begin #1000000;$fatal(1,"compact notice timeout");end
endmodule
