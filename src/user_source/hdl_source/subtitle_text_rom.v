// Nine constant ASCII strings, 64 byte cells per page. Unused cells are
// spaces. One synchronous read port avoids a wide variable string selector.
module subtitle_text_rom #(parameter integer TOURISM_TEXT=0)(
    input wire pixel_clk,
    input wire [9:0] address,
    output reg [7:0] character
);
    reg [7:0] rom [0:1023];
    integer init_address;
    task put_line;
        input integer page,length;
        input [255:0] value;
        integer column;
        begin
            for(column=0;column<length;column=column+1)
                rom[page*64+column]=value[(length-1-column)*8+:8];
        end
    endtask
    initial begin
        for (init_address=0; init_address<1024; init_address=init_address+1)
            rom[init_address]=8'h20;
        // page 0: WELCOME TO ANLOGIC FPGA MULTIMEDIA DEMO
        rom[0]=8'h57;
        rom[1]=8'h45;
        rom[2]=8'h4C;
        rom[3]=8'h43;
        rom[4]=8'h4F;
        rom[5]=8'h4D;
        rom[6]=8'h45;
        rom[8]=8'h54;
        rom[9]=8'h4F;
        rom[11]=8'h41;
        rom[12]=8'h4E;
        rom[13]=8'h4C;
        rom[14]=8'h4F;
        rom[15]=8'h47;
        rom[16]=8'h49;
        rom[17]=8'h43;
        rom[19]=8'h46;
        rom[20]=8'h50;
        rom[21]=8'h47;
        rom[22]=8'h41;
        rom[24]=8'h4D;
        rom[25]=8'h55;
        rom[26]=8'h4C;
        rom[27]=8'h54;
        rom[28]=8'h49;
        rom[29]=8'h4D;
        rom[30]=8'h45;
        rom[31]=8'h44;
        rom[32]=8'h49;
        rom[33]=8'h41;
        rom[35]=8'h44;
        rom[36]=8'h45;
        rom[37]=8'h4D;
        rom[38]=8'h4F;
        // page 1: HDMI VIDEO AUDIO AND IMAGE SCALING
        rom[64]=8'h48;
        rom[65]=8'h44;
        rom[66]=8'h4D;
        rom[67]=8'h49;
        rom[69]=8'h56;
        rom[70]=8'h49;
        rom[71]=8'h44;
        rom[72]=8'h45;
        rom[73]=8'h4F;
        rom[75]=8'h41;
        rom[76]=8'h55;
        rom[77]=8'h44;
        rom[78]=8'h49;
        rom[79]=8'h4F;
        rom[81]=8'h41;
        rom[82]=8'h4E;
        rom[83]=8'h44;
        rom[85]=8'h49;
        rom[86]=8'h4D;
        rom[87]=8'h41;
        rom[88]=8'h47;
        rom[89]=8'h45;
        rom[91]=8'h53;
        rom[92]=8'h43;
        rom[93]=8'h41;
        rom[94]=8'h4C;
        rom[95]=8'h49;
        rom[96]=8'h4E;
        rom[97]=8'h47;
        // page 2: FPGA REAL TIME PROCESSING
        rom[128]=8'h46;
        rom[129]=8'h50;
        rom[130]=8'h47;
        rom[131]=8'h41;
        rom[133]=8'h52;
        rom[134]=8'h45;
        rom[135]=8'h41;
        rom[136]=8'h4C;
        rom[138]=8'h54;
        rom[139]=8'h49;
        rom[140]=8'h4D;
        rom[141]=8'h45;
        rom[143]=8'h50;
        rom[144]=8'h52;
        rom[145]=8'h4F;
        rom[146]=8'h43;
        rom[147]=8'h45;
        rom[148]=8'h53;
        rom[149]=8'h53;
        rom[150]=8'h49;
        rom[151]=8'h4E;
        rom[152]=8'h47;
        // page 3: ANLOGIC FPGA MULTIMEDIA
        rom[192]=8'h41;
        rom[193]=8'h4E;
        rom[194]=8'h4C;
        rom[195]=8'h4F;
        rom[196]=8'h47;
        rom[197]=8'h49;
        rom[198]=8'h43;
        rom[200]=8'h46;
        rom[201]=8'h50;
        rom[202]=8'h47;
        rom[203]=8'h41;
        rom[205]=8'h4D;
        rom[206]=8'h55;
        rom[207]=8'h4C;
        rom[208]=8'h54;
        rom[209]=8'h49;
        rom[210]=8'h4D;
        rom[211]=8'h45;
        rom[212]=8'h44;
        rom[213]=8'h49;
        rom[214]=8'h41;
        // page 4: HDMI IMAGE AND AUDIO OUTPUT
        rom[256]=8'h48;
        rom[257]=8'h44;
        rom[258]=8'h4D;
        rom[259]=8'h49;
        rom[261]=8'h49;
        rom[262]=8'h4D;
        rom[263]=8'h41;
        rom[264]=8'h47;
        rom[265]=8'h45;
        rom[267]=8'h41;
        rom[268]=8'h4E;
        rom[269]=8'h44;
        rom[271]=8'h41;
        rom[272]=8'h55;
        rom[273]=8'h44;
        rom[274]=8'h49;
        rom[275]=8'h4F;
        rom[277]=8'h4F;
        rom[278]=8'h55;
        rom[279]=8'h54;
        rom[280]=8'h50;
        rom[281]=8'h55;
        rom[282]=8'h54;
        // page 5: ADAPTIVE BMP SCALING
        rom[320]=8'h41;
        rom[321]=8'h44;
        rom[322]=8'h41;
        rom[323]=8'h50;
        rom[324]=8'h54;
        rom[325]=8'h49;
        rom[326]=8'h56;
        rom[327]=8'h45;
        rom[329]=8'h42;
        rom[330]=8'h4D;
        rom[331]=8'h50;
        rom[333]=8'h53;
        rom[334]=8'h43;
        rom[335]=8'h41;
        rom[336]=8'h4C;
        rom[337]=8'h49;
        rom[338]=8'h4E;
        rom[339]=8'h47;
        // page 6: 320x240 640x480 800x600
        rom[384]=8'h33;
        rom[385]=8'h32;
        rom[386]=8'h30;
        rom[387]=8'h78;
        rom[388]=8'h32;
        rom[389]=8'h34;
        rom[390]=8'h30;
        rom[392]=8'h36;
        rom[393]=8'h34;
        rom[394]=8'h30;
        rom[395]=8'h78;
        rom[396]=8'h34;
        rom[397]=8'h38;
        rom[398]=8'h30;
        rom[400]=8'h38;
        rom[401]=8'h30;
        rom[402]=8'h30;
        rom[403]=8'h78;
        rom[404]=8'h36;
        rom[405]=8'h30;
        rom[406]=8'h30;
        // page 7: REAL TIME VISUAL EFFECTS
        rom[448]=8'h52;
        rom[449]=8'h45;
        rom[450]=8'h41;
        rom[451]=8'h4C;
        rom[453]=8'h54;
        rom[454]=8'h49;
        rom[455]=8'h4D;
        rom[456]=8'h45;
        rom[458]=8'h56;
        rom[459]=8'h49;
        rom[460]=8'h53;
        rom[461]=8'h55;
        rom[462]=8'h41;
        rom[463]=8'h4C;
        rom[465]=8'h45;
        rom[466]=8'h46;
        rom[467]=8'h46;
        rom[468]=8'h45;
        rom[469]=8'h43;
        rom[470]=8'h54;
        rom[471]=8'h53;
        // page 8: FADE OSD AND AUDIO WAVEFORM
        rom[512]=8'h46;
        rom[513]=8'h41;
        rom[514]=8'h44;
        rom[515]=8'h45;
        rom[517]=8'h4F;
        rom[518]=8'h53;
        rom[519]=8'h44;
        rom[521]=8'h41;
        rom[522]=8'h4E;
        rom[523]=8'h44;
        rom[525]=8'h41;
        rom[526]=8'h55;
        rom[527]=8'h44;
        rom[528]=8'h49;
        rom[529]=8'h4F;
        rom[531]=8'h57;
        rom[532]=8'h41;
        rom[533]=8'h56;
        rom[534]=8'h45;
        rom[535]=8'h46;
        rom[536]=8'h4F;
        rom[537]=8'h52;
        rom[538]=8'h4D;
        // Reuse the same tiny synchronous ROM/font. The three scrolling
        // pages stay unchanged; scene pages are selected by COMMITTED image.
        if(TOURISM_TEXT)begin
            for(init_address=192;init_address<704;init_address=init_address+1)
                rom[init_address]=8'h20;
            put_line(3,9,"WEST LAKE");
            put_line(4,15,"POETIC JIANGNAN");
            put_line(5,14,"FORBIDDEN CITY");
            put_line(6,17,"IMPERIAL HERITAGE");
            put_line(7,13,"POTALA PALACE");
            put_line(8,17,"SNOWLAND HERITAGE");
            put_line(9,15,"TERRACOTTA ARMY");
            put_line(10,20,"ANCIENT CIVILIZATION");
        end
    end
    always @(posedge pixel_clk)
        character <= rom[address];
endmodule
