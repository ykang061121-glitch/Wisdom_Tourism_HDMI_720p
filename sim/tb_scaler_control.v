`timescale 1ns/1ps
module tb_scaler_control;
    reg clk=0,rst=1,cancel=0,start=0,iv=0,orr=0;
    always #5 clk=~clk;
    reg [23:0] id=0;
    wire ir,ov,done,busy;
    wire [23:0] od;
    wire [9:0] ox,oy;
    integer sent=0,received=0,n,stage;
    reg [31:0] seed=32'h1751CA11;
    reg hold=0;
    reg [43:0] held;
    image_scaler #(.OUT_WIDTH(4),.OUT_HEIGHT(2)) dut(.clk(clk),.reset(rst),.cancel(cancel),
        .start(start),.source_width(10'd4),.source_height(10'd2),.in_rgb(id),.in_valid(iv),.in_ready(ir),
        .out_rgb(od),.out_valid(ov),.out_ready(orr),.out_x(ox),.out_row(oy),.scale_done(done),.busy(busy));
    always @(posedge clk)begin
        if(!rst&&!cancel)begin
            if(hold && (!ov || {od,ox,oy}!==held))$fatal(1,"held output changed");
            hold=ov&&!orr;held={od,ox,oy};
            if(iv&&ir)sent=sent+1;
            if(ov&&orr)begin if(od!==(24'hABCDE0+received)||ox!==received%4||oy!==received/4)$fatal(1,"restart pixel/coordinate error");received=received+1;end
            if(done && received!=8)$fatal(1,"early scale_done");
        end else hold=0;
    end
    task launch;
        begin @(negedge clk);sent=0;received=0;start=1;iv=0;orr=0;
            @(negedge clk);start=0;end
    endtask
    task feed;
        begin while(sent<8)begin
            @(negedge clk);seed={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]};
            iv=seed[0];id=24'hABCDE0+sent;orr=seed[3];
        end @(negedge clk);iv=0;orr=1;end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;
        launch;
        fork
            begin while(sent<4)begin @(negedge clk);iv=1;id=24'hABCDE0+sent;end @(negedge clk);iv=0;end
            begin wait(ov);repeat(200)@(negedge clk);if(ir||received)$fatal(1,"line overwritten during long output stall");orr=1;end
        join
        feed;wait(done);@(negedge clk);
        for(stage=1;stage<=3;stage=stage+1)begin
            launch;
            fork
                begin while(dut.state!=stage)begin @(negedge clk);iv=1;id=24'hABCDE0+sent;end end
                begin wait(dut.state==stage);end
            join
            @(negedge clk);cancel=1;iv=0;@(negedge clk);cancel=0;
            if(busy||ov||done)$fatal(1,"cancel failed stage=%0d",stage);
            launch;feed;wait(done);@(negedge clk);
        end
        launch;wait(busy);@(negedge clk);rst=1;iv=0;
        repeat(4)@(negedge clk);rst=0;launch;feed;wait(done);
        $display("SCALER_CONTROL_TEST_PASS long stall/cancel all stages/reset restart");$finish;
    end
    initial begin #1000000;$fatal(1,"SCALER_CONTROL_TIMEOUT");end
endmodule
