// Exact five-clock reference path, with the same blanking convention as adjust.
module pixel_identity_delay #(parameter COORD_BITS=11)(
 input wire pixel_clk,reset,hs,vs,de,
 input wire [COORD_BITS-1:0] x,y,
 input wire [23:0] rgb,
 output wire out_hs,out_vs,out_de,
 output wire [COORD_BITS-1:0] out_x,out_y,
 output wire [23:0] out_rgb
);
 localparam WIDTH=27+2*COORD_BITS;
 (* keep="true", preserve="true", dont_touch="true" *) reg [WIDTH-1:0] pipeline[0:4];integer i;
 always @(posedge pixel_clk or posedge reset)begin
  if(reset)for(i=0;i<5;i=i+1)pipeline[i]<=0;
  else begin
   pipeline[0]<={hs,vs,de,x,y,(de?rgb:24'd0)};
   for(i=1;i<5;i=i+1)pipeline[i]<=pipeline[i-1];
  end
 end
 assign {out_hs,out_vs,out_de,out_x,out_y,out_rgb}=pipeline[4];
endmodule
