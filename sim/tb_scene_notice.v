`timescale 1ns/1ps
module tb_scene_notice;
    reg clk=0,reset=1,boundary=0,commit=0,valid=0;
    reg [1:0] image=0;
    wire visible;
    wire [1:0] scene;
    integer left=0,cards=0,frames=0;
    reg [1:0] expected_scene=0;
    always #20 clk=~clk;
    scene_notice dut(.pixel_clk(clk),.reset(reset),.frame_boundary(boundary),
        .display_commit(commit),.display_valid(valid),.display_image(image),
        .visible(visible),.scene_index(scene));
    always @(posedge clk)begin
        if(reset)begin left=0;expected_scene=0;end
        else if(!valid)left=0;
        else if(commit)begin left=72;expected_scene=image;cards++;end
        else if(boundary && left>0)begin left--;frames++;end
        #0.1;
        if(visible!==(left>0) || (visible && scene!==expected_scene))begin
            $display("SHOWCASE_CHECKER_REJECT PREMATURE_NOTICE remaining=%0d valid=%b commit=%b",left,valid,commit);
            $fatal(1,"notice not governed by successful committed display");
        end
    end
    task frame;
        begin @(negedge clk);boundary=1;@(negedge clk);boundary=0;
            repeat(11)@(negedge clk);end
    endtask
    task show(input [1:0] number);
        begin
            @(negedge clk);boundary=1;@(negedge clk);boundary=0;
            // The real fade FSM's registered commit/index arrive AFTER this
            // raw blanking edge, not as a button-edge event.
            image=number;valid=1;commit=1;
            @(negedge clk);commit=0;
        end
    endtask
    integer i;
    initial begin
        repeat(5)@(negedge clk);reset=0;
        // Loading/pending index changes and arbitrary UI activity are not
        // commit. Even an invalid display cannot announce a pending image.
        for(i=0;i<8;i++)begin image=i;frame;end
        if($test$plusargs("INJECT_NOTICE_EARLY"))begin force dut.visible=1;@(negedge clk);end
        show(0);repeat(71)frame;
        if(!visible)$fatal(1,"notice too short");
        frame;if(visible)$fatal(1,"notice did not expire at 72 frames");
        repeat(8)frame;if(visible)$fatal(1,"mode/period activity restarted card");
        show(1);repeat(5)frame;show(2);repeat(5)frame;show(3);
        if(scene!=3)$fatal(1,"rapid successful commits did not replace card");
        reset=1;repeat(3)@(negedge clk);reset=0;
        if(visible)$fatal(1,"K1 stale notice");
        if(cards!=4)$fatal(1,"wrong commit/card count");
        $display("SCENE_NOTICE_TEST_PASS duration_72_frames commits_manual_auto_latest_reset no_pending_trigger");$finish;
    end
endmodule
