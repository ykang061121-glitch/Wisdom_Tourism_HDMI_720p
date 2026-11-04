module display_adjust_control #(
    parameter integer STABLE_CYCLES = 250000
)(
    input  wire              video_clk,
    input  wire              reset,
    input  wire [3:0]        switches_async,
    output reg signed [7:0]  brightness,
    output reg [1:0]         contrast,
    output reg [3:0]         switches_stable
);

reg [3:0] switch_sync0;
reg [3:0] switch_sync1;
reg [3:0] switch_candidate;
reg [31:0] stable_count;

// Each pin first receives a conventional two-register synchronizer.  The
// complete four-bit vector is then required to remain unchanged for the full
// stability interval before it is committed atomically.
always @(posedge video_clk or posedge reset) begin
    if (reset) begin
        switch_sync0    <= 4'b0110;
        switch_sync1    <= 4'b0110;
        switch_candidate<= 4'b0110;
        switches_stable <= 4'b0110;
        stable_count    <= 32'd0;
        brightness      <= 8'sd0;
        contrast        <= 2'b01;
    end else begin
        switch_sync0 <= switches_async;
        switch_sync1 <= switch_sync0;

        if (switch_sync1 != switch_candidate) begin
            switch_candidate <= switch_sync1;
            stable_count     <= 32'd0;
        end else if (switch_candidate != switches_stable) begin
            if (stable_count >= STABLE_CYCLES - 1) begin
                switches_stable <= switch_candidate;
                stable_count    <= 32'd0;

                case (switch_candidate[1:0])
                    2'b00: brightness <= -8'sd32;
                    2'b01: brightness <= -8'sd16;
                    2'b10: brightness <=  8'sd0;
                    default: brightness <= 8'sd16;
                endcase

                contrast <= switch_candidate[3:2];
            end else begin
                stable_count <= stable_count + 32'd1;
            end
        end else begin
            stable_count <= 32'd0;
        end
    end
end

endmodule
