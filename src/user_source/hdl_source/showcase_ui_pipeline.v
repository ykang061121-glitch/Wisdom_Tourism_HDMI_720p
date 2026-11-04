// Five-cycle experimental UI. Frozen original is the equivalence oracle.
module showcase_ui_pipeline #(parameter COORD_BITS=10, parameter VIDEO_720P=0,
    parameter COMPLIANCE_UI=0, parameter SCALE_MODE=0,parameter PERCENT_CONTRAST=0)(
    input wire pixel_clk,reset,hs,vs,de,
    input wire [COORD_BITS-1:0] x,y,
    input wire [23:0] background_rgb,
    input wire display_valid,auto_play_enable,subtitles_visible,visual_visible,
    input wire [1:0] image_index,interval_code,preset_mode,
    input wire signed [7:0] brightness,
    input wire [7:0] contrast,
    input wire [11:0] brightness_digits,contrast_digits,
    input wire param_hint_visible,
    input wire [2:0] fade_level,
    input wire scaling_meta_valid,adjust_mode,adjust_target_contrast,adjust_fast,
    input wire waiting_for_scene,
    input wire [63:0] scaling_meta_bcd,
    input wire [9:0] music_status,
    input wire [7:0] error_status,
    input wire hint_visible,
    input wire [2:0] hint_kind,
    input wire notice_visible,
    input wire [1:0] notice_index,
    output reg out_hs,out_vs,out_de,
    output reg [COORD_BITS-1:0] out_x,out_y,
    output reg [23:0] output_rgb
);

    localparam TOP_Y=VIDEO_720P?20:16;
    localparam AN_X=VIDEO_720P?24:16, IMG_X=VIDEO_720P?144:112;
    localparam AUTO_X=VIDEO_720P?256:208, TIME_X=VIDEO_720P?368:304;
    localparam PRESET_X=VIDEO_720P?456:400;
    localparam HINT_X=VIDEO_720P?24:16, HINT_Y=VIDEO_720P?52:48;
    localparam NOTICE_X=VIDEO_720P?1040:408;
    localparam MUSIC_X_SHIFT=VIDEO_720P?632:0, MUSIC_Y=VIDEO_720P?619:379;
    reg [4:0] area,area_g;
    reg [COORD_BITS-1:0] relative_x,relative_y;
    reg error_visible;
    reg [23:0] text_rgb;
    reg [5:0] kind;
    reg override_en;
    reg [7:0] override_char;
    reg [4:0] cell_index;
    reg display_valid_g,auto_play_enable_g,subtitles_visible_g,visual_visible_g;
    reg [1:0] image_index_g,interval_code_g,preset_mode_g,notice_index_g;
    reg [9:0] music_status_g;
    reg [7:0] error_status_g;
    reg [2:0] hint_kind_g;
    reg adjust_mode_g,adjust_target_g,adjust_fast_g;
    reg [63:0] meta_g;
    reg signed [7:0] brightness_g;
    reg [1:0] contrast_g;
    reg [11:0] bri_digits_g,con_digits_g;
    wire [7:0] brightness_magnitude=brightness_g[7] ? -brightness_g : brightness_g;
    wire [3:0] current_pitch;
    wire [15:0] current_name=note_name(current_pitch);
    image_melody_rom current_note(.image_index(music_status_g[8:7]),.note_index(music_status_g[6:4]),
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

    function [7:0] scene_slash;
        input [2:0] row;
        begin case(row)
            0:scene_slash=8'h02;1:scene_slash=8'h04;2:scene_slash=8'h08;
            3:scene_slash=8'h10;4:scene_slash=8'h20;5:scene_slash=8'h40;
            6:scene_slash=8'h80;default:scene_slash=0;
        endcase end
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
                "%":case(row)0:punctuation=8'hC6;1:punctuation=8'hCC;
                    2:punctuation=8'h18;3:punctuation=8'h30;
                    4:punctuation=8'h66;5:punctuation=8'hC6;endcase
            endcase
        end
    endfunction

    // P0: region decoding and coordinate subtraction only.
    always @* begin
        area=31;relative_x=0;relative_y=0;text_rgb=24'hEAF6FF;
        // Exact codes only: omitted legacy-test input (Z) is not an error.
        // All codes below have a concrete hardware detection source.
        case(error_status)
            8'hE0,8'hE1,8'hE2,8'hE3,8'hE4,8'hEF:error_visible=1;
            default:error_visible=0;
        endcase
        if(y>=TOP_Y && y<TOP_Y+16)begin
            if(x>=AN_X && x<AN_X+64)begin area=0;relative_x=x-AN_X;relative_y=y-TOP_Y;text_rgb=24'h30D8FF;end
            else if(x>=IMG_X && x<IMG_X+48)begin area=1;relative_x=x-IMG_X;relative_y=y-TOP_Y;text_rgb=24'hFFD040;end
            else if(x>=AUTO_X && x<AUTO_X+48)begin area=2;relative_x=x-AUTO_X;relative_y=y-TOP_Y;text_rgb=24'h00FF9A;end
            else if(x>=TIME_X && x<TIME_X+24)begin area=3;relative_x=x-TIME_X;relative_y=y-TOP_Y;text_rgb=24'hFFD040;end
            else if(x>=PRESET_X && x<PRESET_X+48)begin area=4;relative_x=x-PRESET_X;relative_y=y-TOP_Y;text_rgb=24'h30D8FF;end
        end
        // Explicit setting feedback only. FADE is not a presentation label.
        if(hint_visible)begin
            if(x>=HINT_X && x<HINT_X+192 && y>=HINT_Y && y<HINT_Y+16)begin
                area=13;relative_x=x-HINT_X;relative_y=y-HINT_Y;
                if(COMPLIANCE_UI)text_rgb=24'hFFD040;
            end
        end
        // Error has priority over the temporary setting hint, not the music
        // panel or scene notice. Transparent glyphs use the same black outline.
        if(error_visible && x>=HINT_X && x<HINT_X+192 && y>=HINT_Y && y<HINT_Y+16)begin
            area=15;relative_x=x-HINT_X;relative_y=y-HINT_Y;text_rgb=24'hFFAD48;
        end
        if(visual_visible && y>=MUSIC_Y && y<MUSIC_Y+16)begin
            if(x>=408+MUSIC_X_SHIFT && x<432+MUSIC_X_SHIFT)begin area=10;relative_x=x-(408+MUSIC_X_SHIFT);relative_y=y-MUSIC_Y;text_rgb=24'h50D9FF;end
            else if(x>=448+MUSIC_X_SHIFT && x<504+MUSIC_X_SHIFT)begin area=11;relative_x=x-(448+MUSIC_X_SHIFT);relative_y=y-MUSIC_Y;end
            else if(x>=584+MUSIC_X_SHIFT && x<608+MUSIC_X_SHIFT)begin
                area=12;relative_x=x-(584+MUSIC_X_SHIFT);relative_y=y-MUSIC_Y;
                text_rgb=music_status[0]?24'h00FF9A:24'h8CA6B8;
            end
        end
        if(notice_visible)begin
            if(x>=NOTICE_X && x<NOTICE_X+160 && y>=HINT_Y && y<HINT_Y+16)begin
                area=14;relative_x=x-NOTICE_X;relative_y=y-HINT_Y;
                if(COMPLIANCE_UI)text_rgb=24'h30D8FF;
            end
        end

        if(COMPLIANCE_UI && scaling_meta_valid && y>=84 && y<100 && x>=24 && x<280)begin
            area=16;relative_x=x-24;relative_y=y-84;text_rgb=24'hFFD040;
        end
        if(COMPLIANCE_UI && scaling_meta_valid && y>=104 && y<120 && x>=24 && x<280)begin
            area=17;relative_x=x-24;relative_y=y-104;text_rgb=24'h30D8FF;
        end
        if(COMPLIANCE_UI && (adjust_mode || (PERCENT_CONTRAST && param_hint_visible)) && y>=124 && y<140 && x>=24 && x<280)begin
            area=18;relative_x=x-24;relative_y=y-124;text_rgb=24'hFFD040;
        end
        if(COMPLIANCE_UI && waiting_for_scene && y>=84 && y<100 && x>=1040 && x<1168)begin
            area=19;relative_x=x-1040;relative_y=y-84;text_rgb=24'hFFD040;
        end

    end
    reg [4:0] cell_g;
    reg [2:0] row_g,col_g;
    reg [23:0] color_g;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin
            area_g<=31;cell_g<=0;row_g<=0;col_g<=0;color_g<=0;
            display_valid_g<=0;auto_play_enable_g<=0;subtitles_visible_g<=0;visual_visible_g<=0;
            image_index_g<=0;interval_code_g<=0;preset_mode_g<=0;notice_index_g<=0;
            music_status_g<=0;error_status_g<=0;hint_kind_g<=0;
            adjust_mode_g<=0;adjust_target_g<=0;adjust_fast_g<=0;meta_g<=0;brightness_g<=0;contrast_g<=1;
            bri_digits_g<=0;con_digits_g<=12'h100;
        end else begin
            area_g<=area;cell_g<=relative_x[7:3];row_g<=relative_y[3:1];col_g<=relative_x[2:0];color_g<=text_rgb;
            display_valid_g<=display_valid;auto_play_enable_g<=auto_play_enable;
            subtitles_visible_g<=subtitles_visible;visual_visible_g<=visual_visible;
            image_index_g<=image_index;interval_code_g<=interval_code;preset_mode_g<=preset_mode;notice_index_g<=notice_index;
            music_status_g<=music_status;error_status_g<=error_status;hint_kind_g<=hint_kind;
            adjust_mode_g<=adjust_mode;adjust_target_g<=adjust_target_contrast;adjust_fast_g<=adjust_fast;
            meta_g<=scaling_meta_bcd;brightness_g<=brightness;contrast_g<=contrast;
            bri_digits_g<=brightness_digits;con_digits_g<=contrast_digits;
        end
    end
    // P1: small string ID and dynamic ASCII substitutions. No coordinates.
    always @* begin
        kind=6'd63;cell_index=cell_g;override_en=0;override_char=0;
        case(area_g)
            0:kind=display_valid_g?6'd0:6'd1;
            1:kind=display_valid_g?6'd2:6'd3;
            2:kind=auto_play_enable_g?6'd4:6'd5;
            3:kind=6'd6;
            4:if(COMPLIANCE_UI && adjust_mode_g)kind=36;else case(preset_mode_g)
                0:kind=6'd7;1:kind=6'd8;
                2:kind=6'd9;3:kind=6'd10;
            endcase
            10:kind=music_status_g[9]?6'd11:6'd12;
            11:kind=music_status_g[9]?6'd13:6'd14;
            12:kind=music_status_g[9]?6'd15:6'd16;
            13:if(COMPLIANCE_UI && adjust_mode_g && hint_kind_g==3)kind=28;else case(hint_kind_g)
                1:kind=6'd17;
                2:kind=auto_play_enable_g?6'd18:6'd19;
                3:if(COMPLIANCE_UI && adjust_mode_g)kind=41;else if(PERCENT_CONTRAST)begin
                    case(preset_mode_g)0:kind=7;1:kind=8;2:kind=9;default:kind=10;endcase
                end else case(preset_mode_g)
                    0:kind=6'd20;
                    1:kind=6'd21;
                    2:kind=6'd22;
                    3:kind=6'd23;
                endcase
                4:kind=subtitles_visible_g?6'd24:6'd25;
                5:kind=visual_visible_g?6'd26:6'd27;
                default:kind=6'd28;
            endcase
            14:kind=6'd29;
            15:case(error_status_g)
                8'hE0:kind=6'd30;
                8'hE1:kind=6'd31;
                8'hE2:kind=6'd32;
                8'hE3:kind=6'd33;
                8'hE4:kind=6'd34;
                8'hEF:kind=6'd35;
                default:kind=6'd28;
            endcase
            16:kind=37;
            17:kind=SCALE_MODE==0?38:SCALE_MODE==1?39:40;
            18:kind=41;
            19:kind=42;
        endcase
        case(area_g)
            1:if(display_valid_g && cell_index==5)begin override_en=1; override_char="1"+{6'd0,image_index_g}; end 
            3:case(cell_index)
                0:begin override_en=1; override_char=(interval_code_g==3)?"1":"0"; end 
                1:case(interval_code_g)0:begin override_en=1; override_char="5"; end 1:begin override_en=1; override_char="3"; end 2:begin override_en=1; override_char="5"; end 3:begin override_en=1; override_char="0"; end endcase
            endcase
            10:if(music_status_g[9] && cell_index==2)begin override_en=1; override_char="1"+{6'd0,music_status_g[8:7]}; end 
            11:if(music_status_g[9])case(cell_index)5:begin override_en=1; override_char=current_name[15:8]; end 6:begin override_en=1; override_char=current_name[7:0]; end endcase
            12:if(music_status_g[9] && cell_index==0)begin override_en=1; override_char="1"+{5'd0,music_status_g[6:4]}; end 
            13:if(hint_kind_g==1)case(cell_index)
                9:begin override_en=1; override_char=(interval_code_g==3)?"1":"0"; end 
                10:case(interval_code_g)0:begin override_en=1; override_char="5"; end 1:begin override_en=1; override_char="3"; end 2:begin override_en=1; override_char="5"; end 3:begin override_en=1; override_char="0"; end endcase
            endcase
            14:if(cell_index==7 || cell_index==19)begin override_en=1; override_char="1"+{6'd0,notice_index_g}; end 
            16:begin
                if(cell_index>=4 && cell_index<=7)begin
                    override_en=1;override_char="0"+meta_g[63-(cell_index-4)*4-:4];
                end else if(cell_index>=9 && cell_index<=12)begin
                    override_en=1;override_char="0"+meta_g[47-(cell_index-9)*4-:4];
                end
            end
            17:begin
                if(cell_index>=8 && cell_index<=11)begin override_en=1;override_char="0"+meta_g[31-(cell_index-8)*4-:4];end
                else if(cell_index>=13 && cell_index<=16)begin override_en=1;override_char="0"+meta_g[63-(cell_index-13)*4-:4];end
                else if(cell_index>=20 && cell_index<=23)begin override_en=1;override_char="0"+meta_g[15-(cell_index-20)*4-:4];end
                else if(cell_index>=25 && cell_index<=28)begin override_en=1;override_char="0"+meta_g[47-(cell_index-25)*4-:4];end
            end
            18:if(PERCENT_CONTRAST)begin
                case(cell_index)
                    0:begin override_en=1;override_char=adjust_mode_g?"A":"N";end
                    1:begin override_en=1;override_char=adjust_mode_g?"D":"O";end
                    2:begin override_en=1;override_char=adjust_mode_g?"J":"R";end
                    3:begin override_en=1;override_char=adjust_mode_g?" ":"M";end
                    9:begin override_en=1;override_char=brightness_g[7]?"-":"+";end
                    10,11,12:begin override_en=1;override_char="0"+bri_digits_g[11-(cell_index-10)*4-:4];end
                    18,19,20:begin override_en=1;override_char="0"+con_digits_g[11-(cell_index-18)*4-:4];end
                    25:begin override_en=1;override_char=adjust_target_g?"C":"B";end
                    29:begin override_en=1;override_char=adjust_fast_g?"Q":"F";end
                endcase
            end else case(cell_index)
                8:begin override_en=1;override_char=brightness_g[7]?"-":"+";end
                9:begin override_en=1;override_char="0"+brightness_magnitude/10;end
                10:begin override_en=1;override_char="0"+brightness_magnitude%10;end
                16:begin override_en=1;override_char=contrast_g==0?"0":"1";end
                17:begin override_en=1;override_char=contrast_g==0?"7":contrast_g==1?"0":contrast_g==2?"2":"5";end
                18:begin override_en=1;override_char=contrast_g==0 || contrast_g==2?"5":"0";end
                22:begin override_en=1;override_char=adjust_target_g?"C":"B";end
                26:begin override_en=1;override_char=adjust_fast_g?"Q":"F";end
            endcase
        endcase

    end
    reg [10:0] address_s1;
    reg override_s1,override_s2;
    reg [7:0] dynamic_s1,dynamic_s2,ascii_s2;
    reg [2:0] row_s1,row_s2,col_s1,col_s2,col_s3,col_s4;
    reg text_s1,text_s2,text_s3,text_s4,shadow_s1,shadow_s2,shadow_s3,shadow_s4;
    reg top_s1,top_s2,top_s3,top_s4;
    reg [23:0] color_s1,color_s2,color_s3,color_s4;
    reg scene_s1,scene_s2;
    reg [5:0] glyph_s3;
    reg punct_s3,punct_s4;
    reg [7:0] punctuation_s3,punctuation_s4;
    reg [7:0] text_rom [0:2047];
    integer init_address;
    task put_text;
        input integer id,length;
        input [255:0] message;
        integer k;
        begin for(k=0;k<length;k=k+1)text_rom[id*32+k]=message[(length-1-k)*8+:8];end
    endtask
    initial begin
        for(init_address=0;init_address<2048;init_address=init_address+1)text_rom[init_address]=8'h20;
        put_text(36,6,"ADJUST");
        put_text(37,27,"SRC:0000X0000 OUT:1280X0720");
        put_text(38,29,"FIT   X:0000/0000 Y:0000/0000");
        put_text(39,29,"FILL  X:0000/0000 Y:0000/0000");
        put_text(40,29,"STR   X:0000/0000 Y:0000/0000");
        if(PERCENT_CONTRAST)put_text(41,30,"NORM BRI +000 CON 100% T:B S:F");
        else put_text(41,27,"ADJ BRI:+00 CON:100 T:B S:F");
        put_text(42,15,"NEXT SCENE WAIT");
        text_rom[0]=8'h41;
        text_rom[1]=8'h4E;
        text_rom[2]=8'h4C;
        text_rom[3]=8'h4F;
        text_rom[4]=8'h47;
        text_rom[5]=8'h49;
        text_rom[6]=8'h43;
        text_rom[32]=8'h4C;
        text_rom[33]=8'h4F;
        text_rom[34]=8'h41;
        text_rom[35]=8'h44;
        text_rom[36]=8'h49;
        text_rom[37]=8'h4E;
        text_rom[38]=8'h47;
        text_rom[64]=8'h49;
        text_rom[65]=8'h4D;
        text_rom[66]=8'h47;
        text_rom[67]=8'h3A;
        text_rom[68]=8'h30;
        text_rom[69]=8'h31;
        text_rom[96]=8'h49;
        text_rom[97]=8'h4D;
        text_rom[98]=8'h47;
        text_rom[99]=8'h3A;
        text_rom[100]=8'h2D;
        text_rom[101]=8'h2D;
        text_rom[128]=8'h41;
        text_rom[129]=8'h55;
        text_rom[130]=8'h54;
        text_rom[131]=8'h4F;
        text_rom[160]=8'h4D;
        text_rom[161]=8'h41;
        text_rom[162]=8'h4E;
        text_rom[163]=8'h55;
        text_rom[164]=8'h41;
        text_rom[165]=8'h4C;
        text_rom[192]=8'h30;
        text_rom[193]=8'h35;
        text_rom[194]=8'h53;
        text_rom[224]=8'h4E;
        text_rom[225]=8'h4F;
        text_rom[226]=8'h52;
        text_rom[227]=8'h4D;
        text_rom[228]=8'h41;
        text_rom[229]=8'h4C;
        text_rom[256]=8'h53;
        text_rom[257]=8'h4F;
        text_rom[258]=8'h46;
        text_rom[259]=8'h54;
        text_rom[288]=8'h42;
        text_rom[289]=8'h52;
        text_rom[290]=8'h49;
        text_rom[291]=8'h47;
        text_rom[292]=8'h48;
        text_rom[293]=8'h54;
        text_rom[320]=8'h56;
        text_rom[321]=8'h49;
        text_rom[322]=8'h56;
        text_rom[323]=8'h49;
        text_rom[324]=8'h44;
        text_rom[352]=8'h4D;
        text_rom[353]=8'h30;
        text_rom[354]=8'h31;
        text_rom[384]=8'h4D;
        text_rom[385]=8'h2D;
        text_rom[386]=8'h2D;
        text_rom[416]=8'h4E;
        text_rom[417]=8'h4F;
        text_rom[418]=8'h54;
        text_rom[419]=8'h45;
        text_rom[420]=8'h3A;
        text_rom[421]=8'h43;
        text_rom[422]=8'h34;
        text_rom[448]=8'h4E;
        text_rom[449]=8'h4F;
        text_rom[450]=8'h54;
        text_rom[451]=8'h45;
        text_rom[452]=8'h3A;
        text_rom[453]=8'h2D;
        text_rom[454]=8'h2D;
        text_rom[480]=8'h31;
        text_rom[481]=8'h2F;
        text_rom[482]=8'h38;
        text_rom[512]=8'h2D;
        text_rom[513]=8'h2F;
        text_rom[514]=8'h38;
        text_rom[544]=8'h49;
        text_rom[545]=8'h4E;
        text_rom[546]=8'h54;
        text_rom[547]=8'h45;
        text_rom[548]=8'h52;
        text_rom[549]=8'h56;
        text_rom[550]=8'h41;
        text_rom[551]=8'h4C;
        text_rom[552]=8'h3A;
        text_rom[553]=8'h30;
        text_rom[554]=8'h35;
        text_rom[555]=8'h53;
        text_rom[576]=8'h4D;
        text_rom[577]=8'h4F;
        text_rom[578]=8'h44;
        text_rom[579]=8'h45;
        text_rom[580]=8'h3A;
        text_rom[581]=8'h41;
        text_rom[582]=8'h55;
        text_rom[583]=8'h54;
        text_rom[584]=8'h4F;
        text_rom[608]=8'h4D;
        text_rom[609]=8'h4F;
        text_rom[610]=8'h44;
        text_rom[611]=8'h45;
        text_rom[612]=8'h3A;
        text_rom[613]=8'h4D;
        text_rom[614]=8'h41;
        text_rom[615]=8'h4E;
        text_rom[616]=8'h55;
        text_rom[617]=8'h41;
        text_rom[618]=8'h4C;
        text_rom[640]=8'h4E;
        text_rom[641]=8'h4F;
        text_rom[642]=8'h52;
        text_rom[643]=8'h4D;
        text_rom[644]=8'h41;
        text_rom[645]=8'h4C;
        text_rom[647]=8'h42;
        text_rom[648]=8'h52;
        text_rom[649]=8'h49;
        text_rom[650]=8'h3A;
        text_rom[651]=8'h2B;
        text_rom[652]=8'h30;
        text_rom[653]=8'h30;
        text_rom[655]=8'h43;
        text_rom[656]=8'h4F;
        text_rom[657]=8'h4E;
        text_rom[658]=8'h3A;
        text_rom[659]=8'h31;
        text_rom[660]=8'h30;
        text_rom[661]=8'h30;
        text_rom[672]=8'h53;
        text_rom[673]=8'h4F;
        text_rom[674]=8'h46;
        text_rom[675]=8'h54;
        text_rom[677]=8'h42;
        text_rom[678]=8'h52;
        text_rom[679]=8'h49;
        text_rom[680]=8'h3A;
        text_rom[681]=8'h2D;
        text_rom[682]=8'h33;
        text_rom[683]=8'h32;
        text_rom[685]=8'h43;
        text_rom[686]=8'h4F;
        text_rom[687]=8'h4E;
        text_rom[688]=8'h3A;
        text_rom[689]=8'h30;
        text_rom[690]=8'h37;
        text_rom[691]=8'h35;
        text_rom[704]=8'h42;
        text_rom[705]=8'h52;
        text_rom[706]=8'h49;
        text_rom[707]=8'h47;
        text_rom[708]=8'h48;
        text_rom[709]=8'h54;
        text_rom[711]=8'h42;
        text_rom[712]=8'h52;
        text_rom[713]=8'h49;
        text_rom[714]=8'h3A;
        text_rom[715]=8'h2B;
        text_rom[716]=8'h31;
        text_rom[717]=8'h36;
        text_rom[719]=8'h43;
        text_rom[720]=8'h4F;
        text_rom[721]=8'h4E;
        text_rom[722]=8'h3A;
        text_rom[723]=8'h31;
        text_rom[724]=8'h30;
        text_rom[725]=8'h30;
        text_rom[736]=8'h56;
        text_rom[737]=8'h49;
        text_rom[738]=8'h56;
        text_rom[739]=8'h49;
        text_rom[740]=8'h44;
        text_rom[742]=8'h42;
        text_rom[743]=8'h52;
        text_rom[744]=8'h49;
        text_rom[745]=8'h3A;
        text_rom[746]=8'h2B;
        text_rom[747]=8'h30;
        text_rom[748]=8'h30;
        text_rom[750]=8'h43;
        text_rom[751]=8'h4F;
        text_rom[752]=8'h4E;
        text_rom[753]=8'h3A;
        text_rom[754]=8'h31;
        text_rom[755]=8'h32;
        text_rom[756]=8'h35;
        text_rom[768]=8'h53;
        text_rom[769]=8'h55;
        text_rom[770]=8'h42;
        text_rom[771]=8'h3A;
        text_rom[772]=8'h4F;
        text_rom[773]=8'h4E;
        text_rom[800]=8'h53;
        text_rom[801]=8'h55;
        text_rom[802]=8'h42;
        text_rom[803]=8'h3A;
        text_rom[804]=8'h4F;
        text_rom[805]=8'h46;
        text_rom[806]=8'h46;
        text_rom[832]=8'h56;
        text_rom[833]=8'h49;
        text_rom[834]=8'h53;
        text_rom[835]=8'h3A;
        text_rom[836]=8'h4F;
        text_rom[837]=8'h4E;
        text_rom[864]=8'h56;
        text_rom[865]=8'h49;
        text_rom[866]=8'h53;
        text_rom[867]=8'h3A;
        text_rom[868]=8'h4F;
        text_rom[869]=8'h46;
        text_rom[870]=8'h46;
        text_rom[928]=8'h53;
        text_rom[929]=8'h43;
        text_rom[930]=8'h45;
        text_rom[931]=8'h4E;
        text_rom[932]=8'h45;
        text_rom[934]=8'h30;
        text_rom[935]=8'h31;
        text_rom[937]=8'h2F;
        text_rom[939]=8'h4D;
        text_rom[940]=8'h45;
        text_rom[941]=8'h4C;
        text_rom[942]=8'h4F;
        text_rom[943]=8'h44;
        text_rom[944]=8'h59;
        text_rom[946]=8'h30;
        text_rom[947]=8'h31;
        text_rom[960]=8'h42;
        text_rom[961]=8'h4D;
        text_rom[962]=8'h50;
        text_rom[964]=8'h46;
        text_rom[965]=8'h4F;
        text_rom[966]=8'h52;
        text_rom[967]=8'h4D;
        text_rom[968]=8'h41;
        text_rom[969]=8'h54;
        text_rom[971]=8'h45;
        text_rom[972]=8'h52;
        text_rom[973]=8'h52;
        text_rom[974]=8'h4F;
        text_rom[975]=8'h52;
        text_rom[992]=8'h42;
        text_rom[993]=8'h4D;
        text_rom[994]=8'h50;
        text_rom[996]=8'h53;
        text_rom[997]=8'h49;
        text_rom[998]=8'h5A;
        text_rom[999]=8'h45;
        text_rom[1001]=8'h45;
        text_rom[1002]=8'h52;
        text_rom[1003]=8'h52;
        text_rom[1004]=8'h4F;
        text_rom[1005]=8'h52;
        text_rom[1024]=8'h42;
        text_rom[1025]=8'h4D;
        text_rom[1026]=8'h50;
        text_rom[1028]=8'h4C;
        text_rom[1029]=8'h45;
        text_rom[1030]=8'h4E;
        text_rom[1031]=8'h47;
        text_rom[1032]=8'h54;
        text_rom[1033]=8'h48;
        text_rom[1035]=8'h45;
        text_rom[1036]=8'h52;
        text_rom[1037]=8'h52;
        text_rom[1038]=8'h4F;
        text_rom[1039]=8'h52;
        text_rom[1056]=8'h53;
        text_rom[1057]=8'h44;
        text_rom[1059]=8'h52;
        text_rom[1060]=8'h45;
        text_rom[1061]=8'h41;
        text_rom[1062]=8'h44;
        text_rom[1064]=8'h45;
        text_rom[1065]=8'h52;
        text_rom[1066]=8'h52;
        text_rom[1067]=8'h4F;
        text_rom[1068]=8'h52;
        text_rom[1088]=8'h4E;
        text_rom[1089]=8'h4F;
        text_rom[1091]=8'h42;
        text_rom[1092]=8'h4D;
        text_rom[1093]=8'h50;
        text_rom[1095]=8'h46;
        text_rom[1096]=8'h4F;
        text_rom[1097]=8'h55;
        text_rom[1098]=8'h4E;
        text_rom[1099]=8'h44;
        text_rom[1120]=8'h4C;
        text_rom[1121]=8'h4F;
        text_rom[1122]=8'h41;
        text_rom[1123]=8'h44;
        text_rom[1125]=8'h43;
        text_rom[1126]=8'h41;
        text_rom[1127]=8'h4E;
        text_rom[1128]=8'h43;
        text_rom[1129]=8'h45;
        text_rom[1130]=8'h4C;
        text_rom[1131]=8'h4C;
        text_rom[1132]=8'h45;
        text_rom[1133]=8'h44;
    end
    // P2: synchronous 2K x 8 text ROM, two ERAM9K at most.
    // ID 63 contains spaces and is additionally gated by text_s4.
    always @(posedge pixel_clk) ascii_s2<=text_rom[address_s1];
    wire [7:0] selected_ascii=override_s2?dynamic_s2:ascii_s2;
    wire [7:0] font_bits;
    // P4: synchronous glyph read, AFTER registered ASCII-to-glyph decode P3.
    reg [2:0] row_s3;
    subtitle_font_rom font(.pixel_clk(pixel_clk),.glyph_code(glyph_s3),.glyph_row(row_s3),.font_bits(font_bits));
    localparam PIXEL_BITS=27+2*COORD_BITS;
    reg [PIXEL_BITS-1:0] pixels[0:4]; // {HS,VS,DE,x,y,RGB}, all five stages.
    integer pipe;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin
            for(pipe=0;pipe<5;pipe=pipe+1)pixels[pipe]<=0;
            address_s1<=0;override_s1<=0;override_s2<=0;dynamic_s1<=0;dynamic_s2<=0;
            row_s1<=0;row_s2<=0;row_s3<=0;col_s1<=0;col_s2<=0;col_s3<=0;col_s4<=0;
            text_s1<=0;text_s2<=0;text_s3<=0;text_s4<=0;
            shadow_s1<=0;shadow_s2<=0;shadow_s3<=0;shadow_s4<=0;
            top_s1<=0;top_s2<=0;top_s3<=0;top_s4<=0;
            color_s1<=0;color_s2<=0;color_s3<=0;color_s4<=0;
            glyph_s3<=0;punct_s3<=0;punct_s4<=0;punctuation_s3<=0;punctuation_s4<=0;
            scene_s1<=0;scene_s2<=0;
        end else begin
            pixels[0]<={hs,vs,de,x,y,background_rgb};
            for(pipe=1;pipe<5;pipe=pipe+1)pixels[pipe]<=pixels[pipe-1];
            address_s1<={kind,cell_g};override_s1<=override_en;dynamic_s1<=override_char;
            override_s2<=override_s1;dynamic_s2<=dynamic_s1;
            row_s1<=row_g;row_s2<=row_s1;row_s3<=row_s2;
            col_s1<=col_g;col_s2<=col_s1;col_s3<=col_s2;col_s4<=col_s3;
            text_s1<=area_g!=31;text_s2<=text_s1;text_s3<=text_s2;text_s4<=text_s3;
            shadow_s1<=area_g==13 || area_g==14 || area_g==15;
            scene_s1<=area_g==14;scene_s2<=scene_s1;
            shadow_s2<=shadow_s1;shadow_s3<=shadow_s2;shadow_s4<=shadow_s3;
            top_s1<=area_g<=4 || (COMPLIANCE_UI && area_g>=16 && area_g<=19);top_s2<=top_s1;top_s3<=top_s2;top_s4<=top_s3;
            color_s1<=color_g;color_s2<=color_s1;color_s3<=color_s2;color_s4<=color_s3;
            glyph_s3<=glyph_code(selected_ascii);
            punct_s3<=(selected_ascii==":" || selected_ascii=="-" || selected_ascii=="+" || selected_ascii=="/" || selected_ascii=="%");
            punctuation_s3<=(COMPLIANCE_UI && scene_s2 && selected_ascii=="/")?
                scene_slash(row_s2):punctuation(selected_ascii,row_s2);
            punct_s4<=punct_s3;punctuation_s4<=punctuation_s3;
        end
    end
    always @* {out_hs,out_vs,out_de,out_x,out_y}=pixels[4][PIXEL_BITS-1:24];
    wire [7:0] selected_bits=punct_s4?punctuation_s4:font_bits;
    wire foreground_dot=text_s4 && selected_bits[7-col_s4];
    wire left_outline=shadow_s4 && col_s4<7 && selected_bits[6-col_s4];
    reg previous_outline_dot,previous_top_dot,previous_de;
    reg [COORD_BITS-1:0] previous_x,previous_y;
    always @(posedge pixel_clk or posedge reset)begin
        if(reset)begin previous_outline_dot<=0;previous_top_dot<=0;previous_de<=0;previous_x<=0;previous_y<=0;end
        else begin
            previous_outline_dot<=foreground_dot && shadow_s4;
            previous_top_dot<=foreground_dot && top_s4;
            previous_de<=out_de;previous_x<=out_x;previous_y<=out_y;
        end
    end
    wire right_outline=previous_outline_dot && previous_de && previous_y==out_y && previous_x+10'd1==out_x;
    wire top_right_shadow=previous_top_dot && previous_de && previous_y==out_y && previous_x+10'd1==out_x;
    always @* begin
        if(reset || !out_de)output_rgb=0;
        else if(foreground_dot)output_rgb=color_s4;
        else if(left_outline || right_outline)output_rgb=0;
        else if(top_right_shadow)output_rgb=24'h102C48;
        else output_rgb=pixels[4][23:0];
    end
endmodule
