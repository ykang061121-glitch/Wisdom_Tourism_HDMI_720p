// Independent oracle: MIDI score, mathematical rectangles, packed glyphs.
`include "subtitle_reference.vh"
function automatic integer ref_midi(input integer melody,step);
    reg [63:0] score;
    begin case(melody)
        0:score=64'h3c3e4043403e4348;1:score=64'h303734323034373c;
        2:score=64'h3c40434843404348;default:score=64'h45484c4a47434845;
    endcase ref_midi=(score>>(8*(7-step)))&255;end
endfunction
function automatic integer ref_bar_height(input integer midi);
    begin case(midi)
        48:ref_bar_height=20;50:ref_bar_height=24;52:ref_bar_height=28;55:ref_bar_height=32;
        60:ref_bar_height=36;62:ref_bar_height=40;64:ref_bar_height=44;67:ref_bar_height=48;
        69:ref_bar_height=52;71:ref_bar_height=56;72:ref_bar_height=60;74:ref_bar_height=64;76:ref_bar_height=68;
        default:$fatal(1,"bad reference MIDI");
    endcase end
endfunction
function automatic string ref_note_name(input integer midi);
    string letter;
    begin
        case(midi%12)0:letter="C";2:letter="D";4:letter="E";7:letter="G";9:letter="A";11:letter="B";
            default:$fatal(1,"unsupported reference note");endcase
        ref_note_name=$sformatf("%s%0d",letter,midi/12-1);
    end
endfunction
// Compact layout oracle. Musical ranks derive from independent MIDI data.
function automatic integer ref_compact_height(input integer midi);
    begin ref_compact_height=4+(ref_bar_height(midi)-16)/2;end
endfunction
function automatic [23:0] ref_music_pixel(input integer px,py,active,visible,
    input [9:0] status,input integer pcm_valid,amplitude,input [23:0] background);
    integer slot,midi,dy;
    begin
        ref_music_pixel=active?background:0;
        if(active && visible && px>=400 && px<=631 && py>=375 && py<=451)begin
            ref_music_pixel=24'h0B1725;
            if(px==400 || px==631 || py==375 || py==451)ref_music_pixel=24'h245674;
            else begin
                if(py==398)ref_music_pixel=24'h163C54;
                if(px>=408 && px<624)begin
                    slot=(px-408)/27;midi=ref_midi(status[8:7],slot);
                    if(slot<8 && (px-408)%27<18 && py<=439 && py>=439-ref_compact_height(midi))begin
                        if(status[9] && slot==status[6:4])ref_music_pixel=status[0]?24'h00FF9A:24'h4F8D83;
                        else if(status[9] && slot<status[6:4])ref_music_pixel=24'h287DA8;
                        else ref_music_pixel=24'h12384F;
                    end
                end
                if(px>=408 && px<=623 && py>=445 && py<=449)begin
                    ref_music_pixel=24'h101E30;if(py==447)ref_music_pixel=24'h254459;
                    dy=447-((amplitude<0)?-((-amplitude+31)/32):amplitude/32);
                    if(pcm_valid && py>=dy && py<=dy+1)ref_music_pixel=24'h00FF80;
                end
            end
        end
    end
endfunction
function automatic [23:0] ref_subtitle_plate(input integer px,py,active,visible,input [23:0] background);
    begin ref_subtitle_plate=active?background:0;end
endfunction
// Coordinate translation calls the independently packed, legacy font oracle,
// not DUT state or font memory. Two dots provide a one-pixel right shadow.
function automatic [23:0] ref_compact_subtitle(input integer px,py,active,frames,fpp,gf,
    input [23:0] background);
    integer old_y;
    reg fg,shadow;
    begin
        old_y=-1;
        if(py>=456 && py<472)old_y=184+py-456;
        else if(py>=386 && py<402)old_y=250+py-386;
        else if(py>=410 && py<426)old_y=276+py-410;
        fg=0;shadow=0;
        if(active && old_y>=0 && px>=16 && px<=623)begin
            fg=(ref_subtitle(px,old_y,1,frames,fpp,gf,0)==24'hFFCC40);
            if(px>16)shadow=(ref_subtitle(px-1,old_y,1,frames,fpp,gf,0)==24'hFFCC40);
        end
        ref_compact_subtitle=active?(fg?24'hFFCC40:shadow?24'd0:background):0;
    end
endfunction
function automatic bit ref_ui_dot(input integer ascii,row,column);
    reg [63:0] bitmap;
    begin bitmap=(ascii==47)?64'h060c183060606000:ref_bitmap(ascii);
        ref_ui_dot=bitmap[63-row*8-column];end
endfunction
function automatic [23:0] ref_print(input integer px,py,ox,oy,input string text_value,
    input [23:0] foreground,background);
    integer cx,cy;
    begin
        ref_print=background;cx=px-ox;cy=py-oy;
        if(cx>=0 && cx<text_value.len()*8 && cy>=0 && cy<16 &&
           ref_ui_dot(text_value[cx/8],cy/2,cx%8))ref_print=foreground;
    end
endfunction
// Independent morphological outline, from packed glyph coordinates.
function automatic bit ref_word_dot(input integer px,py,ox,oy,input string word);
    integer cx,cy;
    begin cx=px-ox;cy=py-oy;
        ref_word_dot=(cx>=0 && cx<word.len()*8 && cy>=0 && cy<16)?
            ref_ui_dot(word[cx/8],cy/2,cx%8):0;
    end
endfunction
function automatic [23:0] ref_print_outline(input integer px,py,ox,oy,input string word,
    input [23:0] foreground,background);
    begin
        ref_print_outline=background;
        if(ref_word_dot(px,py,ox,oy,word))ref_print_outline=foreground;
        else if(ref_word_dot(px-1,py,ox,oy,word) || ref_word_dot(px+1,py,ox,oy,word))
            ref_print_outline=0;
    end
endfunction
// Independent strings and formatting, no DUT selector/state-machine reuse.
function automatic [23:0] ref_print_top_shadow(input integer px,py,ox,oy,input string word,
    input [23:0] foreground,background);
    begin
        ref_print_top_shadow=background;
        if(ref_word_dot(px,py,ox,oy,word))ref_print_top_shadow=foreground;
        else if(ref_word_dot(px-1,py,ox,oy,word))ref_print_top_shadow=24'h102C48;
    end
endfunction
function automatic [23:0] ref_showcase_ui(input integer px,py,active,valid,image,auto_mode,interval_code,preset,
    bri,con,fade,input [9:0] music,input integer notice,index,hint,kind,input [23:0] background);
    reg [23:0] p;
    string label,style;
    integer seconds_value;
    begin
        case(interval_code)0:seconds_value=1;1:seconds_value=3;2:seconds_value=5;3:seconds_value=10;endcase
        case(preset&3)0:style="NORMAL";1:style="SOFT";2:style="BRIGHT";3:style="VIVID";endcase
        p=active?background:0;
        if(active && px>=8 && px<=631 && py>=8 && py<=39)begin
            p=ref_print_top_shadow(px,py,16,16,valid?"ANLOGIC":"LOADING",24'h00C8DC,p);
            label=valid?$sformatf("IMG:0%0d",image+1):"IMG:--";p=ref_print_top_shadow(px,py,112,16,label,24'hFFC000,p);
            p=ref_print_top_shadow(px,py,208,16,auto_mode?"AUTO":"MANUAL",24'h00D070,p);
            p=ref_print_top_shadow(px,py,304,16,$sformatf("%02dS",seconds_value),24'hFFC000,p);
            p=ref_print_top_shadow(px,py,400,16,style,24'h00BFA5,p);
        end
        if(active && hint && px>=8 && px<=319 && py>=44 && py<=67)begin
            if(hint)case(kind)
                1:label=$sformatf("INTERVAL:%02dS",seconds_value);
                2:label=auto_mode?"MODE:AUTO":"MODE:MANUAL";
                3:begin
                    case(preset&3)
                        0:label="NORMAL BRI:+00 CON:100";1:label="SOFT BRI:-32 CON:075";
                        2:label="BRIGHT BRI:+16 CON:100";3:label="VIVID BRI:+00 CON:125";
                    endcase
                end
                4:label=(preset&4)?"SUB:OFF":"SUB:ON";
                5:label=(preset&8)?"VIS:OFF":"VIS:ON";
                default:label="";
            endcase
            p=ref_print_outline(px,py,16,48,label,24'hEAF6FF,p);
        end
        if(active && !(preset&8))begin
            label=music[9]?$sformatf("M0%0d",music[8:7]+1):"M--";
            p=ref_print(px,py,408,379,label,24'h50D9FF,p);
            label=music[9]?{"NOTE:",ref_note_name(ref_midi(music[8:7],music[6:4]))}:"NOTE:--";
            p=ref_print(px,py,448,379,label,24'hEAF6FF,p);
            label=music[9]?$sformatf("%0d/8",music[6:4]+1):"-/8";
            p=ref_print(px,py,584,379,label,music[0]?24'h00FF9A:24'h8CA6B8,p);
        end
        if(active && notice && px>=400 && px<=631 && py>=44 && py<=67)begin
            p=ref_print_outline(px,py,408,48,$sformatf("SCENE 0%0d / MELODY 0%0d",index+1,index+1),24'hEAF6FF,p);
        end
        ref_showcase_ui=p;
    end
endfunction
