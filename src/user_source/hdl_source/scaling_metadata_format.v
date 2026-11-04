// Source/control clock only. One committed-scene snapshot, eleven double-
// dabble steps, one atomic BCD output. No video-domain division/multiplication.
module scaling_metadata_format(
    input wire clk,reset,
    input wire [1:0] image_index,
    input wire [43:0] scaling_meta,
    output reg valid,
    output reg [1:0] formatted_image,
    output reg [63:0] bcd
);
    reg [45:0] previous;
    reg [43:0] work;
    reg [1:0] image_latch;
    reg [3:0] count;
    reg active;
    reg [15:0] a,b,c,d;
    function [15:0] add3;
        input [15:0] v;
        integer i;
        begin
            add3=v;
            for(i=0;i<4;i=i+1)
                if(v[i*4+:4]>=5)add3[i*4+:4]=v[i*4+:4]+4'd3;
        end
    endfunction
    wire [15:0] na=(add3(a)<<1)|{15'd0,work[43]};
    wire [15:0] nb=(add3(b)<<1)|{15'd0,work[32]};
    wire [15:0] nc=(add3(c)<<1)|{15'd0,work[21]};
    wire [15:0] nd=(add3(d)<<1)|{15'd0,work[10]};
    always @(posedge clk or posedge reset)begin
        if(reset)begin previous<=0;work<=0;image_latch<=0;count<=0;active<=0;
            a<=0;b<=0;c<=0;d<=0;bcd<=0;valid<=0;formatted_image<=0;end
        else if(!active)begin
            if({image_index,scaling_meta}!=previous && scaling_meta!=0)begin
                previous<={image_index,scaling_meta};work<=scaling_meta;
                image_latch<=image_index;active<=1;count<=0;a<=0;b<=0;c<=0;d<=0;
            end
        end else begin
            a<=na;b<=nb;c<=nc;d<=nd;work<=work<<1;count<=count+1'b1;
            if(count==10)begin
                active<=0;valid<=1;formatted_image<=image_latch;bcd<={na,nb,nc,nd};
            end
        end
    end
endmodule
