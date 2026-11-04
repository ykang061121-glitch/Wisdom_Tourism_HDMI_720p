// ONE pixel cycle, matching the unchanged real-PCM capture RAM's read latency.
// Eight bar pitches come from the SAME ROM used by DDS, not a duplicate score.
module showcase_music_overlay(
    input wire pixel_clk,reset,hs,vs,de,visible,
    input wire [9:0] x,y,
    input wire [23:0] background_rgb,
    input wire [9:0] music_status,
    input wire signed [7:0] sample_amplitude,
    input wire sample_valid,
    output wire [7:0] sample_index,
    output reg out_hs,out_vs,out_de,
    output reg [9:0] out_x,out_y,
    output reg [23:0] output_rgb
);
    reg [23:0] background_d;
    reg visible_d;
    reg [9:0] status_d;
    wire [3:0] pitch[0:7];
    genvar g;
    generate for(g=0;g<8;g=g+1)begin:score
        image_melody_rom notes(.image_index(status_d[8:7]),.note_index(g[2:0]),
            .phase_increment(),.note_samples(),.pitch_code(pitch[g]));
    end endgenerate
    assign sample_index=(x>=408 && x<624)?(x-408):8'd0;
    wire signed [10:0] amplitude_ext={{3{sample_amplitude[7]}},sample_amplitude};
    wire signed [10:0] target_y=11'sd447-(amplitude_ext>>>5);
    wire signed [10:0] pixel_y={1'b0,out_y};
    integer k;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin
            out_hs<=0;out_vs<=0;out_de<=0;out_x<=0;out_y<=0;
            background_d<=0;visible_d<=0;status_d<=0;
        end else begin
            out_hs<=hs;out_vs<=vs;out_de<=de;out_x<=x;out_y<=y;
            background_d<=background_rgb;visible_d<=visible;status_d<=music_status;
        end
    end
    always @* begin
        output_rgb=background_d;
        if(reset || !out_de)output_rgb=0;
        else if(visible_d && out_x>=400 && out_x<=631 && out_y>=375 && out_y<=451)begin
            output_rgb=24'h0B1725;
            if(out_x==400 || out_x==631 || out_y==375 || out_y==451)output_rgb=24'h245674;
            else begin
                if(out_y==398)output_rgb=24'h163C54;
                for(k=0;k<8;k=k+1)begin
                    if(out_x>=408+k*27 && out_x<426+k*27 && out_y<=439 &&
                       out_y>=439-(4+{pitch[k],1'b0}))begin
                        if(status_d[9] && k==status_d[6:4])
                            output_rgb=status_d[0]?24'h00FF9A:24'h4F8D83;
                        else if(status_d[9] && k<status_d[6:4])output_rgb=24'h287DA8;
                        else output_rgb=24'h12384F;
                    end
                end
                // Small proof-of-real-PCM strip, not a decorative oscillator.
                if(out_x>=408 && out_x<=623 && out_y>=445 && out_y<=449)begin
                    output_rgb=24'h101E30;
                    if(out_y==447)output_rgb=24'h254459;
                    if(sample_valid && out_x>=408 && out_x<624 &&
                       pixel_y>=target_y && pixel_y<=target_y+11'sd1)output_rgb=24'h00FF80;
                end
            end
        end
    end
endmodule


