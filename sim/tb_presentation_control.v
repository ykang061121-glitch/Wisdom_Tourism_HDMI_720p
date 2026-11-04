`timescale 1ns/1ps
module tb_presentation_control;
    reg clk=0,reset=1,boundary=0;
    reg [3:0] sw=0;
    wire [3:0] active;
    wire [1:0] mode,contrast;
    wire signed [7:0] brightness;
    wire sub_visible,wave_visible;
    reg [23:0] background=0;
    wire [23:0] rgb;
    integer pixels=0;
    always #5 clk=~clk;
    presentation_control #(.STABLE_CYCLES(8)) dut(.video_clk(clk),.reset(reset),
        .frame_boundary(boundary),.switches_async(sw),.switches_active(active),
        .preset_mode(mode),.brightness(brightness),.contrast(contrast),
        .subtitles_visible(sub_visible),.wave_visible(wave_visible));
    video_adjust adjust(.pixel_clk(clk),.reset(reset),.de(1'b1),.rgb_in(background),
        .brightness(brightness),.contrast(contrast),.rgb_out(rgb));
    function integer expected_channel(input integer v,m);
        integer centered,numerator,value;
        begin
            centered=v-128;
            case(m)
                1:begin numerator=centered*3;value=128+(numerator+3)/4-32;end
                2:value=v+16;
                3:begin numerator=centered*5;value=128+((numerator<0)?-((-numerator+3)/4):numerator/4);end
                default:value=v;
            endcase
            // SOFT is centered - floor(centered/4) == ceil(3*centered/4).
            if(m==1)value=128+((numerator<0)?-((-numerator)/4):(numerator+3)/4)-32;
            expected_channel=(value<0)?0:(value>255)?255:value;
        end
    endfunction
    task commit(input [3:0] selected);
        reg [3:0] previous;
        begin
            previous=active;@(negedge clk);sw=selected;
            repeat(20)@(negedge clk);
            if(active!==previous)$fatal(1,"switch changed outside frame boundary");
            boundary=1;@(negedge clk);boundary=0;
            if(active!==selected || mode!==selected[1:0] ||
               sub_visible!==!selected[2] || wave_visible!==!selected[3])
                $fatal(1,"switch atomic decode failure");
        end
    endtask
    integer m,v,pattern;
    reg [23:0] expected;
    initial begin
        repeat(4)@(negedge clk);reset=0;
        if(mode!=0 || brightness!=0 || contrast!=1 || !sub_visible || !wave_visible)
            $fatal(1,"neutral reset");
        // Bouncing 00->01->11 must not commit the transient 01.
        sw=1;repeat(4)@(negedge clk);sw=3;repeat(4)@(negedge clk);
        boundary=1;@(negedge clk);boundary=0;
        if(active!=0)$fatal(1,"unqualified simultaneous switches committed");
        for(m=0;m<4;m++)begin
            commit(m);
            if(brightness!==((m==1)?-8'sd32:(m==2)?8'sd16:8'sd0) ||
               contrast!==((m==1)?2'd0:(m==3)?2'd2:2'd1))
                $fatal(1,"preset parameter mismatch");
            for(v=0;v<256;v++)begin
                background={8'(v),8'(255-v),8'((v*73)%256)};#1;
                expected={8'(expected_channel(v,m)),8'(expected_channel(255-v,m)),
                          8'(expected_channel((v*73)%256,m))};
                if($test$plusargs("INJECT_PRESET") && m==1 && v==100) force dut.brightness=8'sd32;
                #1;
                if(rgb!==expected)begin
                    $display("INTERACTION_CHECKER_REJECT PRESET mode=%0d in=%h got=%h expected=%h",m,background,rgb,expected);
                    $fatal(1,"preset pixel/saturation failure");
                end
                pixels++;
            end
        end
        for(pattern=0;pattern<16;pattern++)commit(pattern);
        // Reset does not manufacture a switch edge: a held physical 1111
        // setting must be reapplied after stability + the next frame event.
        reset=1;repeat(3)@(negedge clk);reset=0;
        if(active!=0)$fatal(1,"reset defaults not neutral");
        commit(15);
        commit(0);
        $display("PRESENTATION_CONTROL_TEST_PASS pixels=%0d all_16_switches frame_atomic simultaneous debounce saturation",pixels);
        $finish;
    end
endmodule
