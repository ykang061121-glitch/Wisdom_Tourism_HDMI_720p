// Asynchronous switches -> two synchronizers -> stable WHOLE vector ->
// blanking frame-boundary commit. No control travels back to the image/audio.
module presentation_control #(
    parameter integer STABLE_CYCLES = 250000
)(
    input wire video_clk,
    input wire reset,
    input wire frame_boundary,
    input wire [3:0] switches_async,
    output reg [3:0] switches_active,
    output wire [1:0] preset_mode,
    output reg signed [7:0] brightness,
    output reg [1:0] contrast,
    output wire subtitles_visible,
    output wire wave_visible
);
    localparam integer COUNT_BITS=STABLE_CYCLES<=1?1:$clog2(STABLE_CYCLES+1);
    reg [3:0] switch_sync0,switch_sync1,candidate;
    reg [COUNT_BITS-1:0] stable_count;
    assign preset_mode=switches_active[1:0];
    assign subtitles_visible=~switches_active[2];
    assign wave_visible=~switches_active[3];
    always @(posedge video_clk or posedge reset) begin
        if(reset) begin
            switch_sync0<=0;switch_sync1<=0;candidate<=0;
            stable_count<=0;switches_active<=0;brightness<=0;contrast<=1;
        end else begin
            switch_sync0<=switches_async;
            switch_sync1<=switch_sync0;
            if(switch_sync1!=candidate) begin
                candidate<=switch_sync1;stable_count<=0;
            end else begin
                if(stable_count<STABLE_CYCLES) stable_count<=stable_count+1'b1;
                if(frame_boundary && stable_count>=STABLE_CYCLES &&
                   candidate!=switches_active) begin
                    switches_active<=candidate;
                    case(candidate[1:0])
                        0:begin brightness<=0;contrast<=1;end // NORMAL
                        1:begin brightness<=-8'sd32;contrast<=0;end // SOFT
                        2:begin brightness<=8'sd16;contrast<=1;end // BRIGHT
                        default:begin brightness<=0;contrast<=2;end // VIVID
                    endcase
                end
            end
        end
    end
endmodule
