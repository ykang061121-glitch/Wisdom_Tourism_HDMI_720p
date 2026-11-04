module audio_wave_overlay #(
    parameter [23:0] PANEL_RGB = 24'h18202A,
    parameter [23:0] BORDER_RGB = 24'h608090,
    parameter [23:0] ZERO_RGB = 24'h405060,
    parameter [23:0] WAVE_RGB = 24'h00FF80
)(
    input wire pixel_clk,
    input wire reset,
    input wire hs,
    input wire vs,
    input wire de,
    input wire [9:0] x,
    input wire [9:0] y,
    input wire [23:0] background_rgb,
    input wire signed [7:0] sample_amplitude,
    input wire sample_valid,
    output wire [7:0] sample_index,
    output reg out_hs,
    output reg out_vs,
    output reg out_de,
    output reg [9:0] out_x,
    output reg [9:0] out_y,
    output reg [23:0] wave_rgb
);
    reg [23:0] background_d;
    // 512 columns / 256 samples = two columns per sample. Side margins
    // surround the plot in a 608x126 panel, with no runtime division.
    assign sample_index = (x >= 10'd64 && x < 10'd576) ?
                         ((x - 10'd64) >> 1) : 8'd0;
    wire signed [10:0] amplitude_ext = {{3{sample_amplitude[7]}},sample_amplitude};
    wire signed [10:0] sample_y = 11'sd392 - amplitude_ext;
    wire signed [10:0] pixel_y = {1'b0,out_y};

    // Match the capture RAM's ONE synchronous read cycle. ALL pixel metadata
    // and background are delayed together. No timing widths or rates change.
    always @(posedge pixel_clk or posedge reset) begin
        if (reset) begin
            out_hs <= 1'b0; out_vs <= 1'b0; out_de <= 1'b0;
            out_x <= 10'd0; out_y <= 10'd0; background_d <= 24'd0;
        end else begin
            out_hs <= hs; out_vs <= vs; out_de <= de;
            out_x <= x; out_y <= y; background_d <= background_rgb;
        end
    end

    always @* begin
        wave_rgb = background_d;
        if (reset || !out_de) wave_rgb = 24'd0;
        else if (out_x >= 10'd16 && out_x <= 10'd623 &&
                 out_y >= 10'd330 && out_y <= 10'd455) begin
            wave_rgb = PANEL_RGB;
            if (out_x == 10'd16 || out_x == 10'd623 ||
                out_y == 10'd330 || out_y == 10'd455)
                wave_rgb = BORDER_RGB;
            else begin
                if (out_y == 10'd392) wave_rgb = ZERO_RGB;
                if (sample_valid && out_x >= 10'd64 && out_x < 10'd576 &&
                    pixel_y >= sample_y - 11'sd1 && pixel_y <= sample_y + 11'sd1)
                    wave_rgb = WAVE_RGB;
            end
        end
    end
endmodule
