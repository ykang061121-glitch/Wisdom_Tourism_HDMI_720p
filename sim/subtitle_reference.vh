// Test-only golden fixture: packed whole-glyph patterns, not DUT ROM reads.
function automatic [63:0] ref_bitmap(input integer ascii);
    begin
        case(ascii)
            65:ref_bitmap=64'h183c66667e666600;
            66:ref_bitmap=64'h7c66667c66667c00;
            67:ref_bitmap=64'h3c66606060663c00;
            68:ref_bitmap=64'h786c6666666c7800;
            69:ref_bitmap=64'h7e60607c60607e00;
            70:ref_bitmap=64'h7e60607c60606000;
            71:ref_bitmap=64'h3c66606e66663c00;
            72:ref_bitmap=64'h6666667e66666600;
            73:ref_bitmap=64'h7e18181818187e00;
            74:ref_bitmap=64'h1e06060666663c00;
            75:ref_bitmap=64'h666c7870786c6600;
            76:ref_bitmap=64'h6060606060607e00;
            77:ref_bitmap=64'h63777f6b63636300;
            78:ref_bitmap=64'h66767e7e6e666600;
            79:ref_bitmap=64'h3c66666666663c00;
            80:ref_bitmap=64'h7c66667c60606000;
            81:ref_bitmap=64'h3c6666666e3c0600;
            82:ref_bitmap=64'h7c66667c6c666600;
            83:ref_bitmap=64'h3c66603c06663c00;
            84:ref_bitmap=64'h7e18181818181800;
            85:ref_bitmap=64'h6666666666663c00;
            86:ref_bitmap=64'h66666666663c1800;
            87:ref_bitmap=64'h6363636b7f776300;
            88:ref_bitmap=64'h66663c183c666600;
            89:ref_bitmap=64'h66663c1818181800;
            90:ref_bitmap=64'h7e060c1830607e00;
            48:ref_bitmap=64'h3c666e7666663c00;
            49:ref_bitmap=64'h1838181818187e00;
            50:ref_bitmap=64'h3c66060c30607e00;
            51:ref_bitmap=64'h3c66061c06663c00;
            52:ref_bitmap=64'h0c1c3c6c7e0c0c00;
            53:ref_bitmap=64'h7e60607c06663c00;
            54:ref_bitmap=64'h1c30607c66663c00;
            55:ref_bitmap=64'h7e060c1830303000;
            56:ref_bitmap=64'h3c66663c66663c00;
            57:ref_bitmap=64'h3c66663e060c3800;
            120:ref_bitmap=64'h0000663c183c6600;
            // Original OSD-only punctuation, not subtitle font ROM codes.
            58:ref_bitmap=64'h0018180018180000;
            43:ref_bitmap=64'h0000187e18000000;
            45:ref_bitmap=64'h0000007e00000000;
            default:ref_bitmap=0;
        endcase
    end
endfunction
function automatic bit ref_dot(input integer ascii,row,column);
    reg [63:0] bitmap;
    begin bitmap=ref_bitmap(ascii);ref_dot=bitmap[63-row*8-column];end
endfunction
function automatic string ref_string(input integer page_number);
    begin
        case(page_number)
            0:ref_string="WELCOME TO ANLOGIC FPGA MULTIMEDIA DEMO";
            1:ref_string="HDMI VIDEO AUDIO AND IMAGE SCALING";
            2:ref_string="FPGA REAL TIME PROCESSING";
            3:ref_string="ANLOGIC FPGA MULTIMEDIA";
            4:ref_string="HDMI IMAGE AND AUDIO OUTPUT";
            5:ref_string="ADAPTIVE BMP SCALING";
            6:ref_string="320x240 640x480 800x600";
            7:ref_string="REAL TIME VISUAL EFFECTS";
            8:ref_string="FADE OSD AND AUDIO WAVEFORM";
            default:ref_string="";
        endcase
    end
endfunction
function automatic integer ref_scroll_message(input integer frames,frames_per_pixel);
    integer p;
    begin p=(frames/frames_per_pixel)%2608;ref_scroll_message=(p<920)?0:(p<1800)?1:2;end
endfunction
function automatic integer ref_scroll_offset(input integer frames,frames_per_pixel);
    integer p;
    begin p=(frames/frames_per_pixel)%2608;ref_scroll_offset=(p<920)?p:(p<1800)?p-920:p-1800;end
endfunction
function automatic [23:0] ref_subtitle(
    input integer px,py,active,frames,frames_per_pixel,group_frames,
    input [23:0] background
);
    integer offset,message,group_number,relative,column,row,char_number,page_number;
    string text_value;
    begin
        ref_subtitle=active?background:0;
        offset=ref_scroll_offset(frames,frames_per_pixel);
        message=ref_scroll_message(frames,frames_per_pixel);
        group_number=(frames/group_frames)%3;
        relative=px-(624-offset);
        text_value="";column=0;row=0;char_number=0;page_number=-1;
        if(active && px>=16 && px<=623) begin
            if(py>=184 && py<=199) begin
                text_value=ref_string(message);
                if(relative>=0 && relative<text_value.len()*8) begin
                    char_number=relative/8;column=relative%8;row=(py-184)/2;page_number=message;
                end
            end else if(px<272 && ((py>=250 && py<=265) || (py>=276 && py<=291))) begin
                page_number=3+group_number*2+((py>=276)?1:0);
                text_value=ref_string(page_number);char_number=(px-16)/8;column=(px-16)%8;
                row=(py-((py>=276)?276:250))/2;
                if(char_number>=text_value.len()) page_number=-1;
            end
        end
        if(page_number>=0 && ref_dot(text_value[char_number],row,column)) ref_subtitle=24'hFFCC40;
    end
endfunction
