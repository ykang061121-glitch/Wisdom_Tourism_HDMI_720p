// All state in SD/control clock domain. Normal single-key events are emitted
// on debounced release, so a later long chord cannot first change AUTO/period.
module adjustment_key_control #(
    parameter CLK_FREQ_HZ=100000000,
    parameter DEBOUNCE_MS=20,
    parameter CHORD_MS=1000
)(
    input wire clk,reset,
    input wire key3_n,key4_n,
    input wire [1:0] switches_async,
    output reg normal_key3,normal_key4,
    output reg adjust_mode,
    output reg signed [7:0] brightness,
    output reg [7:0] contrast,
    output reg [1:0] preset_mode,
    output wire target_contrast,fast_step
);
    localparam DB=(CLK_FREQ_HZ/1000)*DEBOUNCE_MS;
    localparam LONG=(CLK_FREQ_HZ/1000)*CHORD_MS;
    localparam DB_BITS=DB<=1?1:$clog2(DB+1);
    localparam LONG_BITS=LONG<=1?1:$clog2(LONG+1);
    reg [1:0] key_meta,key_sync,key_candidate,key_stable;
    reg [1:0] sw_meta,sw_sync,sw_candidate,sw_stable;
    reg [DB_BITS-1:0] key_count,sw_count;
    reg [LONG_BITS-1:0] chord_count;
    reg chord_seen,chord_consumed,pending3,pending4;
    wire increase=pending3 && key_stable[0];
    wire decrease=pending4 && key_stable[1];
    reg signed [10:0] adjusted,adjusted_contrast;
    reg signed [8:0] manual_brightness,manual_contrast;
    reg [1:0] preset_sw_seen;
    reg signed [10:0] composed_brightness,composed_contrast;
    function signed [7:0] preset_bri;
        input [1:0] mode;
        begin case(mode)1:preset_bri=-32;2:preset_bri=16;default:preset_bri=0;endcase end
    endfunction
    function [7:0] preset_con;
        input [1:0] mode;
        begin case(mode)1:preset_con=75;3:preset_con=125;default:preset_con=100;endcase end
    endfunction
    function signed [7:0] clamp_bri;
        input signed [10:0] value;
        begin clamp_bri=value>64?8'sd64:value< -64?-8'sd64:value[7:0];end
    endfunction
    function [7:0] clamp_con;
        input signed [10:0] value;
        begin clamp_con=value>200?8'd200:value<50?8'd50:value[7:0];end
    endfunction
    assign target_contrast=sw_stable[0];
    assign fast_step=sw_stable[1];
    always @*begin
        adjusted=$signed(brightness);
        adjusted_contrast=$signed({3'b0,contrast});
        composed_brightness=$signed(preset_bri(sw_stable))+$signed(manual_brightness);
        composed_contrast=$signed({3'b0,preset_con(sw_stable)})+$signed(manual_contrast);
        if(increase)begin
            adjusted=$signed(brightness)+(fast_step?11'sd16:11'sd1);
            adjusted_contrast=$signed({3'b0,contrast})+(fast_step?11'sd25:11'sd5);
        end else if(decrease)begin
            adjusted=$signed(brightness)-(fast_step?11'sd16:11'sd1);
            adjusted_contrast=$signed({3'b0,contrast})-(fast_step?11'sd25:11'sd5);
        end
    end
    always @(posedge clk or posedge reset)begin
        if(reset)begin
            key_meta<=3;key_sync<=3;key_candidate<=3;key_stable<=3;key_count<=0;
            sw_meta<=0;sw_sync<=0;sw_candidate<=0;sw_stable<=0;sw_count<=0;
        end else begin
            key_meta<={key4_n,key3_n};key_sync<=key_meta;
            sw_meta<=switches_async;sw_sync<=sw_meta;
            if(key_candidate!=key_sync)begin key_candidate<=key_sync;key_count<=0;end
            else if(key_count<DB)key_count<=key_count+1'b1;
            else key_stable<=key_candidate;
            if(sw_candidate!=sw_sync)begin sw_candidate<=sw_sync;sw_count<=0;end
            else if(sw_count<DB)sw_count<=sw_count+1'b1;
            else sw_stable<=sw_candidate;
        end
    end
    always @(posedge clk or posedge reset)begin
        if(reset)begin
            normal_key3<=0;normal_key4<=0;adjust_mode<=0;brightness<=0;contrast<=100;
            manual_brightness<=0;manual_contrast<=0;preset_mode<=0;preset_sw_seen<=0;
            chord_seen<=0;chord_consumed<=0;chord_count<=0;pending3<=0;pending4<=0;
        end else begin
            normal_key3<=0;normal_key4<=0;
            if(key_stable==0 || chord_seen)begin
                pending3<=0;pending4<=0;chord_seen<=1;
                // ADJ switch positions are not a preset request on exit.
                preset_sw_seen<=sw_stable;
                if(key_stable==0 && !chord_consumed)begin
                    if(chord_count==LONG-1)begin
                        adjust_mode<=~adjust_mode;chord_consumed<=1;
                    end else chord_count<=chord_count+1'b1;
                end else if(!chord_consumed)chord_count<=0;
                if(key_stable==3)begin
                    chord_seen<=0;chord_consumed<=0;chord_count<=0;
                end
            end else begin
                chord_count<=0;
                if(!key_stable[0])pending3<=1;
                else if(pending3)begin
                    pending3<=0;
                    if(!adjust_mode)normal_key3<=1;
                end
                if(!key_stable[1])pending4<=1;
                else if(pending4)begin
                    pending4<=0;
                    if(!adjust_mode)normal_key4<=1;
                end
                if(adjust_mode && (increase||decrease))begin
                    if(target_contrast)begin
                        if(adjusted_contrast>=50 && adjusted_contrast<=200)begin
                            contrast<=adjusted_contrast[7:0];
                            // Invariant: manual_contrast == contrast - preset_con(preset_mode).
                            // The preset is held during ADJ; apply the SAME accepted step
                            // to both stored values, avoiding a second serial subtraction.
                            manual_contrast <= manual_contrast +
                                (increase ? (fast_step ? 9'sd25 : 9'sd5) :
                                            (fast_step ? -9'sd25 : -9'sd5));
                        end
                    end else if(adjusted>= -64 && adjusted<=64)begin
                        brightness<=adjusted[7:0];
                        manual_brightness<=adjusted-$signed(preset_bri(preset_mode));
                    end
                end
                // Only a NEW stable switch gesture in NORMAL selects a base.
                // Offsets are additive (contrast in percentage points). Explicit
                // preset changes are clipped/rebased; ADJ steps reject overflow.
                if(!adjust_mode && key_stable==3 && sw_stable!=preset_sw_seen)begin
                    preset_sw_seen<=sw_stable;preset_mode<=sw_stable;
                    brightness<=clamp_bri(composed_brightness);
                    contrast<=clamp_con(composed_contrast);
                    manual_brightness<=$signed(clamp_bri(composed_brightness))-$signed(preset_bri(sw_stable));
                    manual_contrast<=$signed({1'b0,clamp_con(composed_contrast)})-$signed({1'b0,preset_con(sw_stable)});
                end
            end
        end
    end
endmodule
