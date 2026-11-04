`include "image_melody_pcm.v"
// Board-tested wire framing: 64 BCLK/channel, 128/stereo,
// BCLK=MCLK/2, Fs=MCLK/256. PCM has one frame of serializer latency.
module image_melody_i2s #(
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
    output wire song_start,
    output reg [9:0] playback_status
);
    reg [5:0] bit_count;
    reg [63:0] shift_reg;
    reg [23:0] stereo_sample;
    wire signed [23:0] pcm_sample;
    wire [9:0] pcm_status;
    wire sample_tick=O_i2s_BCLK && bit_count==63 && O_i2s_LRCK;
    image_melody_pcm #(.BASE_NOTE_SAMPLES(BASE_NOTE_SAMPLES),
        .RAMP_HOLD_SAMPLES(RAMP_HOLD_SAMPLES), .SILENCE_SAMPLES(SILENCE_SAMPLES)) pcm (
        .clk(I_mclk), .reset(I_rst), .sample_tick(sample_tick),
        .selection_update(selection_update), .selection_valid(selection_valid),
        .selection_image(selection_image), .pcm_sample(pcm_sample),
        .active_valid(active_valid), .active_image(active_image),
        .note_index(), .envelope(), .song_start(song_start),.pcm_status(pcm_status));
    always @(posedge I_mclk or posedge I_rst) begin
        if (I_rst) begin
            O_i2s_BCLK<=0; O_i2s_LRCK<=0; O_i2s_DOUT<=0;
            bit_count<=0; shift_reg<=0; stereo_sample<=0;playback_status<=0;
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
                        playback_status<=pcm_status;
                        shift_reg<={pcm_sample,40'd0};
                    end
                end else bit_count<=bit_count+6'd1;
            end
        end
    end
endmodule
