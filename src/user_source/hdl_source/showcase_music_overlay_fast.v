`ifndef SHOWCASE_MUSIC_OVERLAY_FAST_V
`define SHOWCASE_MUSIC_OVERLAY_FAST_V
// Same ONE pixel-cycle interface and PCM RAM phase as showcase_music_overlay.
// Move geometry to the existing input registers, not to a new pixel stage.
module showcase_music_overlay_fast #(parameter COORD_BITS=10, parameter VIDEO_720P=0)(
    input wire pixel_clk,reset,hs,vs,de,visible,
    input wire [COORD_BITS-1:0] x,y,
    input wire [23:0] background_rgb,
    input wire [9:0] music_status,
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
    reg [9:0] status_d;
    reg panel_d,border_d,separator_d,strip_d,center_d;
    reg [7:0] bar_d,pcm_hit_d;
    wire [3:0] pitch[0:7];
    genvar g;
    generate for(g=0;g<8;g=g+1)begin:score
        image_melody_rom notes(.image_index(music_status[8:7]),.note_index(g[2:0]),
            .phase_increment(),.note_samples(),.pitch_code(pitch[g]));
        // Each comparison feeds its own register. Color selection no longer
        // includes y/height subtraction or x/panel arithmetic after this edge.
        always @(posedge pixel_clk or posedge reset)
            if(reset)bar_d[g]<=0;
            else bar_d[g]<=x>=408+X_SHIFT+g*27 && x<426+X_SHIFT+g*27 && y<=439+Y_SHIFT &&
                           y>=439+Y_SHIFT-(4+{pitch[g],1'b0});
        // signed PCM >>>5 is exactly signed sample_amplitude[7:5]. Encode
        // its eight possible 2-pixel line masks BEFORE the RAM read returns.
        localparam integer PCM_TOP=447+Y_SHIFT-((g<4)?g:(g-8));
        always @(posedge pixel_clk or posedge reset)
            if(reset)pcm_hit_d[g]<=0;
            else pcm_hit_d[g]<=(y==PCM_TOP || y==PCM_TOP+1);
    end endgenerate
    assign sample_index=(x>=408+X_SHIFT && x<624+X_SHIFT)?(x-(408+X_SHIFT)):8'd0;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin
            out_hs<=0;out_vs<=0;out_de<=0;out_x<=0;out_y<=0;
            background_d<=0;visible_d<=0;status_d<=0;
            panel_d<=0;border_d<=0;separator_d<=0;strip_d<=0;center_d<=0;
        end else begin
            out_hs<=hs;out_vs<=vs;out_de<=de;out_x<=x;out_y<=y;
            background_d<=background_rgb;visible_d<=visible;status_d<=music_status;
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
                for(k=0;k<8;k=k+1)if(bar_d[k])begin
                    if(status_d[9] && k==status_d[6:4])
                        output_rgb=status_d[0]?24'h00FF9A:24'h4F8D83;
                    else if(status_d[9] && k<status_d[6:4])output_rgb=24'h287DA8;
                    else output_rgb=24'h12384F;
                end
                if(strip_d)begin
                    output_rgb=center_d?24'h254459:24'h101E30;
                    if(sample_valid && pcm_hit_d[sample_amplitude[7:5]])output_rgb=24'h00FF80;
                end
            end
        end
    end
endmodule
`endif
