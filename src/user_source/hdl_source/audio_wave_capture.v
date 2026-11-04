// Observe the SAME video-clock PCM interface consumed by the HDMI core.
// I2S_receiver already performs serial CDC; no multi-bit audio CDC is added.
module audio_wave_capture #(
    parameter integer STARTUP_SAMPLES = 2
)(
    input wire pixel_clk,
    input wire reset,
    input wire audio_valid,
    input wire signed [23:0] audio_left,
    input wire frame_boundary,
    input wire video_de,
    input wire [7:0] read_index,
    output reg signed [7:0] read_amplitude,
    output reg read_valid,
    output reg snapshot_valid,
    output reg snapshot_commit
);
    // Two 256-sample banks share a synchronous simple-dual-port RAM.
    // RAM contents need not be reset: validity and bank ownership are reset.
    reg [7:0] sample_ram [0:511];
    reg write_bank;
    reg display_bank;
    reg [7:0] write_index;
    reg pending;
    reg [1:0] warmup_samples;
    reg samples_seen;
    reg silent_frame;
    wire signed [7:0] quantized = audio_left[23:16];
    wire signed [7:0] clipped = (quantized > 8'sd45) ? 8'sd45 :
                               (quantized < -8'sd45) ? -8'sd45 : quantized;

    // Held pending banks are immutable. While waiting for a frame boundary,
    // incoming samples are ignored; the next window starts AFTER consumption.
    always @(posedge pixel_clk) begin
        if (!reset && warmup_samples == STARTUP_SAMPLES &&
            !pending && audio_valid)
            sample_ram[{write_bank,write_index}] <= clipped;
        read_amplitude <= sample_ram[{display_bank,read_index}];
    end

    always @(posedge pixel_clk or posedge reset) begin
        if (reset) begin
            write_bank <= 1'b0;
            display_bank <= 1'b1;
            write_index <= 8'd0;
            pending <= 1'b0;
            warmup_samples <= 2'd0;
            samples_seen <= 1'b0;
            silent_frame <= 1'b0;
            read_valid <= 1'b0;
            snapshot_valid <= 1'b0;
            snapshot_commit <= 1'b0;
        end else begin
            read_valid <= snapshot_valid;
            snapshot_commit <= 1'b0;
            if (audio_valid) samples_seen <= 1'b1;
            // Skip two complete received stereo frames after reset/unlock.
            // The legacy receiver does not reset its serial shift registers.
            if (warmup_samples != STARTUP_SAMPLES) begin
                if (audio_valid) warmup_samples <= warmup_samples + 2'd1;
            end else if (!pending && audio_valid) begin
                write_index <= write_index + 8'd1;
                if (write_index == 8'd255) pending <= 1'b1;
            end
            // Even an erroneously active-video boundary cannot publish a bank.
            if (pending && frame_boundary && !video_de) begin
                display_bank <= write_bank;
                write_bank <= ~write_bank;
                write_index <= 8'd0;
                pending <= 1'b0;
                snapshot_valid <= 1'b1;
                snapshot_commit <= 1'b1;
            end
            // Missing PCM is different from valid PCM with value zero.
            // Invalidate old music after TWO complete boundary intervals with
            // no valid sample; a stopped source cannot leave a frozen waveform.
            if (frame_boundary && !video_de) begin
                samples_seen <= 1'b0;
                if (samples_seen || audio_valid) silent_frame <= 1'b0;
                else begin
                    silent_frame <= 1'b1;
                    if (silent_frame) begin
                        snapshot_valid <= 1'b0;
                        read_valid <= 1'b0;
                        snapshot_commit <= 1'b0;
                        pending <= 1'b0;
                        write_index <= 8'd0;
                        warmup_samples <= 2'd0;
                    end
                end
            end
        end
    end
endmodule
