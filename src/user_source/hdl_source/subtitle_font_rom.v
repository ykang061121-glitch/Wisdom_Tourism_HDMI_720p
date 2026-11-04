// Small synchronous 8x8 bitmap ROM. The overlay doubles each row for 8x16.
// Code 0 = space; 1..26 = A..Z; 27..36 = 0..9; 37 = lowercase x.
// Unused codes read zero. No ROM reset: delayed pixel validity masks startup.
module subtitle_font_rom(
    input wire pixel_clk,
    input wire [5:0] glyph_code,
    input wire [2:0] glyph_row,
    output reg [7:0] font_bits
);
    reg [7:0] rom [0:511];
    integer init_address;
    initial begin
        for (init_address=0; init_address<512; init_address=init_address+1)
            rom[init_address]=8'h00;
        // 0: SPACE
        // 1: A
        rom[8]=8'h18;
        rom[9]=8'h3C;
        rom[10]=8'h66;
        rom[11]=8'h66;
        rom[12]=8'h7E;
        rom[13]=8'h66;
        rom[14]=8'h66;
        // 2: B
        rom[16]=8'h7C;
        rom[17]=8'h66;
        rom[18]=8'h66;
        rom[19]=8'h7C;
        rom[20]=8'h66;
        rom[21]=8'h66;
        rom[22]=8'h7C;
        // 3: C
        rom[24]=8'h3C;
        rom[25]=8'h66;
        rom[26]=8'h60;
        rom[27]=8'h60;
        rom[28]=8'h60;
        rom[29]=8'h66;
        rom[30]=8'h3C;
        // 4: D
        rom[32]=8'h78;
        rom[33]=8'h6C;
        rom[34]=8'h66;
        rom[35]=8'h66;
        rom[36]=8'h66;
        rom[37]=8'h6C;
        rom[38]=8'h78;
        // 5: E
        rom[40]=8'h7E;
        rom[41]=8'h60;
        rom[42]=8'h60;
        rom[43]=8'h7C;
        rom[44]=8'h60;
        rom[45]=8'h60;
        rom[46]=8'h7E;
        // 6: F
        rom[48]=8'h7E;
        rom[49]=8'h60;
        rom[50]=8'h60;
        rom[51]=8'h7C;
        rom[52]=8'h60;
        rom[53]=8'h60;
        rom[54]=8'h60;
        // 7: G
        rom[56]=8'h3C;
        rom[57]=8'h66;
        rom[58]=8'h60;
        rom[59]=8'h6E;
        rom[60]=8'h66;
        rom[61]=8'h66;
        rom[62]=8'h3C;
        // 8: H
        rom[64]=8'h66;
        rom[65]=8'h66;
        rom[66]=8'h66;
        rom[67]=8'h7E;
        rom[68]=8'h66;
        rom[69]=8'h66;
        rom[70]=8'h66;
        // 9: I
        rom[72]=8'h7E;
        rom[73]=8'h18;
        rom[74]=8'h18;
        rom[75]=8'h18;
        rom[76]=8'h18;
        rom[77]=8'h18;
        rom[78]=8'h7E;
        // 10: J
        rom[80]=8'h1E;
        rom[81]=8'h06;
        rom[82]=8'h06;
        rom[83]=8'h06;
        rom[84]=8'h66;
        rom[85]=8'h66;
        rom[86]=8'h3C;
        // 11: K
        rom[88]=8'h66;
        rom[89]=8'h6C;
        rom[90]=8'h78;
        rom[91]=8'h70;
        rom[92]=8'h78;
        rom[93]=8'h6C;
        rom[94]=8'h66;
        // 12: L
        rom[96]=8'h60;
        rom[97]=8'h60;
        rom[98]=8'h60;
        rom[99]=8'h60;
        rom[100]=8'h60;
        rom[101]=8'h60;
        rom[102]=8'h7E;
        // 13: M
        rom[104]=8'h63;
        rom[105]=8'h77;
        rom[106]=8'h7F;
        rom[107]=8'h6B;
        rom[108]=8'h63;
        rom[109]=8'h63;
        rom[110]=8'h63;
        // 14: N
        rom[112]=8'h66;
        rom[113]=8'h76;
        rom[114]=8'h7E;
        rom[115]=8'h7E;
        rom[116]=8'h6E;
        rom[117]=8'h66;
        rom[118]=8'h66;
        // 15: O
        rom[120]=8'h3C;
        rom[121]=8'h66;
        rom[122]=8'h66;
        rom[123]=8'h66;
        rom[124]=8'h66;
        rom[125]=8'h66;
        rom[126]=8'h3C;
        // 16: P
        rom[128]=8'h7C;
        rom[129]=8'h66;
        rom[130]=8'h66;
        rom[131]=8'h7C;
        rom[132]=8'h60;
        rom[133]=8'h60;
        rom[134]=8'h60;
        // 17: Q
        rom[136]=8'h3C;
        rom[137]=8'h66;
        rom[138]=8'h66;
        rom[139]=8'h66;
        rom[140]=8'h6E;
        rom[141]=8'h3C;
        rom[142]=8'h06;
        // 18: R
        rom[144]=8'h7C;
        rom[145]=8'h66;
        rom[146]=8'h66;
        rom[147]=8'h7C;
        rom[148]=8'h6C;
        rom[149]=8'h66;
        rom[150]=8'h66;
        // 19: S
        rom[152]=8'h3C;
        rom[153]=8'h66;
        rom[154]=8'h60;
        rom[155]=8'h3C;
        rom[156]=8'h06;
        rom[157]=8'h66;
        rom[158]=8'h3C;
        // 20: T
        rom[160]=8'h7E;
        rom[161]=8'h18;
        rom[162]=8'h18;
        rom[163]=8'h18;
        rom[164]=8'h18;
        rom[165]=8'h18;
        rom[166]=8'h18;
        // 21: U
        rom[168]=8'h66;
        rom[169]=8'h66;
        rom[170]=8'h66;
        rom[171]=8'h66;
        rom[172]=8'h66;
        rom[173]=8'h66;
        rom[174]=8'h3C;
        // 22: V
        rom[176]=8'h66;
        rom[177]=8'h66;
        rom[178]=8'h66;
        rom[179]=8'h66;
        rom[180]=8'h66;
        rom[181]=8'h3C;
        rom[182]=8'h18;
        // 23: W
        rom[184]=8'h63;
        rom[185]=8'h63;
        rom[186]=8'h63;
        rom[187]=8'h6B;
        rom[188]=8'h7F;
        rom[189]=8'h77;
        rom[190]=8'h63;
        // 24: X
        rom[192]=8'h66;
        rom[193]=8'h66;
        rom[194]=8'h3C;
        rom[195]=8'h18;
        rom[196]=8'h3C;
        rom[197]=8'h66;
        rom[198]=8'h66;
        // 25: Y
        rom[200]=8'h66;
        rom[201]=8'h66;
        rom[202]=8'h3C;
        rom[203]=8'h18;
        rom[204]=8'h18;
        rom[205]=8'h18;
        rom[206]=8'h18;
        // 26: Z
        rom[208]=8'h7E;
        rom[209]=8'h06;
        rom[210]=8'h0C;
        rom[211]=8'h18;
        rom[212]=8'h30;
        rom[213]=8'h60;
        rom[214]=8'h7E;
        // 27: 0
        rom[216]=8'h3C;
        rom[217]=8'h66;
        rom[218]=8'h6E;
        rom[219]=8'h76;
        rom[220]=8'h66;
        rom[221]=8'h66;
        rom[222]=8'h3C;
        // 28: 1
        rom[224]=8'h18;
        rom[225]=8'h38;
        rom[226]=8'h18;
        rom[227]=8'h18;
        rom[228]=8'h18;
        rom[229]=8'h18;
        rom[230]=8'h7E;
        // 29: 2
        rom[232]=8'h3C;
        rom[233]=8'h66;
        rom[234]=8'h06;
        rom[235]=8'h0C;
        rom[236]=8'h30;
        rom[237]=8'h60;
        rom[238]=8'h7E;
        // 30: 3
        rom[240]=8'h3C;
        rom[241]=8'h66;
        rom[242]=8'h06;
        rom[243]=8'h1C;
        rom[244]=8'h06;
        rom[245]=8'h66;
        rom[246]=8'h3C;
        // 31: 4
        rom[248]=8'h0C;
        rom[249]=8'h1C;
        rom[250]=8'h3C;
        rom[251]=8'h6C;
        rom[252]=8'h7E;
        rom[253]=8'h0C;
        rom[254]=8'h0C;
        // 32: 5
        rom[256]=8'h7E;
        rom[257]=8'h60;
        rom[258]=8'h60;
        rom[259]=8'h7C;
        rom[260]=8'h06;
        rom[261]=8'h66;
        rom[262]=8'h3C;
        // 33: 6
        rom[264]=8'h1C;
        rom[265]=8'h30;
        rom[266]=8'h60;
        rom[267]=8'h7C;
        rom[268]=8'h66;
        rom[269]=8'h66;
        rom[270]=8'h3C;
        // 34: 7
        rom[272]=8'h7E;
        rom[273]=8'h06;
        rom[274]=8'h0C;
        rom[275]=8'h18;
        rom[276]=8'h30;
        rom[277]=8'h30;
        rom[278]=8'h30;
        // 35: 8
        rom[280]=8'h3C;
        rom[281]=8'h66;
        rom[282]=8'h66;
        rom[283]=8'h3C;
        rom[284]=8'h66;
        rom[285]=8'h66;
        rom[286]=8'h3C;
        // 36: 9
        rom[288]=8'h3C;
        rom[289]=8'h66;
        rom[290]=8'h66;
        rom[291]=8'h3E;
        rom[292]=8'h06;
        rom[293]=8'h0C;
        rom[294]=8'h38;
        // 37: x
        rom[298]=8'h66;
        rom[299]=8'h3C;
        rom[300]=8'h18;
        rom[301]=8'h3C;
        rom[302]=8'h66;
    end
    always @(posedge pixel_clk)
        font_bits <= rom[{glyph_code,glyph_row}];
endmodule
