`timescale 1ns/1ps
module tb_interaction_osd;
    reg clk=0,src_clk=0,reset=1,de=1;
    reg [9:0] x=0,y=0;
    reg [1:0] mode=0;
    reg sub_visible=1,wave_visible=1,display_valid=1;
    reg [5:0] src_status=6'b101000;
    wire [5:0] status;
    wire [23:0] rgb;
    wire signed [7:0] brightness=(mode==1)?-8'sd32:(mode==2)?8'sd16:8'sd0;
    wire [1:0] contrast=(mode==1)?0:(mode==3)?2:1;
    always #20 clk=~clk;
    always #5 src_clk=~src_clk;
    `include "subtitle_reference.vh"
    osd_status_cdc #(.WIDTH(6)) cdc(.src_clk(src_clk),.src_reset(reset),.src_status(src_status),
        .dst_clk(clk),.dst_reset(reset),.dst_status(status));
    osd_overlay #(.SHOW_SETTINGS(1)) dut(.pixel_clk(clk),.reset(reset),.de(de),.x(x),.y(y),
        .background_rgb(24'h123456),.image_index(2'd0),.auto_play_enable(1'b1),
        .display_valid(display_valid),.brightness(brightness),.contrast(contrast),.fade_level(3'd4),
        .interval_code(status[5:4]),.preset_mode(mode),.subtitles_visible(sub_visible),
        .wave_visible(wave_visible),.osd_rgb(rgb));
    task text_check(input integer ox,oy,input string text_value);
        integer column,row,k;
        reg [23:0] expected;
        begin
            for(row=0;row<16;row++)for(column=0;column<88;column++)begin
                x=ox+column;y=oy+row;k=column/8;#1;
                expected=(k<text_value.len() && ref_dot(text_value[k],row/2,column%8))?24'hFFFFFF:24'h123456;
                if($test$plusargs("INJECT_OSD_STATUS") && ox==360 && oy==16 && row==0 && column==2)
                    force dut.interval_code=2'd3;
                #1;
                if(rgb!==expected)begin
                    $display("INTERACTION_CHECKER_REJECT OSD text=%s x=%0d y=%0d got=%h expected=%h",text_value,x,y,rgb,expected);
                    $fatal(1,"OSD disagrees with actual selection");
                end
            end
        end
    endtask
    integer m,t,hidden,checks=0;
    string label;
    initial begin
        repeat(4)@(negedge clk);reset=0;
        for(t=0;t<4;t++)begin
            @(negedge src_clk);src_status={2'(t),4'b1100};
            wait(status==src_status);repeat(3)@(negedge clk);
            for(m=0;m<4;m++)for(hidden=0;hidden<4;hidden++)begin
                mode=m;sub_visible=!hidden[0];wave_visible=!hidden[1];
                case(t)0:label="INT:01S";1:label="INT:03S";2:label="INT:05S";3:label="INT:10S";endcase
                text_check(360,16,label);
                case(m)0:label="MODE:NORMAL";1:label="MODE:SOFT";2:label="MODE:BRIGHT";3:label="MODE:VIVID";endcase
                text_check(360,36,label);
                text_check(360,56,sub_visible?"SUB:ON":"SUB:OFF");
                text_check(360,76,wave_visible?"WAVE:ON":"WAVE:OFF");
                case(m)1:label="BRI:-32";2:label="BRI:+16";default:label="BRI:+00";endcase
                text_check(16,76,label);
                case(m)1:label="CON:075";3:label="CON:125";default:label="CON:100";endcase
                text_check(16,96,label);checks++;
            end
        end
        // Both hidden + LOADING must retain necessary status text.
        display_valid=0;sub_visible=0;wave_visible=0;
        text_check(16,16,"LOADING");text_check(360,56,"SUB:OFF");text_check(360,76,"WAVE:OFF");
        x=500;y=150;#1;if(rgb!==24'h123456)$fatal(1,"OSD polluted other areas");
        de=0;#1;if(rgb!==0)$fatal(1,"DE blanking");
        $display("INTERACTION_OSD_TEST_PASS combinations=%0d independent_glyphs BRI_CON interval_mode_hide loading CDC6",checks);$finish;
    end
    initial begin #10000000;$fatal(1,"settings OSD timeout");end
endmodule
