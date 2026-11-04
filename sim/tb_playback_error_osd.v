`timescale 1ns/1ps
module tb_playback_error_osd;
    reg clk=0,reset=1,boundary=0,hs=1,vs=1,de=0;
    reg [9:0] x=0,y=0;
    reg [23:0] background=24'hFFFFFF;
    reg [7:0] error=0,golden_error=0;
    reg [1:0] preset=0;
    reg sub=1,vis=1;
    wire oh,ov,od,ph,pv,pd;
    wire [9:0] ox,oy,px,py;
    wire [23:0] rgb,plain;
    always #5 clk=~clk;
    `include "subtitle_reference.vh"
    showcase_presentation dut(.pixel_clk(clk),.reset(reset),.frame_boundary(boundary),
        .hs(hs),.vs(vs),.de(de),.x(x),.y(y),.background_rgb(background),
        .subtitles_visible(sub),.visual_visible(vis),.sample_amplitude(-8'sd17),.sample_valid(1'b1),
        .sample_index(),.audio_status(10'b1101011111),.error_status(error),
        .display_commit(1'b0),.display_valid(1'b1),.auto_play_enable(1'b0),
        .image_index(2'd2),.interval_code(2'd2),.preset_mode(preset),.brightness(8'sd0),
        .contrast(2'd1),.fade_level(3'd4),.out_hs(oh),.out_vs(ov),.out_de(od),
        .out_x(ox),.out_y(oy),.output_rgb(rgb));
    showcase_presentation reference(.pixel_clk(clk),.reset(reset),.frame_boundary(boundary),
        .hs(hs),.vs(vs),.de(de),.x(x),.y(y),.background_rgb(background),
        .subtitles_visible(sub),.visual_visible(vis),.sample_amplitude(-8'sd17),.sample_valid(1'b1),
        .sample_index(),.audio_status(10'b1101011111),.error_status(8'd0),
        .display_commit(1'b0),.display_valid(1'b1),.auto_play_enable(1'b0),
        .image_index(2'd2),.interval_code(2'd2),.preset_mode(preset),.brightness(8'sd0),
        .contrast(2'd1),.fade_level(3'd4),.out_hs(ph),.out_vs(pv),.out_de(pd),
        .out_x(px),.out_y(py),.output_rgb(plain));
    function automatic string message(input [7:0] code);
        case(code)
            8'hE0:message="BMP FORMAT ERROR";8'hE1:message="BMP SIZE ERROR";
            8'hE2:message="BMP LENGTH ERROR";8'hE3:message="SD READ ERROR";
            8'hE4:message="NO BMP FOUND";8'hEF:message="LOAD CANCELLED";
            default:message="";
        endcase
    endfunction
    function automatic bit dot(input integer xx,yy,input [7:0] code);
        string s;
        integer col,idx,ascii;
        begin
            dot=0;s=message(code);
            if(xx>=16 && xx<208 && yy>=48 && yy<64)begin
                idx=(xx-16)/8;col=(xx-16)%8;
                ascii=idx<s.len()?s.getc(idx):32;
                dot=ref_dot(ascii,(yy-48)/2,col);
            end
        end
    endfunction
    reg [22:0] qmeta[0:4];
    reg [23:0] qbg[0:4];
    reg [7:0] qerror[0:4];
    reg [23:0] expected,observed;
    integer pipe=0,checks=0,glyphs=0,transparent=0,panel=0,frames=0,valid_pixels=0;
    task reject(input [255:0] reason);
        begin $display("RECOVERY_CHECKER_REJECT %0s",reason);$fatal(1,"error OSD checker");end
    endtask
    always @(posedge clk)begin
        if(reset)begin pipe=0;golden_error=0;end
        else begin
            if(boundary)golden_error=error;
            for(integer j=4;j>0;j--)begin qmeta[j]=qmeta[j-1];qbg[j]=qbg[j-1];qerror[j]=qerror[j-1];end
            qmeta[0]={hs,vs,de,x,y};qbg[0]=background;qerror[0]=golden_error;
            #0.1;
            if(pipe<6)pipe++;
            else begin
                if({oh,ov,od,ox,oy}!==qmeta[4] || {ph,pv,pd,px,py}!==qmeta[4])
                    reject("error text shifted video timing");
                expected=plain;
                if(od && message(qerror[4])!="" && ox>=16 && ox<208 && oy>=48 && oy<64)begin
                    if(dot(ox,oy,qerror[4]))begin expected=24'hFFAD48;glyphs++;end
                    else if(dot(ox-1,oy,qerror[4]) || dot(ox+1,oy,qerror[4]))expected=0;
                    else begin expected=qbg[4];transparent++;end
                end
                observed=rgb;
                // Mutate recorded pixels, not reference glyphs/checker rules.
                if($test$plusargs("INJECT_ERROR_PLATE") && od && oy==48 && ox==17)
                    observed=24'h182030;
                if($test$plusargs("INJECT_ERROR_GLYPH") && od && dot(ox,oy,qerror[4]))
                    observed=qbg[4];
                if(observed!==expected)reject("wrong glyph/opaque error plate/frame tear");
                if(od && oy>=375 && oy<=451 && ox>=400 && ox<=631)begin
                    if(rgb!==plain)reject("error damaged satisfied music panel");panel++;
                end
                if(od)begin checks++;valid_pixels++;end
                else if(rgb!==0)reject("error emitted invalid DE pixel");
            end
        end
    end
    task frame_boundary;
        begin @(negedge clk);de=0;boundary=1;@(negedge clk);boundary=0;repeat(8)@(negedge clk);end
    endtask
    task raster(input integer full);
        integer xx,yy;
        begin
            valid_pixels=0;
            for(yy=full?0:40;yy<(full?525:72);yy++)for(xx=0;xx<800;xx++)begin
                @(negedge clk);x=xx<640?xx:0;y=yy<480?yy:0;de=xx<640 && yy<480;
                hs=!(xx>=656 && xx<752);vs=!(yy>=490 && yy<492);
            end
            @(negedge clk);de=0;repeat(8)@(negedge clk);
            if(full && valid_pixels!=307200)reject("error lost full-raster pixels");
            if(full)frames++;
        end
    endtask
    reg [7:0] codes[0:5];
    integer n;
    initial begin
        codes[0]=8'hE0;codes[1]=8'hE1;codes[2]=8'hE2;
        codes[3]=8'hE3;codes[4]=8'hE4;codes[5]=8'hEF;
        repeat(6)@(negedge clk);reset=0;
        for(n=0;n<6;n++)begin
            background=n[0]?24'hFFFFFF:24'h061010;
            error=codes[n];preset=n%4;frame_boundary;raster(n==0 || n==1);
            // Mid-frame clear must not change this frame's error snapshot.
            error=0;raster(0);frame_boundary;raster(0);
        end
        sub=0;vis=0;error=8'hE3;frame_boundary;raster(1);
        sub=1;vis=1;frame_boundary;raster(1);
        @(negedge clk);reset=1;repeat(8)@(negedge clk);error=0;reset=0;frame_boundary;raster(1);
        if(frames!=5 || glyphs<100 || transparent<100 || panel<10000)
            reject("insufficient error OSD coverage");
        $display("PLAYBACK_ERROR_OSD_TEST_PASS pixels=%0d glyphs=%0d transparent=%0d panel=%0d frames=%0d",checks,glyphs,transparent,panel,frames);
        $finish;
    end
    initial begin #100000000;reject("error OSD timeout");end
endmodule
