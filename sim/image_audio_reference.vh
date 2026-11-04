// Independent score representation: MIDI bytes, not DUT pitch codes/functions.
function automatic [31:0] reference_increment(input integer image,note);
    reg [63:0] score;
    integer midi;
    begin
        case(image)
            0:score=64'h3c3e4043403e4348;
            1:score=64'h303734323034373c;
            2:score=64'h3c40434843404348;
            default:score=64'h45484c4a47434845;
        endcase
        midi=(score>>((7-note)*8))&255;
        case(midi)
            48:reference_increment=11704931; 50:reference_increment=13138341;
            52:reference_increment=14747289; 55:reference_increment=17537578;
            60:reference_increment=23409862; 62:reference_increment=26276681;
            64:reference_increment=29494578; 67:reference_increment=35075155;
            69:reference_increment=39370534; 71:reference_increment=44191930;
            72:reference_increment=46819716; 74:reference_increment=52553362;
            76:reference_increment=58989156;
            default:$fatal(1,"bad reference MIDI score");
        endcase
    end
endfunction
function automatic integer reference_duration(input integer image,note,base);
    begin
        case(image)
            0:reference_duration=base;
            1:reference_duration=base*2;
            2:reference_duration=base/2;
            default:reference_duration=(note==2 || note==7)?base*3/2:base;
        endcase
    end
endfunction
