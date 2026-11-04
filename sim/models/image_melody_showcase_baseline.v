// Four original eight-note motifs. Index 0..3 binds to displayed IMG 01..04.
// Small constant tables, no sample ROM or run-time multiply/divide.
module image_melody_rom_showcase_baseline #(
    parameter integer BASE_NOTE_SAMPLES = 12000
) (
    input wire [1:0] image_index,
    input wire [2:0] note_index,
    output reg [31:0] phase_increment,
    output reg [15:0] note_samples
);
    reg [3:0] pitch;
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


// Existing 32-bit square-wave DDS, signed 24-bit PCM format.
// sample_tick is one stereo frame; clocks/valid never stop during mute.
module image_melody_pcm_showcase_baseline #(
    parameter integer BASE_NOTE_SAMPLES = 12000,
    parameter integer RAMP_HOLD_SAMPLES = 32,
    parameter integer SILENCE_SAMPLES = 64,
    parameter signed [23:0] AMP = 24'sd2000000
) (
    input wire clk, reset, sample_tick,
    input wire selection_update, selection_valid,
    input wire [1:0] selection_image,
    output reg signed [23:0] pcm_sample,
    output reg active_valid,
    output reg [1:0] active_image,
    output reg [2:0] note_index,
    output reg [23:0] envelope,
    output reg song_start
);
    localparam IDLE=0, ATTACK=1, PLAY=2, RELEASE=3, SILENCE=4;
    localparam [23:0] AMP_STEP=(AMP>>5);
    localparam integer RAMP_BITS=(RAMP_HOLD_SAMPLES<=1)?1:$clog2(RAMP_HOLD_SAMPLES);
    localparam integer SILENCE_BITS=(SILENCE_SAMPLES<=1)?1:$clog2(SILENCE_SAMPLES);
    reg [2:0] state;
    reg target_valid;
    reg [1:0] target_image;
    reg [31:0] phase_acc;
    reg [15:0] note_count;
    reg [RAMP_BITS-1:0] ramp_count;
    reg [SILENCE_BITS-1:0] silence_count;
    wire [31:0] phase_increment;
    wire [15:0] note_samples;
    wire retarget=!target_valid || target_image!=active_image;
    image_melody_rom_showcase_baseline #(.BASE_NOTE_SAMPLES(BASE_NOTE_SAMPLES)) notes (
        .image_index(active_image), .note_index(note_index),
        .phase_increment(phase_increment), .note_samples(note_samples));
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state<=IDLE; target_valid<=0; target_image<=0;
            active_valid<=0; active_image<=0; note_index<=0; note_count<=0;
            phase_acc<=0; pcm_sample<=0; envelope<=0;
            ramp_count<=0; silence_count<=0; song_start<=0;
        end else begin
            song_start<=0;
            // Latest committed picture wins during a ramp; same index
            // cannot restart its melody.
            if (selection_update) begin
                target_valid<=selection_valid;
                target_image<=selection_image;
            end
            if (sample_tick) begin
                pcm_sample<=active_valid ? (phase_acc[31] ?
                              $signed(envelope) : -$signed(envelope)) : 24'sd0;
                if (active_valid) begin
                    phase_acc<=phase_acc+phase_increment;
                    if (note_count==note_samples-1) begin
                        note_count<=0; note_index<=note_index+3'd1;
                    end else note_count<=note_count+16'd1;
                end
                case (state)
                    IDLE: begin
                        pcm_sample<=0; envelope<=0; active_valid<=0;
                        if (target_valid) begin
                            active_image<=target_image; active_valid<=1;
                            note_index<=0; note_count<=0; phase_acc<=0;
                            ramp_count<=0; song_start<=1; state<=ATTACK;
                        end
                    end
                    ATTACK: begin
                        if (retarget) begin state<=RELEASE; ramp_count<=0; end
                        else if (ramp_count==RAMP_HOLD_SAMPLES-1) begin
                            ramp_count<=0;
                            if (envelope>=AMP-AMP_STEP) begin
                                envelope<=AMP; state<=PLAY;
                            end else envelope<=envelope+AMP_STEP;
                        end else ramp_count<=ramp_count+1'b1;
                    end
                    PLAY: if (retarget) begin state<=RELEASE; ramp_count<=0; end
                    RELEASE: begin
                        if (envelope==0) begin
                            pcm_sample<=0; active_valid<=0;
                            silence_count<=0; state<=SILENCE;
                        end else if (ramp_count==RAMP_HOLD_SAMPLES-1) begin
                            ramp_count<=0;
                            envelope<=(envelope<=AMP_STEP)?24'd0:envelope-AMP_STEP;
                        end else ramp_count<=ramp_count+1'b1;
                    end
                    SILENCE: begin
                        pcm_sample<=0; envelope<=0; active_valid<=0;
                        if (silence_count==SILENCE_SAMPLES-1) begin
                            silence_count<=0;
                            if (target_valid) begin
                                active_image<=target_image; active_valid<=1;
                                note_index<=0; note_count<=0; phase_acc<=0;
                                ramp_count<=0; song_start<=1; state<=ATTACK;
                            end else state<=IDLE;
                        end else silence_count<=silence_count+1'b1;
                    end
                    default: begin
                        state<=IDLE; pcm_sample<=0; envelope<=0; active_valid<=0;
                    end
                endcase
            end
        end
    end
endmodule


// Board-tested wire framing: 64 BCLK/channel, 128/stereo,
// BCLK=MCLK/2, Fs=MCLK/256. PCM has one frame of serializer latency.
module image_melody_i2s_showcase_baseline #(
    parameter integer BASE_NOTE_SAMPLES = 12000,
    parameter integer RAMP_HOLD_SAMPLES = 32,
    parameter integer SILENCE_SAMPLES = 64
) (
    input wire I_mclk, I_rst,
    input wire selection_update, selection_valid,
    input wire [1:0] selection_image,
    output reg O_i2s_BCLK, O_i2s_LRCK, O_i2s_DOUT,
    output wire active_valid,
    output wire [1:0] active_image,
    output wire song_start
);
    reg [5:0] bit_count;
    reg [63:0] shift_reg;
    reg [23:0] stereo_sample;
    wire signed [23:0] pcm_sample;
    wire sample_tick=O_i2s_BCLK && bit_count==63 && O_i2s_LRCK;
    image_melody_pcm_showcase_baseline #(.BASE_NOTE_SAMPLES(BASE_NOTE_SAMPLES),
        .RAMP_HOLD_SAMPLES(RAMP_HOLD_SAMPLES), .SILENCE_SAMPLES(SILENCE_SAMPLES)) pcm (
        .clk(I_mclk), .reset(I_rst), .sample_tick(sample_tick),
        .selection_update(selection_update), .selection_valid(selection_valid),
        .selection_image(selection_image), .pcm_sample(pcm_sample),
        .active_valid(active_valid), .active_image(active_image),
        .note_index(), .envelope(), .song_start(song_start));
    always @(posedge I_mclk or posedge I_rst) begin
        if (I_rst) begin
            O_i2s_BCLK<=0; O_i2s_LRCK<=0; O_i2s_DOUT<=0;
            bit_count<=0; shift_reg<=0; stereo_sample<=0;
        end else begin
            O_i2s_BCLK<=~O_i2s_BCLK;
            if (O_i2s_BCLK) begin
                O_i2s_DOUT<=shift_reg[63];
                shift_reg<={shift_reg[62:0],1'b0};
                if (bit_count==63) begin
                    bit_count<=0;
                    if (!O_i2s_LRCK) begin
                        O_i2s_LRCK<=1;
                        shift_reg<={stereo_sample,40'd0};
                    end else begin
                        O_i2s_LRCK<=0;
                        stereo_sample<=pcm_sample;
                        shift_reg<={pcm_sample,40'd0};
                    end
                end else bit_count<=bit_count+6'd1;
            end
        end
    end
endmodule



