`include "image_melody_rom.v"
// Existing 32-bit square-wave DDS, signed 24-bit PCM format.
// sample_tick is one stereo frame; clocks/valid never stop during mute.
module image_melody_pcm #(
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
    output reg song_start,
    output reg [9:0] pcm_status
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
    image_melody_rom #(.BASE_NOTE_SAMPLES(BASE_NOTE_SAMPLES)) notes (
        .image_index(active_image), .note_index(note_index),
        .phase_increment(phase_increment), .note_samples(note_samples),.pitch_code());
    // Observe the PRE-edge state used to produce pcm_sample, not the newly
    // advanced note index. Serializer latches this bundle with that sample.
    // [9] valid, [8:7] image, [6:4] note, [3:1] phase, [0] nonzero envelope.
    wire sample_identity_valid=active_valid &&
        (state==ATTACK || state==PLAY || (state==RELEASE && envelope!=0));
    always @(posedge clk or posedge reset) begin
        if(reset)pcm_status<=0;
        else if(sample_tick)pcm_status<={sample_identity_valid,active_image,note_index,state,
                                       (sample_identity_valid && envelope!=0)};
    end
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
