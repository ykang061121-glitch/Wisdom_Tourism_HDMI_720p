`timescale 1ns/1ps
module tb_playback_interval;
    reg clk=0,reset=1,key=1,enable=0,restart=0;
    wire [1:0] code;
    wire press,tick;
    integer cycles=0,presses=0,ticks=0,checks=0;
    always #5 clk=~clk;
    playback_interval_control #(.CLK_FREQ_HZ(1000)) dut(
        .clk(clk),.reset(reset),.key_interval(key),.timer_enable(enable),
        .timer_restart(restart),.interval_code(code),.interval_press(press),.auto_tick(tick));
    // Independent elapsed-time model, not DUT divider/counter observations.
    integer elapsed=0,seconds=5,old_code=2;
    reg old_press;
    always @(posedge clk) begin
        if(reset) begin elapsed=0;presses=0;ticks=0;old_code=2;end
        else begin
            old_press=press;
            if(press)presses++;
            case(code) 0:seconds=5;1:seconds=3;2:seconds=5;3:seconds=10;endcase
            if(!enable || restart || press)elapsed=0;else elapsed++;
            #0.1;
            if($test$plusargs("INJECT_INTERVAL") && checks==0 && tick)
                force dut.auto_tick=0;
            if(tick !== (elapsed==seconds*1000))begin
                $display("INTERACTION_CHECKER_REJECT INTERVAL elapsed=%0d seconds=%0d tick=%b",elapsed,seconds,tick);
                $fatal(1,"wrong dwell duration");
            end
            if(tick)begin ticks++;elapsed=0;checks++;end
            if(code !== (old_press?(old_code==2?3:old_code==3?1:2):old_code))$fatal(1,"wrong K3 cycle");
            old_code=code;
        end
    end
    task press_key;
        begin
            @(negedge clk);key=0;repeat(3)@(negedge clk);key=1;
            repeat(2)@(negedge clk);key=0;repeat(28)@(negedge clk);
            key=1;repeat(28)@(negedge clk);
        end
    endtask
    integer n,before_press,before_tick;
    initial begin
        repeat(5)@(negedge clk);reset=0;
        if(code!==2)$fatal(1,"reset must select 5s");
        // Short glitch rejected; long held key creates ONE press only.
        key=0;repeat(7)@(negedge clk);key=1;repeat(30)@(negedge clk);
        if(presses!=0 || code!=2)$fatal(1,"short glitch changed setting");
        key=0;repeat(250)@(negedge clk);
        if(presses!=1 || code!=3)$fatal(1,"held K3 repeated");
        key=1;repeat(30)@(negedge clk);
        for(n=0;n<4;n++)begin
            press_key;
            if(code!==((n%3)==0?1:(n%3)==1?2:3))$fatal(1,"5->10->3->5 sequence");
            @(negedge clk);enable=1;before_tick=ticks;
            wait(ticks==before_tick+1);@(negedge clk);enable=0;
            repeat(12)@(negedge clk);
        end
        // Changing a running timer must not turn an already-elapsed short
        // interval into an immediate request; the next FULL interval starts.
        @(negedge clk);enable=1;
        repeat(700)@(negedge clk);press_key;
        before_tick=ticks;repeat(900)@(negedge clk);
        if(ticks!=before_tick)$fatal(1,"period change generated immediate advance");
        wait(ticks==before_tick+1);
        @(negedge clk);restart=1;repeat(5)@(negedge clk);restart=0;
        wait(elapsed==seconds*1000-1);
        @(negedge clk);restart=1;before_tick=ticks;
        repeat(3)@(negedge clk);
        if(ticks!=before_tick)$fatal(1,"restart at old expiry created an advance");
        restart=0;
        before_tick=ticks;repeat(400)@(negedge clk);
        enable=0;repeat(12000)@(negedge clk);
        if(ticks!=before_tick)$fatal(1,"busy/manual timer advanced");
        reset=1;repeat(3)@(negedge clk);reset=0;
        if(code!=2 || tick)$fatal(1,"reset did not clear selection/timer");
        $display("PLAYBACK_INTERVAL_TEST_PASS 3_5_10_seconds debounce held reset restart busy");$finish;
    end
    initial begin #2000000;$fatal(1,"interval test timeout");end
endmodule
