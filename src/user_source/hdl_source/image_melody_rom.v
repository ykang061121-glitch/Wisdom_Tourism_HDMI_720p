// Four original eight-note motifs. Index 0..3 binds to displayed IMG 01..04.
// Small constant tables, no sample ROM or run-time multiply/divide.
module image_melody_rom #(
    parameter integer BASE_NOTE_SAMPLES = 12000
) (
    input wire [1:0] image_index,
    input wire [2:0] note_index,
    output reg [31:0] phase_increment,
    output reg [15:0] note_samples,
    output wire [3:0] pitch_code
);
    reg [3:0] pitch;
    assign pitch_code=pitch; // read-only: shared source for music visualization
    always @* begin
        case ({image_index,note_index})
            // Bright ascending midrange: C4 D4 E4 G4 E4 D4 G4 C5.
            5'd0: pitch=5; 5'd1: pitch=6; 5'd2: pitch=7; 5'd3: pitch=8;
            5'd4: pitch=7; 5'd5: pitch=6; 5'd6: pitch=8; 5'd7: pitch=11;
            // Slow bass: C3 G3 E3 D3 C3 E3 G3 C4.
            5'd8: pitch=1; 5'd9: pitch=4; 5'd10: pitch=3; 5'd11: pitch=2;
            5'd12: pitch=1; 5'd13: pitch=3; 5'd14: pitch=4; 5'd15: pitch=5;
            // Fast arpeggio: C4 E4 G4 C5 G4 E4 G4 C5.
            5'd16: pitch=5; 5'd17: pitch=7; 5'd18: pitch=8; 5'd19: pitch=11;
            5'd20: pitch=8; 5'd21: pitch=7; 5'd22: pitch=8; 5'd23: pitch=11;
            // High dotted motif: A4 C5 E5 D5 B4 G4 C5 A4.
            5'd24: pitch=9; 5'd25: pitch=11; 5'd26: pitch=13; 5'd27: pitch=12;
            5'd28: pitch=10; 5'd29: pitch=8; 5'd30: pitch=11; default: pitch=9;
        endcase
        case (pitch)
            1: phase_increment=32'd11704931; // C3
            2: phase_increment=32'd13138341; // D3
            3: phase_increment=32'd14747289; // E3
            4: phase_increment=32'd17537578; // G3
            5: phase_increment=32'd23409862; // C4
            6: phase_increment=32'd26276681; // D4
            7: phase_increment=32'd29494578; // E4
            8: phase_increment=32'd35075155; // G4
            9: phase_increment=32'd39370534; // A4
            10: phase_increment=32'd44191930; // B4
            11: phase_increment=32'd46819716; // C5
            12: phase_increment=32'd52553362; // D5
            default: phase_increment=32'd58989156; // E5
        endcase
        case (image_index)
            0: note_samples=BASE_NOTE_SAMPLES;
            1: note_samples=BASE_NOTE_SAMPLES*2;
            2: note_samples=BASE_NOTE_SAMPLES/2;
            default: note_samples=(note_index==2 || note_index==7) ?
                        BASE_NOTE_SAMPLES+BASE_NOTE_SAMPLES/2 : BASE_NOTE_SAMPLES;
        endcase
    end
endmodule
