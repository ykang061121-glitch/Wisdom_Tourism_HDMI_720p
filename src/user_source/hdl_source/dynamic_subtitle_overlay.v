`include "subtitle_text_rom.v"
`include "subtitle_font_rom.v"

// Observe video only. Both ROM reads are synchronous; ALL pixel metadata
// and background are delayed by the same two cycles. No memory/audio control.
module dynamic_subtitle_overlay #(
    parameter COORD_BITS=10,
    parameter integer FRAMES_PER_PIXEL = 2,
    parameter integer GROUP_FRAMES = 180,
    // Defaults preserve every legacy caller and its two-cycle pipeline.
    parameter integer SCROLL_Y=184, LINE1_Y=250, LINE2_Y=276,
    parameter integer WINDOW_LEFT=16, WINDOW_RIGHT=623, FIXED_LEFT=16,
    parameter integer SHADOW_ENABLE=0,
    parameter integer TOURISM_TEXT=0,
    parameter [23:0] FOREGROUND_RGB = 24'hFFCC40
)(
    input wire pixel_clk,
    input wire reset,
    input wire frame_boundary,
    input wire hs,
    input wire vs,
    input wire de,
    input wire [COORD_BITS-1:0] x,
    input wire [COORD_BITS-1:0] y,
    input wire [23:0] background_rgb,
    input wire [1:0] scene_image,
    output reg out_hs,
    output reg out_vs,
    output reg out_de,
    output reg [COORD_BITS-1:0] out_x,
    output reg [COORD_BITS-1:0] out_y,
    output reg [23:0] subtitle_rgb,
    output reg [COORD_BITS-1:0] scroll_offset,
    output reg [1:0] scroll_message,
    output reg [1:0] subtitle_group
);
    localparam integer STEP_BITS = (FRAMES_PER_PIXEL<=1)?1:$clog2(FRAMES_PER_PIXEL);
    localparam integer GROUP_BITS = (GROUP_FRAMES<=1)?1:$clog2(GROUP_FRAMES);
    reg [STEP_BITS-1:0] step_count;
    reg [GROUP_BITS-1:0] group_count;

    // Window width 608 plus the selected complete string width. At wrap the
    // last text pixel is left of x=16 and the new string starts at x=624.
    function [10:0] last_scroll_offset;
        input [1:0] message;
        begin
            case(message)
                0: last_scroll_offset=WINDOW_RIGHT-WINDOW_LEFT+312;
                1: last_scroll_offset=WINDOW_RIGHT-WINDOW_LEFT+272;
                default: last_scroll_offset=WINDOW_RIGHT-WINDOW_LEFT+200;
            endcase
        end
    endfunction
    function [8:0] message_pixels;
        input [1:0] message;
        begin
            case(message)
                0: message_pixels=9'd312;
                1: message_pixels=9'd272;
                default: message_pixels=9'd200;
            endcase
        end
    endfunction

    // A real one-per-frame blanking event, already aligned to this module's
    // input stage, is the ONLY update source. Active-video events are ignored.
    always @(posedge pixel_clk or posedge reset) begin
        if(reset) begin
            scroll_offset<=0; scroll_message<=0; subtitle_group<=0;
            step_count<=0; group_count<=0;
        end else if(frame_boundary && !de) begin
            if(step_count==FRAMES_PER_PIXEL-1) begin
                step_count<=0;
                if(scroll_offset==last_scroll_offset(scroll_message)) begin
                    scroll_offset<=0;
                    scroll_message<=(scroll_message==2)?0:scroll_message+2'd1;
                end else scroll_offset<=scroll_offset+11'd1;
            end else step_count<=step_count+1'b1;
            if(group_count==GROUP_FRAMES-1) begin
                group_count<=0;
                subtitle_group<=(subtitle_group==2)?0:subtitle_group+2'd1;
            end else group_count<=group_count+1'b1;
        end
    end

    wire signed [12:0] scroll_relative = $signed({2'b00,x}) +
                                        $signed({2'b00,scroll_offset}) - (WINDOW_RIGHT+1);
    wire [10:0] fixed_relative = x-FIXED_LEFT;
    reg [3:0] page;
    reg [5:0] cell_index;
    reg [2:0] glyph_row;
    reg [2:0] glyph_column;
    reg text_enabled;
    wire [9:0] text_address={page,cell_index};
    wire [7:0] character;
    always @* begin
        page=0; cell_index=0; glyph_row=0; glyph_column=0;
        text_enabled=1'b0;
        if(de && x>=WINDOW_LEFT && x<=WINDOW_RIGHT) begin
            // Scroll bar bounding box is y=174..210. Its 8x16 glyphs are
            // vertically centered at y=184..199, with transparent margins.
            if(y>=SCROLL_Y && y<SCROLL_Y+16 && scroll_relative>=0 &&
               scroll_relative<$signed({3'b000,message_pixels(scroll_message)})) begin
                page={2'b00,scroll_message};
                cell_index=scroll_relative[8:3];
                glyph_column=scroll_relative[2:0];
                glyph_row=(y-SCROLL_Y)>>1;
                text_enabled=1'b1;
            end else if(x>=FIXED_LEFT && x<FIXED_LEFT+256 && ((y>=LINE1_Y && y<LINE1_Y+16) ||
                                     (y>=LINE2_Y && y<LINE2_Y+16))) begin
                if(TOURISM_TEXT)page=4'd3+{1'b0,scene_image,1'b0}+((y>=LINE2_Y)?4'd1:4'd0);
                else case(subtitle_group)
                    0: page=(y>=LINE2_Y)?4'd4:4'd3;
                    1: page=(y>=LINE2_Y)?4'd6:4'd5;
                    default: page=(y>=LINE2_Y)?4'd8:4'd7;
                endcase
                cell_index={1'b0,fixed_relative[7:3]};
                glyph_column=fixed_relative[2:0];
                glyph_row=(y>=LINE2_Y)?((y-LINE2_Y)>>1):((y-LINE1_Y)>>1);
                text_enabled=1'b1;
            end
        end
    end
    subtitle_text_rom #(.TOURISM_TEXT(TOURISM_TEXT)) text_rom(.pixel_clk(pixel_clk),.address(text_address),.character(character));

    function [5:0] code_for_ascii;
        input [7:0] ascii;
        begin
            if(ascii>=8'h41 && ascii<=8'h5A) code_for_ascii=ascii-8'h40;
            else if(ascii>=8'h30 && ascii<=8'h39) code_for_ascii=6'd27+(ascii-8'h30);
            else if(ascii==8'h78) code_for_ascii=6'd37;
            else code_for_ascii=0;
        end
    endfunction
    reg hs_s1,vs_s1,de_s1,text_s1,text_s2;
    reg [COORD_BITS-1:0] x_s1,y_s1;
    reg [23:0] background_s1,background_s2;
    reg [2:0] row_s1,column_s1,column_s2;
    wire [7:0] font_bits;
    subtitle_font_rom font_rom(.pixel_clk(pixel_clk),.glyph_code(code_for_ascii(character)),
                              .glyph_row(row_s1),.font_bits(font_bits));
    always @(posedge pixel_clk or posedge reset) begin
        if(reset) begin
            hs_s1<=0;vs_s1<=0;de_s1<=0;x_s1<=0;y_s1<=0;background_s1<=0;
            row_s1<=0;column_s1<=0;text_s1<=0;
            out_hs<=0;out_vs<=0;out_de<=0;out_x<=0;out_y<=0;
            background_s2<=0;column_s2<=0;text_s2<=0;
        end else begin
            hs_s1<=hs;vs_s1<=vs;de_s1<=de;x_s1<=x;y_s1<=y;background_s1<=background_rgb;
            row_s1<=glyph_row;column_s1<=glyph_column;text_s1<=text_enabled;
            out_hs<=hs_s1;out_vs<=vs_s1;out_de<=de_s1;out_x<=x_s1;out_y<=y_s1;
            background_s2<=background_s1;column_s2<=column_s1;text_s2<=text_s1;
        end
    end
    // One pixel right-hand black shadow, using the previous foreground bit.
    // It never delays RGB/metadata, never shades a rectangle, and is clipped
    // to the existing glyph window. Foreground has priority over shadow.
    wire foreground_dot=text_s2 && font_bits[3'd7-column_s2];
    reg previous_dot,previous_de;
    reg [COORD_BITS-1:0] previous_x,previous_y;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin previous_dot<=0;previous_de<=0;previous_x<=0;previous_y<=0;end
        else begin
            previous_dot<=foreground_dot;previous_de<=out_de;
            previous_x<=out_x;previous_y<=out_y;
        end
    end
    always @* begin
        if(reset || !out_de) subtitle_rgb=24'd0;
        else if(foreground_dot) subtitle_rgb=FOREGROUND_RGB;
        else if(SHADOW_ENABLE && previous_dot && previous_de && previous_y==out_y &&
                previous_x+1'b1==out_x && out_x>=WINDOW_LEFT && out_x<=WINDOW_RIGHT) subtitle_rgb=24'd0;
        else subtitle_rgb=background_s2;
    end
endmodule
