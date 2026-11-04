module osd_overlay #(
    parameter [23:0] FOREGROUND_RGB = 24'hFFFFFF,
    parameter [9:0]  OSD_X          = 10'd16,
    parameter [9:0]  OSD_Y          = 10'd16,
    parameter integer SHOW_SETTINGS = 0
)(
    input  wire        pixel_clk,
    input  wire        reset,
    input  wire        de,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [23:0] background_rgb,
    input  wire [1:0]  image_index,
    input  wire        auto_play_enable,
    input  wire        display_valid,
    input  wire signed [7:0] brightness,
    input  wire [1:0]  contrast,
    input  wire [2:0]  fade_level,
    input  wire [1:0]  interval_code,
    input  wire [1:0]  preset_mode,
    input  wire        subtitles_visible,
    input  wire        wave_visible,
    output reg  [23:0] osd_rgb
);

reg [7:0] character;
reg [7:0] font_bits;
reg [9:0] x_relative;
reg [3:0] font_row_16;
reg [6:0] character_index;
reg [2:0] font_column;
reg       text_window;
reg [7:0] brightness_sign;
reg [7:0] brightness_tens;
reg [7:0] brightness_ones;
reg [7:0] contrast_hundreds;
reg [7:0] contrast_tens;
reg [7:0] contrast_ones;
reg [7:0] fade_hundreds;
reg [7:0] fade_tens;
reg [7:0] fade_ones;

// Only the characters used by this first OSD are implemented.  Each 8x8
// glyph row is displayed twice vertically to form an 8x16 cell.
function [7:0] font_row_8;
    input [7:0] ascii;
    input [2:0] row;
    begin
        font_row_8 = 8'h00;
        case (ascii)
            8'h30: case (row) // 0
                0: font_row_8=8'h3C; 1: font_row_8=8'h66; 2: font_row_8=8'h6E; 3: font_row_8=8'h76;
                4: font_row_8=8'h66; 5: font_row_8=8'h66; 6: font_row_8=8'h3C; default: font_row_8=8'h00; endcase
            8'h31: case (row) // 1
                0: font_row_8=8'h18; 1: font_row_8=8'h38; 2: font_row_8=8'h18; 3: font_row_8=8'h18;
                4: font_row_8=8'h18; 5: font_row_8=8'h18; 6: font_row_8=8'h7E; default: font_row_8=8'h00; endcase
            8'h32: case (row) // 2
                0: font_row_8=8'h3C; 1: font_row_8=8'h66; 2: font_row_8=8'h06; 3: font_row_8=8'h0C;
                4: font_row_8=8'h30; 5: font_row_8=8'h60; 6: font_row_8=8'h7E; default: font_row_8=8'h00; endcase
            8'h33: case (row) // 3
                0: font_row_8=8'h3C; 1: font_row_8=8'h66; 2: font_row_8=8'h06; 3: font_row_8=8'h1C;
                4: font_row_8=8'h06; 5: font_row_8=8'h66; 6: font_row_8=8'h3C; default: font_row_8=8'h00; endcase
            8'h34: case (row) // 4
                0: font_row_8=8'h0C; 1: font_row_8=8'h1C; 2: font_row_8=8'h3C; 3: font_row_8=8'h6C;
                4: font_row_8=8'h7E; 5: font_row_8=8'h0C; 6: font_row_8=8'h0C; default: font_row_8=8'h00; endcase
            8'h35: case (row) // 5
                0: font_row_8=8'h7E; 1: font_row_8=8'h60; 2: font_row_8=8'h60; 3: font_row_8=8'h7C;
                4: font_row_8=8'h06; 5: font_row_8=8'h66; 6: font_row_8=8'h3C; default: font_row_8=8'h00; endcase
            8'h36: case (row) // 6
                0: font_row_8=8'h1C; 1: font_row_8=8'h30; 2: font_row_8=8'h60; 3: font_row_8=8'h7C;
                4: font_row_8=8'h66; 5: font_row_8=8'h66; 6: font_row_8=8'h3C; default: font_row_8=8'h00; endcase
            8'h37: case (row) // 7
                0: font_row_8=8'h7E; 1: font_row_8=8'h06; 2: font_row_8=8'h0C; 3: font_row_8=8'h18;
                4: font_row_8=8'h30; 5: font_row_8=8'h30; 6: font_row_8=8'h30; default: font_row_8=8'h00; endcase
            8'h3A: case (row) // :
                1: font_row_8=8'h18; 2: font_row_8=8'h18; 4: font_row_8=8'h18; 5: font_row_8=8'h18;
                default: font_row_8=8'h00; endcase
            8'h2B: case (row) // +
                2: font_row_8=8'h18; 3: font_row_8=8'h7E; 4: font_row_8=8'h18;
                default: font_row_8=8'h00; endcase
            8'h2D: case (row) // -
                3: font_row_8=8'h7E; default: font_row_8=8'h00; endcase
            8'h41: case (row) // A
                0: font_row_8=8'h18; 1: font_row_8=8'h3C; 2: font_row_8=8'h66; 3: font_row_8=8'h66;
                4: font_row_8=8'h7E; 5: font_row_8=8'h66; 6: font_row_8=8'h66; default: font_row_8=8'h00; endcase
            8'h42: case (row) // B
                0: font_row_8=8'h7C; 1: font_row_8=8'h66; 2: font_row_8=8'h66; 3: font_row_8=8'h7C;
                4: font_row_8=8'h66; 5: font_row_8=8'h66; 6: font_row_8=8'h7C; default: font_row_8=8'h00; endcase
            8'h43: case (row) // C
                0: font_row_8=8'h3C; 1: font_row_8=8'h66; 2: font_row_8=8'h60; 3: font_row_8=8'h60;
                4: font_row_8=8'h60; 5: font_row_8=8'h66; 6: font_row_8=8'h3C; default: font_row_8=8'h00; endcase
            8'h44: case (row) // D
                0: font_row_8=8'h78; 1: font_row_8=8'h6C; 2: font_row_8=8'h66; 3: font_row_8=8'h66;
                4: font_row_8=8'h66; 5: font_row_8=8'h6C; 6: font_row_8=8'h78; default: font_row_8=8'h00; endcase
            8'h45: case (row) // E
                0: font_row_8=8'h7E; 1: font_row_8=8'h60; 2: font_row_8=8'h60; 3: font_row_8=8'h7C;
                4: font_row_8=8'h60; 5: font_row_8=8'h60; 6: font_row_8=8'h7E; default: font_row_8=8'h00; endcase
            8'h46: case (row) // F
                0: font_row_8=8'h7E; 1: font_row_8=8'h60; 2: font_row_8=8'h60; 3: font_row_8=8'h7C;
                4: font_row_8=8'h60; 5: font_row_8=8'h60; 6: font_row_8=8'h60; default: font_row_8=8'h00; endcase
            8'h47: case (row) // G
                0: font_row_8=8'h3C; 1: font_row_8=8'h66; 2: font_row_8=8'h60; 3: font_row_8=8'h6E;
                4: font_row_8=8'h66; 5: font_row_8=8'h66; 6: font_row_8=8'h3C; default: font_row_8=8'h00; endcase
            8'h48: case (row) // H
                0,1,2,4,5,6:font_row_8=8'h66; 3:font_row_8=8'h7E; default:font_row_8=0; endcase
            8'h49: case (row) // I
                0: font_row_8=8'h7E; 1: font_row_8=8'h18; 2: font_row_8=8'h18; 3: font_row_8=8'h18;
                4: font_row_8=8'h18; 5: font_row_8=8'h18; 6: font_row_8=8'h7E; default: font_row_8=8'h00; endcase
            8'h4C: case (row) // L
                0: font_row_8=8'h60; 1: font_row_8=8'h60; 2: font_row_8=8'h60; 3: font_row_8=8'h60;
                4: font_row_8=8'h60; 5: font_row_8=8'h60; 6: font_row_8=8'h7E; default: font_row_8=8'h00; endcase
            8'h4D: case (row) // M
                0: font_row_8=8'h63; 1: font_row_8=8'h77; 2: font_row_8=8'h7F; 3: font_row_8=8'h6B;
                4: font_row_8=8'h63; 5: font_row_8=8'h63; 6: font_row_8=8'h63; default: font_row_8=8'h00; endcase
            8'h4E: case (row) // N
                0: font_row_8=8'h66; 1: font_row_8=8'h76; 2: font_row_8=8'h7E; 3: font_row_8=8'h7E;
                4: font_row_8=8'h6E; 5: font_row_8=8'h66; 6: font_row_8=8'h66; default: font_row_8=8'h00; endcase
            8'h4F: case (row) // O
                0: font_row_8=8'h3C; 1: font_row_8=8'h66; 2: font_row_8=8'h66; 3: font_row_8=8'h66;
                4: font_row_8=8'h66; 5: font_row_8=8'h66; 6: font_row_8=8'h3C; default: font_row_8=8'h00; endcase
            8'h50: case (row) // P
                0: font_row_8=8'h7C; 1: font_row_8=8'h66; 2: font_row_8=8'h66; 3: font_row_8=8'h7C;
                4: font_row_8=8'h60; 5: font_row_8=8'h60; 6: font_row_8=8'h60; default: font_row_8=8'h00; endcase
            8'h52: case (row) // R
                0: font_row_8=8'h7C; 1: font_row_8=8'h66; 2: font_row_8=8'h66; 3: font_row_8=8'h7C;
                4: font_row_8=8'h6C; 5: font_row_8=8'h66; 6: font_row_8=8'h66; default: font_row_8=8'h00; endcase
            8'h53: case (row) // S
                0,6:font_row_8=8'h3C; 1,5:font_row_8=8'h66; 2:font_row_8=8'h60;
                3:font_row_8=8'h3C; 4:font_row_8=8'h06; default:font_row_8=0; endcase
            8'h54: case (row) // T
                0: font_row_8=8'h7E; 1: font_row_8=8'h18; 2: font_row_8=8'h18; 3: font_row_8=8'h18;
                4: font_row_8=8'h18; 5: font_row_8=8'h18; 6: font_row_8=8'h18; default: font_row_8=8'h00; endcase
            8'h55: case (row) // U
                0: font_row_8=8'h66; 1: font_row_8=8'h66; 2: font_row_8=8'h66; 3: font_row_8=8'h66;
                4: font_row_8=8'h66; 5: font_row_8=8'h66; 6: font_row_8=8'h3C; default: font_row_8=8'h00; endcase
            8'h56: case (row) // V
                0,1,2,3,4:font_row_8=8'h66; 5:font_row_8=8'h3C; 6:font_row_8=8'h18; default:font_row_8=0; endcase
            8'h57: case (row) // W
                0,1,2,6:font_row_8=8'h63; 3:font_row_8=8'h6B; 4:font_row_8=8'h7F;
                5:font_row_8=8'h77; default:font_row_8=0; endcase
            default: font_row_8 = 8'h00;
        endcase
    end
endfunction

function [7:0] mode_character;
    input [1:0] mode;
    input [6:0] index;
    reg [47:0] text_value;
    begin
        case(mode)
            0:text_value="NORMAL";
            1:text_value="SOFT  ";
            2:text_value="BRIGHT";
            default:text_value="VIVID ";
        endcase
        case(index)
            5:mode_character=text_value[47:40];6:mode_character=text_value[39:32];
            7:mode_character=text_value[31:24];8:mode_character=text_value[23:16];
            9:mode_character=text_value[15:8];10:mode_character=text_value[7:0];
            default:mode_character=8'h20;
        endcase
    end
endfunction

always @* begin
    character       = 8'h20;
    font_bits       = 8'h00;
    x_relative      = 10'd0;
    font_row_16     = 4'd0;
    character_index = 7'd0;
    font_column     = 3'd0;
    text_window     = 1'b0;
    brightness_sign = 8'h2B;
    brightness_tens = 8'h30;
    brightness_ones = 8'h30;
    contrast_hundreds = 8'h31;
    contrast_tens     = 8'h30;
    contrast_ones     = 8'h30;
    fade_hundreds     = 8'h31;
    fade_tens         = 8'h30;
    fade_ones         = 8'h30;

    case (brightness)
        -8'sd32: begin brightness_sign=8'h2D; brightness_tens=8'h33; brightness_ones=8'h32; end
        -8'sd16: begin brightness_sign=8'h2D; brightness_tens=8'h31; brightness_ones=8'h36; end
         8'sd16: begin brightness_sign=8'h2B; brightness_tens=8'h31; brightness_ones=8'h36; end
        default: begin brightness_sign=8'h2B; brightness_tens=8'h30; brightness_ones=8'h30; end
    endcase

    case (contrast)
        2'b00: begin contrast_hundreds=8'h30; contrast_tens=8'h37; contrast_ones=8'h35; end
        2'b01: begin contrast_hundreds=8'h31; contrast_tens=8'h30; contrast_ones=8'h30; end
        2'b10: begin contrast_hundreds=8'h31; contrast_tens=8'h32; contrast_ones=8'h35; end
        default: begin contrast_hundreds=8'h31; contrast_tens=8'h35; contrast_ones=8'h30; end
    endcase

    case (fade_level)
        3'd0: begin fade_hundreds=8'h30; fade_tens=8'h30; fade_ones=8'h30; end
        3'd1: begin fade_hundreds=8'h30; fade_tens=8'h32; fade_ones=8'h35; end
        3'd2: begin fade_hundreds=8'h30; fade_tens=8'h35; fade_ones=8'h30; end
        3'd3: begin fade_hundreds=8'h30; fade_tens=8'h37; fade_ones=8'h35; end
        default: begin fade_hundreds=8'h31; fade_tens=8'h30; fade_ones=8'h30; end
    endcase

    if ((x >= OSD_X) && (x < OSD_X + 10'd96)) begin
        x_relative      = x - OSD_X;
        character_index = x_relative[9:3];
        font_column     = x_relative[2:0];

        if (!display_valid) begin
            if ((y >= OSD_Y) && (y < OSD_Y + 10'd16)) begin
                text_window = 1'b1;
                font_row_16 = y - OSD_Y;
                case (character_index)
                    0: character=8'h4C; 1: character=8'h4F; 2: character=8'h41;
                    3: character=8'h44; 4: character=8'h49; 5: character=8'h4E;
                    6: character=8'h47; default: character=8'h20;
                endcase
            end
        end else if ((y >= OSD_Y) && (y < OSD_Y + 10'd16)) begin
            text_window = 1'b1;
            font_row_16 = y - OSD_Y;
            case (character_index) // ANLOGIC FPGA
                0: character=8'h41; 1: character=8'h4E; 2: character=8'h4C;
                3: character=8'h4F; 4: character=8'h47; 5: character=8'h49;
                6: character=8'h43; 7: character=8'h20; 8: character=8'h46;
                9: character=8'h50; 10: character=8'h47; 11: character=8'h41;
                default: character=8'h20;
            endcase
        end else if ((y >= OSD_Y + 10'd20) && (y < OSD_Y + 10'd36)) begin
            text_window = 1'b1;
            font_row_16 = y - (OSD_Y + 10'd20);
            case (character_index) // IMG:0[1-4]
                0: character=8'h49; 1: character=8'h4D; 2: character=8'h47;
                3: character=8'h3A; 4: character=8'h30;
                5: character=8'h31 + {6'd0,image_index};
                default: character=8'h20;
            endcase
        end else if ((y >= OSD_Y + 10'd40) && (y < OSD_Y + 10'd56)) begin
            text_window = 1'b1;
            font_row_16 = y - (OSD_Y + 10'd40);
            case (character_index) // AUTO:ON / AUTO:OFF
                0: character=8'h41; 1: character=8'h55; 2: character=8'h54;
                3: character=8'h4F; 4: character=8'h3A; 5: character=8'h4F;
                6: character=auto_play_enable ? 8'h4E : 8'h46;
                7: character=auto_play_enable ? 8'h20 : 8'h46;
                default: character=8'h20;
            endcase
        end else if ((y >= OSD_Y + 10'd60) && (y < OSD_Y + 10'd76)) begin
            text_window = 1'b1;
            font_row_16 = y - (OSD_Y + 10'd60);
            case (character_index) // BRI:[+/-][00/16/32]
                0: character=8'h42; 1: character=8'h52; 2: character=8'h49;
                3: character=8'h3A; 4: character=brightness_sign;
                5: character=brightness_tens; 6: character=brightness_ones;
                default: character=8'h20;
            endcase
        end else if ((y >= OSD_Y + 10'd80) && (y < OSD_Y + 10'd96)) begin
            text_window = 1'b1;
            font_row_16 = y - (OSD_Y + 10'd80);
            case (character_index) // CON:075/100/125/150
                0: character=8'h43; 1: character=8'h4F; 2: character=8'h4E;
                3: character=8'h3A; 4: character=contrast_hundreds;
                5: character=contrast_tens; 6: character=contrast_ones;
                default: character=8'h20;
            endcase
        end else if ((y >= OSD_Y + 10'd100) && (y < OSD_Y + 10'd116)) begin
            text_window = 1'b1;
            font_row_16 = y - (OSD_Y + 10'd100);
            case (character_index) // FADE:000/025/050/075/100
                0: character=8'h46; 1: character=8'h41; 2: character=8'h44;
                3: character=8'h45; 4: character=8'h3A; 5: character=fade_hundreds;
                6: character=fade_tens; 7: character=fade_ones;
                default: character=8'h20;
            endcase
        end
    end

    // Right-hand status block: x=360..447, y=16..91. It cannot overlap
    // original status (left), subtitles (y>=174), or waveform (y>=330).
    // Settings remain visible while the first BMP is loading as well.
    if(SHOW_SETTINGS && x>=10'd360 && x<10'd448) begin
        x_relative=x-10'd360;
        character_index=x_relative[9:3];font_column=x_relative[2:0];
        character=8'h20;text_window=0;
        if(y>=16 && y<32) begin
            text_window=1;font_row_16=y-16;
            case(character_index)
                0:character="I";1:character="N";2:character="T";3:character=":";
                4:character=(interval_code==3)?"1":"0";
                5:case(interval_code) 0:character="1";1:character="3";2:character="5";default:character="0";endcase
                6:character="S";default:character=" ";
            endcase
        end else if(y>=36 && y<52) begin
            text_window=1;font_row_16=y-36;
            case(character_index)
                0:character="M";1:character="O";2:character="D";3:character="E";4:character=":";
                default:character=mode_character(preset_mode,character_index);
            endcase
        end else if(y>=56 && y<72) begin
            text_window=1;font_row_16=y-56;
            case(character_index)
                0:character="S";1:character="U";2:character="B";3:character=":";4:character="O";
                5:character=subtitles_visible?"N":"F";
                6:character=subtitles_visible?" ":"F";default:character=" ";
            endcase
        end else if(y>=76 && y<92) begin
            text_window=1;font_row_16=y-76;
            case(character_index)
                0:character="W";1:character="A";2:character="V";3:character="E";4:character=":";5:character="O";
                6:character=wave_visible?"N":"F";
                7:character=wave_visible?" ":"F";default:character=" ";
            endcase
        end
    end
    font_bits = font_row_8(character, font_row_16[3:1]);

    if (reset || !de)
        osd_rgb = 24'd0;
    else if (text_window && font_bits[3'd7 - font_column])
        osd_rgb = FOREGROUND_RGB;
    else
        osd_rgb = background_rgb;
end

// pixel_clk is intentionally present in the interface so this combinational
// overlay is explicitly tied to the pixel-domain contract; it adds no latency.
wire unused_pixel_clk = pixel_clk;

endmodule
