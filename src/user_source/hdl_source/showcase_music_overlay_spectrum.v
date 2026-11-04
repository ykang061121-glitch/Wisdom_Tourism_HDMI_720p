`ifndef SHOWCASE_MUSIC_OVERLAY_SPECTRUM_V
`define SHOWCASE_MUSIC_OVERLAY_SPECTRUM_V
// D1 fast music overlay: exact same ONE pixel-cycle geometry/PCM RAM phase.
// Only the eight score-derived bars are replaced with 16 real PCM bands.
module showcase_music_overlay_spectrum #(parameter COORD_BITS=10, parameter VIDEO_720P=0)(
    input wire pixel_clk,reset,hs,vs,de,visible,
    input wire [COORD_BITS-1:0] x,y,
    input wire [23:0] background_rgb,
    input wire [9:0] music_status,
    input wire [127:0] spectrum_levels,
    input wire signed [7:0] sample_amplitude,
    input wire sample_valid,
    output wire [7:0] sample_index,
    output reg out_hs,out_vs,out_de,
    output reg [COORD_BITS-1:0] out_x,out_y,
    output reg [23:0] output_rgb
);
    localparam X_SHIFT=VIDEO_720P?632:0, Y_SHIFT=VIDEO_720P?240:0;
    reg [23:0] background_d;
    reg visible_d;
    reg panel_d,border_d,separator_d,strip_d,center_d;
    reg [15:0] bar_d;
    reg [7:0] pcm_hit_d;
    // One shared vertical subtraction, rather than 16 level-dependent ones.
    wire [COORD_BITS:0] bar_y_distance = (439+Y_SHIFT) - {1'b0,y};
    genvar g;
    generate for(g=0;g<16;g=g+1)begin:bands
        // 16 x (11 lit + 2 gap) = 208 pixels; band 0 is lowest frequency.
        // 0..255 -> 0..31 pixels. Strict > makes level zero truly empty.
        wire [4:0] height = spectrum_levels[g*8+3 +: 5];
        always @(posedge pixel_clk or posedge reset)
            if(reset)bar_d[g]<=0;
            else bar_d[g]<=height!=0 &&
                           x>=408+X_SHIFT+g*13 && x<419+X_SHIFT+g*13 &&
                           y<=439+Y_SHIFT && bar_y_distance<height;
    end endgenerate
    generate for(g=0;g<8;g=g+1)begin:pcm
        // Existing signed PCM >>>5 line masks, evaluated before RAM returns.
        localparam integer PCM_TOP=447+Y_SHIFT-((g<4)?g:(g-8));
        always @(posedge pixel_clk or posedge reset)
            if(reset)pcm_hit_d[g]<=0;
            else pcm_hit_d[g]<=(y==PCM_TOP || y==PCM_TOP+1);
    end endgenerate
    assign sample_index=(x>=408+X_SHIFT && x<624+X_SHIFT)?(x-(408+X_SHIFT)):8'd0;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin
            out_hs<=0;out_vs<=0;out_de<=0;out_x<=0;out_y<=0;
            background_d<=0;visible_d<=0;
            panel_d<=0;border_d<=0;separator_d<=0;strip_d<=0;center_d<=0;
        end else begin
            out_hs<=hs;out_vs<=vs;out_de<=de;out_x<=x;out_y<=y;
            background_d<=background_rgb;visible_d<=visible;
            panel_d<=x>=400+X_SHIFT && x<=631+X_SHIFT && y>=375+Y_SHIFT && y<=451+Y_SHIFT;
            border_d<=x==400+X_SHIFT || x==631+X_SHIFT || y==375+Y_SHIFT || y==451+Y_SHIFT;
            separator_d<=y==398+Y_SHIFT;
            strip_d<=x>=408+X_SHIFT && x<=623+X_SHIFT && y>=445+Y_SHIFT && y<=449+Y_SHIFT;
            center_d<=y==447+Y_SHIFT;
        end
    end
    integer k;
    always @*begin
        output_rgb=background_d;
        if(reset || !out_de)output_rgb=0;
        else if(visible_d && panel_d)begin
            output_rgb=24'h0B1725;
            if(border_d)output_rgb=24'h245674;
            else begin
                if(separator_d)output_rgb=24'h163C54;
                for(k=0;k<16;k=k+1)if(bar_d[k])begin
                    if(k<4)output_rgb=24'h00EEA0;
                    else if(k<8)output_rgb=24'h28CFE8;
                    else if(k<12)output_rgb=24'h4294F0;
                    else output_rgb=24'hA878EC;
                end
                if(strip_d)begin
                    output_rgb=center_d?24'h254459:24'h101E30;
                    if(sample_valid && pcm_hit_d[sample_amplitude[7:5]])output_rgb=24'h00FF80;
                end
            end
        end
    end
    // music_status remains in the compatible interface. M/NOTE/STEP glyphs
    // still use it in the unchanged downstream showcase_ui_pipeline stage.
endmodule
`endif
