// Five pixel stages. Exact truncation toward zero of (c-128)*percent/100.
// Supported percent is a multiple of 5 in [50,200]. All sidebands share latency.
module video_adjust_percent # (parameter COORD_BITS=11)(
 input wire pixel_clk,reset,hs,vs,de,
 input wire [COORD_BITS-1:0] x,y,
 input wire [23:0] rgb_in,
 input wire signed [7:0] brightness,
 input wire [7:0] contrast_percent,
 output wire out_hs,out_vs,out_de,
 output wire [COORD_BITS-1:0] out_x,out_y,
 output reg [23:0] rgb_out
);
 localparam SIDE=3+2*COORD_BITS;
 reg [SIDE-1:0] side[0:4];
 reg [7:0] magnitude[0:2];
 reg [5:0] gain;
 reg [13:0] product[0:2];
 reg [25:0] partial_a[0:2],partial_b[0:2];
 wire [25:0] reciprocal[0:2];
 reg [8:0] quotient[0:2];
 reg [2:0] negative[0:3];
 reg signed [7:0] bri[0:3];
 integer i;
 assign {out_hs,out_vs,out_de,out_x,out_y}=side[4];
 generate genvar ch;for(ch=0;ch<3;ch=ch+1)begin: sum_stage
   assign reciprocal[ch]=partial_a[ch]+partial_b[ch];
 end endgenerate
 function [7:0] finish_channel;
   input [8:0] q;input neg;input signed[7:0] b;
   reg signed[10:0] value;
   begin
    value=11'sd128+(neg?-$signed({2'b0,q}):$signed({2'b0,q}))+
           $signed({{3{b[7]}},b});
    if(value<0)finish_channel=0;
    else if(value>255)finish_channel=255;
    else finish_channel=value[7:0];
   end
 endfunction
 always @(posedge pixel_clk or posedge reset)begin
  if(reset)begin
   gain<=20;rgb_out<=0;
   for(i=0;i<5;i=i+1)side[i]<=0;
   for(i=0;i<4;i=i+1)begin negative[i]<=0;bri[i]<=0;end
   for(i=0;i<3;i=i+1)begin magnitude[i]<=0;product[i]<=0;
      partial_a[i]<=0;partial_b[i]<=0;quotient[i]<=0;end
  end else begin
   side[0]<={hs,vs,de,x,y};for(i=1;i<5;i=i+1)side[i]<=side[i-1];
   gain<=contrast_percent/5;
   bri[0]<=brightness;
   for(i=1;i<4;i=i+1)begin bri[i]<=bri[i-1];negative[i]<=negative[i-1];end
   for(i=0;i<3;i=i+1)begin
    negative[0][i]<=!rgb_in[i*8+7];
    magnitude[i]<=rgb_in[i*8+7]?{1'b0,rgb_in[i*8+:7]}:8'd128-rgb_in[i*8+:8];
    product[i]<=magnitude[i]*gain;
    // ceil(2^16/20)=3277. For p=0..5120, floor(p*3277/65536)=floor(p/20).
    partial_a[i]<=({12'b0,product[i]}<<11)+({12'b0,product[i]}<<10)+({12'b0,product[i]}<<7);
    partial_b[i]<=({12'b0,product[i]}<<6)+({12'b0,product[i]}<<3)+({12'b0,product[i]}<<2)+{12'b0,product[i]};
    quotient[i]<=reciprocal[i][24:16];
    rgb_out[i*8+:8]<=side[3][2*COORD_BITS]?finish_channel(quotient[i],negative[3][i],bri[3]):8'd0;
   end
  end
 end
endmodule
