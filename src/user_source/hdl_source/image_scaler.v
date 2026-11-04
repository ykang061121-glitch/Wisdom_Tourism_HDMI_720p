// One selected source-row RAM, no frame store or runtime divide.
module image_scaler #(
    parameter integer OUT_WIDTH=640, OUT_HEIGHT=480,
    parameter integer COORD_BITS=(OUT_WIDTH>1023 ? 11 : 10),
    parameter integer LINE_MAX=(OUT_WIDTH==1280 ? 1280 : 800)
)(
    input wire clk, reset, cancel, start,
    input wire [COORD_BITS-1:0] source_width, source_height,
    input wire [23:0] in_rgb,
    input wire in_valid,
    output wire in_ready,
    output reg [23:0] out_rgb,
    output wire out_valid,
    input wire out_ready,
    output reg [COORD_BITS-1:0] out_x, out_row,
    output reg scale_done,
    output wire busy
);
    localparam IDLE=0, RECEIVE=1, READ_RAM=2, PRESENT=3;
    reg [1:0] state;
    reg [23:0] line_ram [0:LINE_MAX-1];
    reg [10:0] width_latch, height_latch, last_input_x;
    reg [10:0] input_x, input_row, sample_x, sample_row;
    reg [10:0] content_width, margin_left, content_end;
    reg [11:0] phase_x, phase_y;
    wire [11:0] next_phase_x=phase_x+{1'b0,width_latch};
    wire [11:0] next_phase_y=phase_y+{1'b0,height_latch};
    wire [10:0] following_row=sample_row+
        ((next_phase_y>=2*OUT_HEIGHT) ? 2 : (next_phase_y>=OUT_HEIGHT) ? 1 : 0);
    wire content_pixel=(out_x>=margin_left && out_x<content_end);
    reg [23:0] row_read_data;
    assign in_ready=(state==RECEIVE) && !cancel;
    assign out_valid=(state==PRESENT) && !cancel;
    assign busy=(state!=IDLE);
    // Synchronous RAM read, no RAM/output reset.
    always @(posedge clk) begin
        if(in_valid && in_ready && input_row==sample_row) line_ram[input_x]<=in_rgb;
        if(state==READ_RAM)row_read_data<=line_ram[sample_x];
    end
    // Keep the synchronous RAM output template free of a zero-data mux:
    // TD otherwise maps this row RAM to large distributed logic. Coordinates
    // are held throughout PRESENT/backpressure, so this adds no latency.
    always @* out_rgb=content_pixel ? row_read_data : 24'd0;
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            state<=IDLE;width_latch<=0;height_latch<=0;last_input_x<=0;
            input_x<=0;input_row<=0;sample_x<=0;sample_row<=0;
            phase_x<=0;phase_y<=0;out_x<=0;out_row<=0;scale_done<=0;
            content_width<=OUT_WIDTH;margin_left<=0;content_end<=OUT_WIDTH;
        end else begin
            scale_done<=0;
            if(cancel)state<=IDLE;
            else if(start)begin
                width_latch<=source_width;height_latch<=source_height;
                last_input_x<=source_width-1'b1;
                input_x<=0;input_row<=0;sample_x<=0;sample_row<=0;
                phase_x<={1'b0,source_width}>>1;
                // Bottom-up reversal: ceil(center)-1 instead of floor(center).
                // Exact integer ties matter for 640->960 and 480->720.
                phase_y<=(OUT_WIDTH==1280 ? ({1'b0,source_height}-1'b1) : {1'b0,source_height})>>1;
                if(OUT_WIDTH==1280 && source_width!=1280)begin
                    content_width<=960;margin_left<=160;content_end<=1120;
                end else begin
                    content_width<=OUT_WIDTH;margin_left<=0;content_end<=OUT_WIDTH;
                end
                out_x<=0;out_row<=0;state<=RECEIVE;
            end else case(state)
                RECEIVE:if(in_valid)begin
                    if(input_x==last_input_x)begin
                        input_x<=0;input_row<=input_row+1'b1;
                        if(input_row==sample_row)state<=READ_RAM;
                    end else input_x<=input_x+1'b1;
                end
                READ_RAM:state<=PRESENT;
                PRESENT:if(out_ready)begin
                    if(out_x==OUT_WIDTH-1)begin
                        out_x<=0;sample_x<=0;phase_x<={1'b0,width_latch}>>1;
                        if(out_row==OUT_HEIGHT-1)begin state<=IDLE;scale_done<=1;end
                        else begin
                            out_row<=out_row+1'b1;sample_row<=following_row;
                            if(next_phase_y>=2*OUT_HEIGHT)phase_y<=next_phase_y-2*OUT_HEIGHT;
                            else if(next_phase_y>=OUT_HEIGHT)phase_y<=next_phase_y-OUT_HEIGHT;
                            else phase_y<=next_phase_y;
                            state<=(following_row==sample_row)?READ_RAM:RECEIVE;
                        end
                    end else begin
                        out_x<=out_x+1'b1;
                        if(content_pixel && out_x!=content_end-1'b1)begin
                            if(next_phase_x>=2*content_width)begin
                                phase_x<=next_phase_x-2*content_width;sample_x<=sample_x+2;
                            end else if(next_phase_x>=content_width)begin
                                phase_x<=next_phase_x-content_width;sample_x<=sample_x+1'b1;
                            end else phase_x<=next_phase_x;
                        end
                        state<=READ_RAM;
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
