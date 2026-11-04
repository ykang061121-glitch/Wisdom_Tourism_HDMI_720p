// Observation only, entirely in video_clk. State changes in vertical blanking.
module diagnostic_frame_phase #(parameter HOLD_FRAMES=180)(
 input wire pixel_clk,reset,frame_boundary,enable,
 (* keep="true", preserve="true", dont_touch="true" *) output reg [1:0] phase
);
 localparam BITS=HOLD_FRAMES<=1?1:$clog2(HOLD_FRAMES);
 (* keep="true", preserve="true", dont_touch="true" *) reg [BITS-1:0] frames;
 always @(posedge pixel_clk or posedge reset)begin
  if(reset)begin phase<=0;frames<=0;end
  else if(frame_boundary && enable)begin
   if(frames==HOLD_FRAMES-1)begin frames<=0;phase<=phase+1'b1;end
   else frames<=frames+1'b1;
  end
 end
endmodule
