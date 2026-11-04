// Fixed 19-character Chinese subset + space, generated from installed SimSun.
// A one-clock ROM without reset; pixel validity masks startup.
module fixed_chinese_row_rom(
 input wire pixel_clk,
 input wire [4:0] glyph_id,
 input wire [3:0] glyph_row,
 output reg [15:0] row_bits
);
 reg [15:0]rom[0:511];integer i;
 initial begin
  for(i=0;i<512;i=i+1)rom[i]=16'd0;
  `include "fixed_chinese16_init.vh"
 end
 always @(posedge pixel_clk)row_bits<=rom[{glyph_id,glyph_row}];
endmodule
