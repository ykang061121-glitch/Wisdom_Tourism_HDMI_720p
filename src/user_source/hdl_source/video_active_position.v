module video_active_position #(parameter COORD_BITS=10)(
    input  wire       pixel_clk,
    input  wire       reset,
    input  wire       vs,
    input  wire       de,
    output reg [COORD_BITS-1:0] x,
    output reg [COORD_BITS-1:0] y
);

reg de_d;
reg vs_d;

// x/y describe the pixel present on de in the current cycle.  y advances at
// the end of each active line, so the first active pixel of the next line sees
// the new line number without adding another pixel pipeline stage.
always @(posedge pixel_clk or posedge reset) begin
    if (reset) begin
        de_d <= 1'b0;
        vs_d <= 1'b0;
        x    <= 11'd0;
        y    <= 11'd0;
    end else begin
        de_d <= de;
        vs_d <= vs;

        if (vs != vs_d)
            y <= 11'd0;
        else if (de_d && !de)
            y <= y + 11'd1;

        if (de)
            x <= x + 11'd1;
        else
            x <= 11'd0;
    end
end

endmodule
