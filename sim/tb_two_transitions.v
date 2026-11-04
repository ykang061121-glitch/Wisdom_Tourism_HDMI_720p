`timescale 1ns/1ps
module tb_two_transitions;
    wire unused;
    progress_commit_case #(.RUN_AUTOMATIC_CASE(0)) core(unused);
    integer commits=0,successes=0,transactions=0,selected=0;
    reg seen=0,await_scene=0,was_frame;
    task fail(input string why);begin $display("TWO_TRANSITIONS_CHECKER_REJECT %s",why);$fatal(1,"alternation");end endtask
    always @(posedge core.vclk)begin
        was_frame=core.frame;#0.3;
        if(core.reset)begin commits=0;successes=0;seen=0;await_scene=0;end
        else begin
            if(core.commit)begin commits++;await_scene=1;end
            // Independent scoreboard counts actual nonblack scene starts,
            // not the DUT next-effect flag, image number or button edges.
            if(was_frame && await_scene && core.valid && core.level!=0 && (core.state==4 || core.state==0))begin
                await_scene=0;if(seen)successes++;else seen=1;
            end
            if(core.effect>1)fail("removed blinds became visible");
        end
    end
    task check_next;
        reg observed;
        begin
            observed=core.picture.next_effect;
            if($test$plusargs("INJECT_ALTERNATE") && successes>=1)observed=~observed;
            if(observed!==(successes%2))fail("success-count alternating mode mismatch");
        end
    endtask
    task finish_scene(input integer target);
        integer steps;
        reg [1:0] chosen;
        begin
            chosen=successes%2;core.hold_fetch=0;core.wait_ready;
            wait(core.state==2);repeat(4)@(negedge core.vclk);
            if(core.effect!=chosen)fail("effect selected from IMG instead of success count");
            steps=0;
            while(core.state!=3)begin core.advance;steps++;if(steps>20)fail("missing black state");end
            core.advance;
            if($test$plusargs("INJECT_EARLY_ALTERNATE"))force core.picture.next_effect=1'b1;
            check_next; // commit is black; MUST NOT advance the sequence yet
            if(core.level!=0 || core.image!=target)fail("unsafe/incorrect commit");
            core.advance;check_next;
            core.advance;repeat(3)@(negedge core.vclk);
            check_next;
            core.settled(target);check_next;transactions++;
        end
    endtask
    integer i,target,before_commits,before_success;
    initial begin
        core.sd_ticks(12);core.reset=0;core.settled(0);
        if(successes!=0 || commits!=1 || core.effect!=0)fail("first boot counted as a switch");
        check_next;
        // Four scenes, a second cycle with repeated target identities, and
        // real K2/AUTO timer requests all share the same original controller.
        for(i=0;i<6;i++)begin
            target=(core.image+1)%4;core.hold_fetch=1;
            if(i%2==0)core.next_key;
            else begin core.mode_key;wait(core.source.load_busy);end
            wait(core.source.load_busy);repeat(3)core.advance;
            before_commits=commits;before_success=successes;
            core.next_key;repeat(2)core.advance;
            if(commits!=before_commits || successes!=before_success || core.level!=4)fail("busy request changed scene");
            finish_scene(target);
            if(core.auto_mode)core.mode_key;
        end
        // Real malformed cached image load: no commit, no mode consumption.
        core.bad=1;before_commits=commits;before_success=successes;core.next_key;
        wait(core.error==8'hE0);repeat(4)core.advance;
        if(commits!=before_commits || successes!=before_success)fail("bad BMP advanced effects");
        if($test$plusargs("INJECT_FAILED_ALTERNATE"))force core.picture.next_effect=1'b1;
        check_next;core.bad=0;
        target=(core.image+1)%4;core.next_key;finish_scene(target);
        // Cancel while the real loader is waiting. Never guess a new sector.
        before_commits=commits;before_success=successes;core.hold_fetch=1;core.next_key;
        wait(core.source.load_busy);force core.source.cancel=1'b1;core.sd_ticks(10);release core.source.cancel;
        repeat(30)core.advance;
        if(commits!=before_commits || successes!=before_success)fail("cancel advanced effects");
        check_next;
        @(negedge core.clk);core.reset=1;core.hold_fetch=0;core.sd_ticks(12);core.reset=0;core.settled(0);
        if(successes!=0 || core.effect!=0)fail("reset failed to restart with fade");
        core.next_key;finish_scene(1);
        if(transactions!=8)fail("insufficient successful transaction coverage");
        $display("TWO_TRANSITIONS_TEST_PASS transactions=%0d manual AUTO four_scene_wrap bad_retry cancel busy reset",transactions);$finish;
    end
    initial begin #100000000;$fatal(1,"two-transition watchdog");end
endmodule
