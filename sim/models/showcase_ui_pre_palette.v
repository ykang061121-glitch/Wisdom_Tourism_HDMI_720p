// Two-cycle status/text compositor. Reuses the existing synchronous ASCII
// font ROM; only four tiny punctuation glyphs are local. No alpha multiplier.
module showcase_ui_pre_palette(
    input wire pixel_clk,reset,hs,vs,de,
    input wire [9:0] x,y,
    input wire [23:0] background_rgb,
    input wire display_valid,auto_play_enable,subtitles_visible,visual_visible,
    input wire [1:0] image_index,interval_code,preset_mode,
    input wire signed [7:0] brightness,
    input wire [1:0] contrast,
    input wire [2:0] fade_level,
    input wire [9:0] music_status,
    input wire [7:0] error_status,
    input wire hint_visible,
    input wire [2:0] hint_kind,
    input wire notice_visible,
    input wire [1:0] notice_index,
    output reg out_hs,out_vs,out_de,
    output reg [9:0] out_x,out_y,
    output reg [23:0] output_rgb
);
    reg [4:0] area,cell_index;
    reg [9:0] relative_x,relative_y;
    reg text_enabled;
    reg [23:0] base_rgb,text_rgb;
    reg [191:0] text_value;
    reg [7:0] character;
    reg error_visible;
    wire [3:0] current_pitch;
    wire [15:0] current_name;
    image_melody_rom current_note(.image_index(music_status[8:7]),.note_index(music_status[6:4]),
        .phase_increment(),.note_samples(),.pitch_code(current_pitch));
    function [15:0] note_name;
        input [3:0] pitch;
        begin case(pitch)
            1:note_name="C3";2:note_name="D3";3:note_name="E3";4:note_name="G3";
            5:note_name="C4";6:note_name="D4";7:note_name="E4";8:note_name="G4";
            9:note_name="A4";10:note_name="B4";11:note_name="C5";12:note_name="D5";
            default:note_name="E5";
        endcase end
    endfunction
    assign current_name=note_name(current_pitch);
    function [7:0] text_at;
        input [191:0] text;
        input [4:0] index;
        begin text_at=(index<24)?text[191-index*8 -:8]:8'h20;end
    endfunction
    function [5:0] glyph_code;
        input [7:0] ascii;
        begin
            if(ascii>=65 && ascii<=90)glyph_code=ascii-64;
            else if(ascii>=48 && ascii<=57)glyph_code=27+ascii-48;
            else glyph_code=0;
        end
    endfunction
    function [7:0] punctuation;
        input [7:0] ascii;
        input [2:0] row;
        begin
            punctuation=0;
            case(ascii)
                ":":if(row==1 || row==2 || row==4 || row==5)punctuation=8'h18;
                "-":if(row==3)punctuation=8'h7E;
                "+":case(row)2,4:punctuation=8'h18;3:punctuation=8'h7E;endcase
                "/":case(row)
                    0:punctuation=8'h06;1:punctuation=8'h0C;2:punctuation=8'h18;
                    3:punctuation=8'h30;4,5,6:punctuation=8'h60;
                endcase
            endcase
        end
    endfunction
    // Top and temporary text are transparent. Only glyphs and a one-pixel
    // horizontal black outline overwrite the input. Music text is unchanged.
    always @* begin
        area=31;cell_index=0;relative_x=0;relative_y=0;text_enabled=0;
        base_rgb=background_rgb;text_rgb=24'hEAF6FF;character=" ";
        text_value="                        ";
        // Exact codes only: omitted legacy-test input (Z) is not an error.
        // All codes below have a concrete hardware detection source.
        case(error_status)
            8'hE0,8'hE1,8'hE2,8'hE3,8'hE4,8'hEF:error_visible=1;
            default:error_visible=0;
        endcase
        if(x>=8 && x<=631 && y>=8 && y<=39)begin
            if(y>=16 && y<32)begin
                if(x>=16 && x<80)begin area=0;relative_x=x-16;relative_y=y-16;text_rgb=24'h50D9FF;end
                else if(x>=112 && x<160)begin area=1;relative_x=x-112;relative_y=y-16;end
                else if(x>=208 && x<256)begin area=2;relative_x=x-208;relative_y=y-16;text_rgb=24'hB8F4FF;end
                else if(x>=304 && x<328)begin area=3;relative_x=x-304;relative_y=y-16;text_rgb=24'hFFE45C;end
                else if(x>=400 && x<448)begin area=4;relative_x=x-400;relative_y=y-16;text_rgb=24'h68FFB2;end
            end
        end
        // Explicit setting feedback only. FADE is not a presentation label.
        if(hint_visible && x>=8 && x<=319 && y>=44 && y<=67)begin
            if(x>=16 && x<208 && y>=48 && y<64)begin
                area=13;relative_x=x-16;relative_y=y-48;
            end
        end
        // Error has priority over the temporary setting hint, not the music
        // panel or scene notice. Transparent glyphs use the same black outline.
        if(error_visible && x>=16 && x<208 && y>=48 && y<64)begin
            area=15;relative_x=x-16;relative_y=y-48;text_rgb=24'hFFAD48;
        end
        if(visual_visible && y>=379 && y<395)begin
            if(x>=408 && x<432)begin area=10;relative_x=x-408;relative_y=y-379;text_rgb=24'h50D9FF;end
            else if(x>=448 && x<504)begin area=11;relative_x=x-448;relative_y=y-379;end
            else if(x>=584 && x<608)begin
                area=12;relative_x=x-584;relative_y=y-379;
                text_rgb=music_status[0]?24'h00FF9A:24'h8CA6B8;
            end
        end
        if(notice_visible && x>=400 && x<=631 && y>=44 && y<=67)begin
            if(x>=408 && x<568 && y>=48 && y<64)begin
                area=14;relative_x=x-408;relative_y=y-48;
            end
        end
        cell_index=relative_x[7:3];text_enabled=(area!=31);
        case(area)
            0:text_value=display_valid?"ANLOGIC                 ":"LOADING                 ";
            1:text_value=display_valid?"IMG:01                  ":"IMG:--                  ";
            2:text_value=auto_play_enable?"AUTO                    ":"MANUAL                  ";
            3:text_value="05S                     ";
            4:case(preset_mode)
                0:text_value="NORMAL                  ";1:text_value="SOFT                    ";
                2:text_value="BRIGHT                  ";3:text_value="VIVID                   ";
            endcase
            10:text_value=music_status[9]?"M01                     ":"M--                     ";
            11:text_value=music_status[9]?"NOTE:C4                 ":"NOTE:--                 ";
            12:text_value=music_status[9]?"1/8                     ":"-/8                     ";
            13:case(hint_kind)
                1:text_value="INTERVAL:05S            ";
                2:text_value=auto_play_enable?"MODE:AUTO               ":"MODE:MANUAL             ";
                3:case(preset_mode)
                    0:text_value="NORMAL BRI:+00 CON:100  ";
                    1:text_value="SOFT BRI:-32 CON:075    ";
                    2:text_value="BRIGHT BRI:+16 CON:100  ";
                    3:text_value="VIVID BRI:+00 CON:125   ";
                endcase
                4:text_value=subtitles_visible?"SUB:ON                  ":"SUB:OFF                 ";
                5:text_value=visual_visible?"VIS:ON                  ":"VIS:OFF                 ";
                default:text_value="                        ";
            endcase
            14:text_value="SCENE 01 / MELODY 01    ";
            15:case(error_status)
                8'hE0:text_value="BMP FORMAT ERROR        ";
                8'hE1:text_value="BMP SIZE ERROR          ";
                8'hE2:text_value="BMP LENGTH ERROR        ";
                8'hE3:text_value="SD READ ERROR           ";
                8'hE4:text_value="NO BMP FOUND            ";
                8'hEF:text_value="LOAD CANCELLED          ";
                default:text_value="                        ";
            endcase
        endcase
        character=text_at(text_value,cell_index);
        case(area)
            1:if(display_valid && cell_index==5)character="1"+{6'd0,image_index};
            3:case(cell_index)
                0:character=(interval_code==3)?"1":"0";
                1:case(interval_code)0:character="1";1:character="3";2:character="5";3:character="0";endcase
            endcase
            10:if(music_status[9] && cell_index==2)character="1"+{6'd0,music_status[8:7]};
            11:if(music_status[9])case(cell_index)5:character=current_name[15:8];6:character=current_name[7:0];endcase
            12:if(music_status[9] && cell_index==0)character="1"+{5'd0,music_status[6:4]};
            13:if(hint_kind==1)case(cell_index)
                9:character=(interval_code==3)?"1":"0";
                10:case(interval_code)0:character="1";1:character="3";2:character="5";3:character="0";endcase
            endcase
            14:if(cell_index==7 || cell_index==19)character="1"+{6'd0,notice_index};
        endcase
    end
    reg hs_s1,vs_s1,de_s1,text_s1,text_s2,punct_s2,shadow_s1,shadow_s2;
    reg [9:0] x_s1,y_s1;
    reg [23:0] background_s1,background_s2,color_s1,color_s2;
    reg [7:0] character_s1,punctuation_s2;
    reg [2:0] row_s1,column_s1,column_s2;
    wire [7:0] font_bits;
    subtitle_font_rom font(.pixel_clk(pixel_clk),.glyph_code(glyph_code(character_s1)),
        .glyph_row(row_s1),.font_bits(font_bits));
    wire [7:0] selected_bits=punct_s2?punctuation_s2:font_bits;
    wire foreground_dot=text_s2 && selected_bits[7-column_s2];
    // Left outline uses the following dot in the SAME ROM row. Every
    // supported glyph has an empty first column; no second ROM is needed.
    wire left_outline=shadow_s2 && column_s2<7 && selected_bits[6-column_s2];
    reg previous_outline_dot,previous_de;
    reg [9:0] previous_x,previous_y;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin previous_outline_dot<=0;previous_de<=0;previous_x<=0;previous_y<=0;end
        else begin
            previous_outline_dot<=foreground_dot && shadow_s2;
            previous_de<=out_de;previous_x<=out_x;previous_y<=out_y;
        end
    end
    wire right_outline=previous_outline_dot && previous_de &&
        previous_y==out_y && previous_x+10'd1==out_x;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin
            hs_s1<=0;vs_s1<=0;de_s1<=0;x_s1<=0;y_s1<=0;
            out_hs<=0;out_vs<=0;out_de<=0;out_x<=0;out_y<=0;
            background_s1<=0;background_s2<=0;color_s1<=0;color_s2<=0;
            character_s1<=0;row_s1<=0;column_s1<=0;column_s2<=0;
            text_s1<=0;text_s2<=0;punct_s2<=0;punctuation_s2<=0;shadow_s1<=0;shadow_s2<=0;
        end else begin
            hs_s1<=hs;vs_s1<=vs;de_s1<=de;x_s1<=x;y_s1<=y;
            background_s1<=base_rgb;color_s1<=text_rgb;character_s1<=character;
            row_s1<=relative_y[3:1];column_s1<=relative_x[2:0];text_s1<=text_enabled;
            shadow_s1<=text_enabled && (area<=4 || area==13 || area==14 || area==15);shadow_s2<=shadow_s1;
            out_hs<=hs_s1;out_vs<=vs_s1;out_de<=de_s1;out_x<=x_s1;out_y<=y_s1;
            background_s2<=background_s1;color_s2<=color_s1;
            column_s2<=column_s1;text_s2<=text_s1;
            punct_s2<=(character_s1==":" || character_s1=="-" || character_s1=="+" || character_s1=="/");
            punctuation_s2<=punctuation(character_s1,row_s1);
        end
    end
    always @* begin
        if(reset || !out_de)output_rgb=0;
        else if(foreground_dot)output_rgb=color_s2;
        else if(left_outline || right_outline)output_rgb=0;
        else output_rgb=background_s2;
    end
endmodule


