`timescale 1ns/1ps
module tb_frame_completion;
    reg clk=0,rst=1,start=0,cancel=0,arm=0,sd=0,sc=0,md=0;
    always #5 clk=~clk;
    wire ss,cs,ms,ready;
    integer count=0,p,n;
    frame_completion_guard dut(.clk(clk),.reset(rst),.start(start),.cancel(cancel),
        .memory_arm(arm),.source_done(sd),.scale_done(sc),.memory_done(md),
        .source_seen(ss),.scale_seen(cs),.memory_seen(ms),.ready_pulse(ready));
    always @(posedge clk)begin #1;if(ready)begin if(!(ss&&cs&&ms))$fatal(1,"ready without all three events");count=count+1;end end
    task pulse;input integer which;
        begin @(negedge clk);case(which)0:sd=1;1:sc=1;2:md=1;3:start=1;4:arm=1;5:cancel=1;endcase
            @(negedge clk);sd=0;sc=0;md=0;start=0;arm=0;cancel=0;repeat(4)@(negedge clk);end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;
        for(p=0;p<6;p=p+1)begin
            pulse(3);pulse(2);if(ms||ready)$fatal(1,"stale completion before new ACK");pulse(4);
            case(p)0:begin pulse(0);pulse(1);pulse(2);end
                1:begin pulse(0);pulse(2);pulse(1);end
                2:begin pulse(1);pulse(0);pulse(2);end
                3:begin pulse(1);pulse(2);pulse(0);end
                4:begin pulse(2);pulse(0);pulse(1);end
                5:begin pulse(2);pulse(1);pulse(0);end endcase
            if(count!=p+1)$fatal(1,"lost/repeated done permutation=%0d",p);
            pulse(0);pulse(1);pulse(2);if(count!=p+1)$fatal(1,"duplicate ready");
        end
        for(n=0;n<3;n=n+1)begin
            pulse(3);pulse(4);pulse(n);pulse(5);pulse(0);pulse(1);pulse(2);
            if(count!=6 || ss||cs||ms)$fatal(1,"cancel retained old completion");
        end
        pulse(3);pulse(4);pulse(0);rst=1;repeat(4)@(negedge clk);rst=0;
        if(ss||cs||ms||ready)$fatal(1,"reset retained old completion");
        $display("FRAME_COMPLETION_TEST_PASS six orderings/duplicate/stale/reset/cancel");$finish;
    end
    initial begin #100000;$fatal(1,"FRAME_COMPLETION_TIMEOUT");end
endmodule
