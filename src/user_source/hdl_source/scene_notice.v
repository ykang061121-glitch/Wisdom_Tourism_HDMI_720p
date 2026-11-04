// A successful VIDEO-domain buffer commit is the only trigger. No key/mode/
// pending load input exists. Retrigger replaces the card; reset removes it.
module scene_notice #(parameter integer NOTICE_FRAMES=72)(
    input wire pixel_clk,reset,frame_boundary,
    input wire display_commit,display_valid,
    input wire [1:0] display_image,
    output reg visible,
    output reg [1:0] scene_index
);
    localparam integer COUNT_BITS=NOTICE_FRAMES<=1?1:$clog2(NOTICE_FRAMES+1);
    reg [COUNT_BITS-1:0] remaining;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin visible<=0;scene_index<=0;remaining<=0;end
        else if(!display_valid)begin visible<=0;remaining<=0;end
        else if(display_commit)begin
            visible<=1;scene_index<=display_image;remaining<=NOTICE_FRAMES;
        end else if(frame_boundary && remaining!=0)begin
            remaining<=remaining-1'b1;
            if(remaining==1)visible<=0;
        end
    end
endmodule


