// Two pixel stages AFTER the normal complete UI, shared by every diagnostic
// phase. No control feedback and no change to HDMI geometry or clocking.
module hdmi_diagnostic_overlay #(parameter PATTERNS=0,parameter COORD_BITS=11,
 parameter SHOW_DIAGNOSTIC_LABEL=1,parameter SHOW_FIXED_CHINESE=0,
 parameter CHINESE_X_ORIGIN=24,parameter CHINESE_Y_ORIGIN=600)(
 input wire pixel_clk,reset,hs,vs,de,
 input wire [COORD_BITS-1:0] x,y,
 input wire [23:0] rgb,
 input wire [1:0] phase,
 input wire frame_boundary,
 input wire [1:0] scene_index,
 input wire chinese_enable,
 output reg out_hs,out_vs,out_de,
 output reg [COORD_BITS-1:0] out_x,out_y,
 output reg [23:0] out_rgb
);

 // Control-only blanking snapshot: commits publish scene identity by NBA at
 // the boundary. Observe it one clock later without adding any pixel stage.
 reg chinese_boundary_pending,chinese_frame_enable;
 reg [1:0] chinese_frame_scene;
 always @(posedge pixel_clk or posedge reset)
  if(reset)begin
   chinese_boundary_pending<=0;chinese_frame_enable<=0;chinese_frame_scene<=0;
  end else begin
   chinese_boundary_pending<=frame_boundary;
   if(chinese_boundary_pending)begin
    chinese_frame_scene<=scene_index;chinese_frame_enable<=chinese_enable;
   end
  end
 wire chinese_window;
 wire [4:0] chinese_glyph;
 wire [3:0] chinese_row,chinese_column;
 wire [15:0] chinese_bits;
 fixed_chinese_layout #(.COORD_BITS(COORD_BITS),.X_ORIGIN(CHINESE_X_ORIGIN),.Y_ORIGIN(CHINESE_Y_ORIGIN)) chinese_layout(
  .x(x),.y(y),.scene(chinese_frame_scene),.enable(SHOW_FIXED_CHINESE && chinese_frame_enable),
  .inside_text(chinese_window),.glyph_id(chinese_glyph),.glyph_row(chinese_row),.glyph_column(chinese_column));
 fixed_chinese_row_rom chinese_font(.pixel_clk(pixel_clk),.glyph_id(chinese_glyph),.glyph_row(chinese_row),.row_bits(chinese_bits));
 reg s_chinese_window;
 reg [3:0] s_chinese_column;
 reg s_hs,s_vs,s_de,s_panel,s_text;
 reg [COORD_BITS-1:0] s_x,s_y;
 reg [23:0] s_rgb;
 reg [7:0] s_char;
 reg [2:0] s_row,s_bit;
 reg [23:0] base;
 reg [2:0] bar;
 reg [7:0] grey,character;
 reg panel,text;
 reg [COORD_BITS-1:0] tx,ty;
 function [7:0] font_row;
  input [7:0] c;input [2:0] row;
  reg [63:0] glyph;
  begin
   case(c)
    "0":glyph=64'h3c666e7666663c00; "1":glyph=64'h1838181818187e00;
    "2":glyph=64'h3c66060c30607e00; "3":glyph=64'h3c66061c06663c00;
    "4":glyph=64'h0c1c3c6c7e0c0c00; ":":glyph=64'h0018180018180000;
    "A":glyph=64'h183c66667e666600; "B":glyph=64'h7c66667c66667c00;
    "C":glyph=64'h3c66606060663c00; "D":glyph=64'h786c6666666c7800;
    "E":glyph=64'h7e60607c60607e00; "G":glyph=64'h3c66606e66663e00;
    "H":glyph=64'h6666667e66666600; "I":glyph=64'h7e18181818187e00;
    "J":glyph=64'h1e0c0c0c0c6c3800; "K":glyph=64'h666c7870786c6600;
    "L":glyph=64'h6060606060607e00; "P":glyph=64'h7c66667c60606000;
    "R":glyph=64'h7c66667c786c6600; "S":glyph=64'h3c66603c06663c00;
    "T":glyph=64'h7e18181818181800; "U":glyph=64'h6666666666663c00;
    "V":glyph=64'h66666666663c1800; "W":glyph=64'h63636b7f77636300;
    "Y":glyph=64'h66663c1818181800;default:glyph=0;
   endcase
   font_row=glyph >> ((7-row)*8);
  end
 endfunction
 function [7:0] label_character;
  input [4:0] index;input [1:0] p;
  reg [127:0] message;
  begin
   if(PATTERNS)case(p)
    0:message="D2 0:LIVE       ";1:message="D2 1:RGB        ";
    2:message="D2 2:GRAY       ";3:message="D2 3:CHECK      ";
   endcase
   else if(p[0])message="D1 B:BYPASS     ";
   else message="D1 A:ADJUST     ";
   label_character=index<16 ? message >> ((15-index)*8):8'd32;
  end
 endfunction
 always @*begin
  bar=x<160?0:x<320?1:x<480?2:x<640?3:x<800?4:x<960?5:x<1120?6:7;
  grey=x<1024?x[9:2]:8'hff;
  base=rgb;
  if(PATTERNS)case(phase)
   1:begin
    if(y>=360)case(bar)
      0:grey=0;1:grey=36;2:grey=73;3:grey=109;
      4:grey=146;5:grey=182;6:grey=219;7:grey=255;
    endcase
    if(y>=360)base={grey,grey,grey};
    else case(bar)
      0:base=24'hffffff;1:base=24'hffff00;2:base=24'h00ffff;3:base=24'h00ff00;
      4:base=24'hff00ff;5:base=24'hff0000;6:base=24'h0000ff;7:base=0;
    endcase
   end
   2:base={grey,grey,grey};
   3:begin
    if(y<240)base=(x[0]^y[0])?24'hff0000:24'h00ff00;
    else if(y<480)base=(x[1]^y[1])?24'h00ffff:24'hff00ff;
    else base=(x[3]^y[3])?24'hffffff:24'h000000;
   end
  endcase
  panel=x>=16 && x<160 && y>=48 && y<72;
  text=x>=24 && x<152 && y>=52 && y<68;
  tx=x-24;ty=y-52;character=label_character(tx[7:3],phase);
 end
 always @(posedge pixel_clk or posedge reset)begin
  if(reset)begin
   s_hs<=0;s_vs<=0;s_de<=0;s_x<=0;s_y<=0;s_rgb<=0;s_panel<=0;s_text<=0;
   s_char<=0;s_row<=0;s_bit<=0;
   s_chinese_window<=0;s_chinese_column<=0;
   out_hs<=0;out_vs<=0;out_de<=0;out_x<=0;out_y<=0;out_rgb<=0;
  end else begin
   s_hs<=hs;s_vs<=vs;s_de<=de;s_x<=x;s_y<=y;s_rgb<=base;
   s_panel<=panel;s_text<=text;s_char<=character;s_row<=ty[3:1];s_bit<=7-tx[2:0];
   s_chinese_window<=chinese_window;s_chinese_column<=chinese_column;
   out_hs<=s_hs;out_vs<=s_vs;out_de<=s_de;out_x<=s_x;out_y<=s_y;
   if(!s_de)out_rgb<=0;
   else if(s_chinese_window && chinese_bits[15-s_chinese_column])out_rgb<=24'hFFE040;
   else if(s_chinese_window && s_chinese_column!=0 && chinese_bits[16-s_chinese_column])out_rgb<=24'h08304C;
   else if(SHOW_DIAGNOSTIC_LABEL && s_panel)begin
    if(s_text && ((font_row(s_char,s_row)>>s_bit)&1))out_rgb<=24'hffff00;
    else out_rgb<=24'h07152c;
   end else out_rgb<=s_rgb;
  end
 end
endmodule
