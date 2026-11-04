// Generic row decoder. Public format/size eligibility is checked by bmp_read.
// Small fixtures can exercise all padding values without enabling extra sizes.
module bmp_pixel_decoder #(parameter COORD_BITS=10)(
    input wire clk, reset, cancel, start,
    input wire [COORD_BITS-1:0] width, height,
    input wire [31:0] pixel_offset,
    input wire [7:0] byte_data,
    input wire byte_valid,
    output wire byte_ready,
    output reg [23:0] pixel_data,
    output wire pixel_valid,
    input wire pixel_ready,
    output wire row_last,
    output reg source_done,
    output wire busy
);
    localparam IDLE=0, SKIP=1, BGR=2, HOLD=3, PAD=4;
    reg [2:0] state;
    reg [31:0] skip_left;
    reg [10:0] x, row, width_latch, last_x, last_row;
    reg row_is_last;
    reg [1:0] component, pad_left;
    assign byte_ready=(state==SKIP || state==BGR || state==PAD) && !cancel;
    assign pixel_valid=(state==HOLD) && !cancel;
    assign row_last=(x==last_x);
    assign busy=(state!=IDLE);
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            state<=IDLE; skip_left<=0; x<=0; row<=0; width_latch<=0;
            last_x<=11'h7ff; last_row<=11'h7ff; row_is_last<=0;
            component<=0; pad_left<=0; pixel_data<=0; source_done<=0;
        end else begin
            source_done<=0;
            // A row changes only AFTER its last accepted HOLD/PAD cycle.
            // The following row needs three accepted BGR bytes before HOLD,
            // so this one-cycle comparison is settled before it is consumed.
            // This cuts height/subtract/compare out of the end-of-row FSM.
            row_is_last <= (row==last_row);
            if(cancel) state<=IDLE;
            else if(start) begin
                width_latch<=width; last_x<=width-11'd1;
                last_row<=height-11'd1; row_is_last<=(height==11'd1);
                x<=0; row<=0;
                component<=0; skip_left<=pixel_offset;
                state<=(pixel_offset==0) ? BGR : SKIP;
            end else case(state)
                SKIP: if(byte_valid) begin
                    skip_left<=skip_left-1'b1;
                    if(skip_left==1) state<=BGR;
                end
                BGR: if(byte_valid) begin
                    case(component)
                        0: pixel_data[7:0]<=byte_data;
                        1: pixel_data[15:8]<=byte_data;
                        2: pixel_data[23:16]<=byte_data;
                    endcase
                    if(component==2) begin component<=0; state<=HOLD; end
                    else component<=component+1'b1;
                end
                HOLD: if(pixel_ready) begin
                    if(row_last) begin
                        // For RGB24, padding=(-3*width) mod 4 = width mod 4.
                        if(width_latch[1:0]!=0) begin
                            pad_left<=width_latch[1:0]; state<=PAD;
                        end else if(row_is_last) begin
                            state<=IDLE; source_done<=1;
                        end else begin x<=0; row<=row+1'b1; state<=BGR; end
                    end else begin x<=x+1'b1; state<=BGR; end
                end
                PAD: if(byte_valid) begin
                    pad_left<=pad_left-1'b1;
                    if(pad_left==1) begin
                        if(row_is_last) begin state<=IDLE; source_done<=1; end
                        else begin x<=0; row<=row+1'b1; state<=BGR; end
                    end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
