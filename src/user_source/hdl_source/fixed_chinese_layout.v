// Combinational layout only; pair its outputs with one synchronous glyph read.
// Scene/enable must already be held for a complete frame.
module fixed_chinese_layout #(
 parameter COORD_BITS=11, X_ORIGIN=24, Y_ORIGIN=600
)(
 input wire [COORD_BITS-1:0]x,y,
 input wire [1:0]scene,
 input wire enable,
 output wire inside_text,
 output wire [4:0]glyph_id,
 output wire [3:0]glyph_row,glyph_column
);
 wire [COORD_BITS:0]rx={1'b0,x}-X_ORIGIN;
 wire [COORD_BITS:0]ry={1'b0,y}-Y_ORIGIN;
 wire [3:0]cell_index=rx[7:4];
 wire [3:0]cells=scene==2'd3 ? 4'd10 : 4'd9;
 reg [4:0]code;
 always @*begin
  code=0;
  case({scene,cell_index})
   `include "fixed_chinese_text_decode.vh"
   default:code=0;
  endcase
 end
 assign inside_text=enable && x>=X_ORIGIN && y>=Y_ORIGIN &&
                    ry<16 && rx<({1'b0,cells,4'd0});
 assign glyph_id=inside_text?code:5'd0;
 assign glyph_row=inside_text?ry[3:0]:4'd0;
 assign glyph_column=rx[3:0];
endmodule
