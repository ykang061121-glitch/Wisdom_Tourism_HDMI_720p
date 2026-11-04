`timescale 1ns/1ps
module tb_playback_progress #(parameter integer CLOCK_FREQ=1000);
  reg clk=0,vclk=0,reset=1,key=1,enable=0,restart=0;
  always #5 clk=~clk;
  always #7 vclk=~vclk;
  wire [1:0] code;wire press,tick,running;wire [8:0] units;
  playback_interval_control #(.CLK_FREQ_HZ(CLOCK_FREQ)) dut(
    .clk(clk),.reset(reset),.key_interval(key),.timer_enable(enable),.timer_restart(restart),
    .interval_code(code),.interval_press(press),.auto_tick(tick),.progress_running(running),.progress_units(units));
  wire [9:0] received;
  osd_status_cdc #(.WIDTH(10)) mailbox(.src_clk(clk),.src_reset(reset),.src_status({running,units}),
    .dst_clk(vclk),.dst_reset(reset),.dst_status(received));
  reg frame=0;reg [9:0] stable=0;
  always @(posedge vclk)begin
    if(reset)stable<=0;else if(frame)stable<=received;
  end
  integer elapsed=0,seconds=5,previous_elapsed,expected,checks=0,ticks=0;
  integer history_cycle=0,last_frame_cycle=0;
  reg old_press;reg [8:0] observed;
  reg [9:0] history[0:127];
  always @(posedge clk)begin
    if(reset)begin elapsed=0;history_cycle=0;for(integer j=0;j<128;j++)history[j]=0;end
    else begin
      previous_elapsed=elapsed;old_press=press;
      case(code)0:seconds=5;1:seconds=3;2:seconds=5;default:seconds=10;endcase
      if(!enable || restart || old_press)elapsed=0;else elapsed++;
      #0.1;
      expected=(!enable || restart || old_press)?0:(previous_elapsed*256)/(CLOCK_FREQ*seconds);
      if(elapsed==CLOCK_FREQ*seconds)begin expected=256;elapsed=0;end
      observed=units;
      if($test$plusargs("INJECT_PROGRESS_DESYNC") && running && units>=32)observed=units+16;
      if(observed!==expected[8:0] || tick!==(expected==256))begin
        $display("ADVANCED_CHECKER_REJECT PROGRESS expected=%0d got=%0d elapsed=%0d code=%0d",expected,observed,elapsed,code);
        $fatal(1,"progress differs from actual timer oracle");
      end
      if(tick)ticks++;
      for(integer j=127;j>0;j--)history[j]=history[j-1];
      history[0]={running,units};history_cycle++;checks++;
    end
  end
  reg [9:0] old_stable;
  integer matching_bundles;
  always @(posedge vclk)begin
    old_stable=stable;#0.2;
    if(!reset)begin
      matching_bundles=0;for(integer j=0;j<128;j++)if(received===history[j])matching_bundles++;
      if(matching_bundles==0)$fatal(1,"torn or excessively stale progress mailbox");
      if(!frame && stable!==old_stable)$fatal(1,"progress changed inside frame");
    end
  end
  reg de=1,visible=1;reg [9:0] x=0,y=475;reg [8:0] draw_units=0;
  wire [23:0] rgb;reg [23:0] seen,reference;
  playback_progress_overlay bar(.reset(reset),.de(de),.visible(visible),.x(x),.y(y),
    .progress_units(draw_units),.background_rgb(24'h9a3c72),.output_rgb(rgb));
  task keypress;begin @(negedge clk);key=0;repeat(28)@(negedge clk);key=1;repeat(28)@(negedge clk);end endtask
  integer before_tick,n,px,py,value;
  initial begin
    repeat(6)@(negedge clk);reset=0;
    for(n=0;n<4;n++)begin
      keypress;@(negedge clk);enable=1;before_tick=ticks;
      wait(ticks==before_tick+1);@(negedge clk);enable=0;repeat(20)@(negedge clk);
    end
    enable=1;repeat(700)@(negedge clk);keypress;
    repeat(400)@(negedge clk);restart=1;repeat(3)@(negedge clk);restart=0;
    repeat(900)@(negedge clk);enable=0;repeat(14000)@(negedge clk);
    enable=1;repeat(800)@(negedge clk);enable=0;
    for(n=0;n<9;n++)begin
      value=(n==8)?256:n*32;draw_units=value;
      for(py=474;py<=478;py++)for(px=0;px<640;px++)begin
        @(negedge clk);x=px;y=py;#1;
        reference=(py>=475 && py<=477 && px>=16 && px<624 && px-16<(value*608)/256)?24'h38E8DC:24'h9a3c72;
        seen=rgb;
        if($test$plusargs("INJECT_PROGRESS_LAYER") && py==474 && px==16)seen=24'h38E8DC;
        if(seen!==reference)begin $display("ADVANCED_CHECKER_REJECT PROGRESS_LAYER");$fatal(1,"bar boundary/transparent pixel mismatch");end
      end
    end
    visible=0;#1;if(rgb!==24'h9a3c72)$fatal(1,"manual progress not hidden");
    de=0;#1;if(rgb!==0)$fatal(1,"blanking not black");
    reset=1;repeat(3)@(negedge clk);reset=0;repeat(3)@(negedge clk);
    if(units!=0 || running)$fatal(1,"progress reset");
    $display("PLAYBACK_PROGRESS_TEST_PASS timer_3_5_10 debounce restart busy CDC pixels checks=%0d",checks);$finish;
  end
  always begin repeat(50)@(negedge vclk);frame=1;@(negedge vclk);frame=0;end
  initial begin #2000000;$fatal(1,"progress timeout");end
endmodule
module tb_playback_progress_exact;
  tb_playback_progress #(.CLOCK_FREQ(1024)) exact_division();
endmodule
