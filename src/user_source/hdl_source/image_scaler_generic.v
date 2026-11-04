// Bounded, centre-sampled nearest neighbour. MODE: 0 FIT, 1 FILL, 2 STRETCH.
// Source rows arrive bottom-up. out_row is also bottom-up for the existing
// writer's vertical reversal. A selected row stays immutable until replay ends.
module image_scaler_generic #(
    parameter OUT_WIDTH=1280, OUT_HEIGHT=720, MODE=0,
    parameter LINE_MAX=1920
)(
    input wire clk, reset, cancel, start,
    input wire [10:0] source_width, source_height,
    input wire [23:0] in_rgb,
    input wire in_valid,
    output wire in_ready,
    output wire [23:0] out_rgb,
    output wire out_valid,
    input wire out_ready,
    output reg [10:0] out_x, out_row,
    output reg scale_done,
    output wire [10:0] content_width,content_height,
    output wire busy
);
    localparam IDLE=0, AREA=1, FIT_START=2, FIT_WAIT=3, CONFIG=4,
               X_START=5, X_WAIT=6, Y_START=7, Y_WAIT=8, SELECT=9,
               LOAD=10, READ=11, PRESENT=12, DRAIN=13;
    reg [3:0] state;
    reg [10:0] sw,sh,cw,ch,left,bottom;
    reg [10:0] right,upper,last_content_x,last_content_row;
    reg content_q,inside_y_q,last_content_x_q,last_content_row_q;
    reg [10:0] ix,ir,sx,sr,sx_initial;
    reg [10:0] last_source_x,last_source_row;
    reg [21:0] wide_area,tall_area;
    reg [31:0] init_x,init_y;
    reg [12:0] dx,dy,nx,ny,px,py,px_initial;
    // Registered during setup, not an added multiplier in the pixel FSM.
    // FIT over 16..1920 has at most three source steps per output sample.
    reg [13:0] dx2,dx3,dy2,dy3;
    reg [23:0] line_ram[0:LINE_MAX-1];
    reg [23:0] ram_q;
    reg row_available;
    reg [10:0] cached_row;
    reg div_start;
    reg [31:0] dividend;
    reg [12:0] divisor;
    wire div_done;
    wire [31:0] quotient;
    wire [12:0] remainder;
    wire inside_x=(out_x>=left && out_x<right);
    wire inside_y=(out_row>=bottom && out_row<upper);
    wire content=inside_x && inside_y;
    wire [13:0] next_px={1'b0,px}+{1'b0,nx};
    wire [13:0] next_py={1'b0,py}+{1'b0,ny};
    wire [1:0] advance_x=(next_px>=dx3)?3:(next_px>=dx2)?2:
                                  (next_px>={1'b0,dx})?1:0;
    wire [1:0] advance_y=(next_py>=dy3)?3:(next_py>=dy2)?2:
                                  (next_py>={1'b0,dy})?1:0;
    assign in_ready=(state==LOAD || state==DRAIN) && !cancel;
    assign out_valid=state==PRESENT && !cancel;
    assign out_rgb=content_q?ram_q:24'd0;
    assign busy=state!=IDLE;
    assign content_width=cw;
    assign content_height=ch;
    scaler_setup_divider divider(.clk(clk),.reset(reset|cancel),.start(div_start),
        .dividend(dividend),.divisor(divisor),.done(div_done),
        .quotient(quotient),.remainder(remainder));
    // Keep zero/black selection OUTSIDE the synchronous RAM read template.
    always @(posedge clk) begin
        if(state==LOAD && in_valid && in_ready && ir==sr) line_ram[ix]<=in_rgb;
        if(state==READ) ram_q<=line_ram[sx];
    end
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            state<=IDLE;sw<=0;sh<=0;cw<=0;ch<=0;left<=0;bottom<=0;
            right<=0;upper<=0;last_content_x<=0;last_content_row<=0;
            content_q<=0;inside_y_q<=0;last_content_x_q<=0;last_content_row_q<=0;
            ix<=0;ir<=0;sx<=0;sr<=0;sx_initial<=0;
            last_source_x<=0;last_source_row<=0;
            wide_area<=0;tall_area<=0;init_x<=0;init_y<=0;
            dx<=1;dy<=1;nx<=0;ny<=0;px<=0;py<=0;px_initial<=0;
            dx2<=2;dx3<=3;dy2<=2;dy3<=3;
            row_available<=0;cached_row<=0;
            div_start<=0;dividend<=0;divisor<=1;
            out_x<=0;out_row<=0;scale_done<=0;
        end else begin
            scale_done<=0;div_start<=0;
            if(cancel) begin state<=IDLE;row_available<=0; end
            else if(start && state==IDLE) begin
                sw<=source_width;sh<=source_height;
                last_source_x<=source_width-1'b1;
                last_source_row<=source_height-1'b1;
                ix<=0;ir<=0;out_x<=0;out_row<=0;row_available<=0;
                state<=AREA;
            end else case(state)
                IDLE:;
                AREA:begin
                    // Explicit constant shift/add avoids TD inferring DSPs
                    // for these setup-only 1280/720 geometry products.
                    wide_area<=({11'd0,sw}<<9)+({11'd0,sw}<<7)+
                               ({11'd0,sw}<<6)+({11'd0,sw}<<4);
                    tall_area<=({11'd0,sh}<<10)+({11'd0,sh}<<8);
                    state<=FIT_START;
                end
                FIT_START:begin
                    cw<=OUT_WIDTH;ch<=OUT_HEIGHT;left<=0;bottom<=0;
                    if(MODE==0) begin
                        dividend<=(wide_area>=tall_area)?tall_area:wide_area;
                        divisor<=(wide_area>=tall_area)?sw:sh;
                        div_start<=1;state<=FIT_WAIT;
                    end else state<=CONFIG;
                end
                FIT_WAIT:if(div_done) begin
                    if(wide_area>=tall_area)begin
                        ch<=quotient[10:0];
                        // Top uses floor centering; bottom receives the spare
                        // pixel for odd margins after the writer's reversal.
                        bottom<=OUT_HEIGHT-quotient[10:0]-((OUT_HEIGHT-quotient[10:0])>>1);
                    end else begin
                        cw<=quotient[10:0];left<=(OUT_WIDTH-quotient[10:0])>>1;
                    end
                    state<=CONFIG;
                end
                CONFIG:begin
                    right<=left+cw;upper<=bottom+ch;
                    last_content_x<=left+cw-1'b1;
                    last_content_row<=bottom+ch-1'b1;
                    init_x<=sw;init_y<=sh-1'b1;
                    dx<=cw<<1;dy<=ch<<1;nx<=sw<<1;ny<=sh<<1;
                    if(MODE==1 && wide_area>=tall_area)begin
                        init_x<=wide_area-tall_area+sh;
                        dx<=2*OUT_HEIGHT;nx<=sh<<1;
                    end else if(MODE==1)begin
                        init_y<=tall_area-wide_area+sw-1'b1;
                        dy<=2*OUT_WIDTH;ny<=sw<<1;
                    end
                    state<=X_START;
                end
                X_START:begin
                    dx2<={dx,1'b0};dx3<={dx,1'b0}+{1'b0,dx};
                    dividend<=init_x;divisor<=dx;div_start<=1;state<=X_WAIT;
                end
                X_WAIT:if(div_done)begin
                    sx<=quotient[10:0];sx_initial<=quotient[10:0];
                    px<=remainder;px_initial<=remainder;state<=Y_START;
                end
                Y_START:begin
                    dy2<={dy,1'b0};dy3<={dy,1'b0}+{1'b0,dy};
                    dividend<=init_y;divisor<=dy;div_start<=1;state<=Y_WAIT;
                end
                Y_WAIT:if(div_done)begin sr<=quotient[10:0];py<=remainder;state<=SELECT;end
                SELECT:begin
                    content_q<=content;inside_y_q<=inside_y;
                    last_content_x_q<=out_x==last_content_x;
                    last_content_row_q<=out_row==last_content_row;
                    if(!inside_y)state<=PRESENT;
                    else if(!row_available || cached_row!=sr)state<=LOAD;
                    else state<=content?READ:PRESENT;
                end
                LOAD:if(in_valid && in_ready)begin
                    if(ix==last_source_x)begin
                        ix<=0;ir<=ir+1'b1;
                        if(ir==sr)begin
                            row_available<=1;cached_row<=sr;state<=content?READ:PRESENT;
                        end
                    end else ix<=ix+1'b1;
                end
                READ:state<=PRESENT;
                PRESENT:if(out_ready)begin
                    if(out_x==OUT_WIDTH-1)begin
                        out_x<=0;sx<=sx_initial;px<=px_initial;
                        if(out_row==OUT_HEIGHT-1)begin
                            scale_done<=1;
                            // Drain a cropped/unselected source tail. EOF is
                            // independently reported by the BMP decoder.
                            state<=(ir==sh)?IDLE:DRAIN;
                        end else begin
                            out_row<=out_row+1'b1;
                            if(inside_y_q && !last_content_row_q)begin
                                sr<=sr+advance_y;
                                py<=next_py-(advance_y==3?dy3:advance_y==2?dy2:advance_y==1?{1'b0,dy}:14'd0);
                            end
                            state<=SELECT;
                        end
                    end else begin
                        out_x<=out_x+1'b1;
                        if(content_q && !last_content_x_q)begin
                            sx<=sx+advance_x;
                            px<=next_px-(advance_x==3?dx3:advance_x==2?dx2:advance_x==1?{1'b0,dx}:14'd0);
                        end
                        state<=SELECT;
                    end
                end
                DRAIN:if(in_valid && in_ready)begin
                    if(ix==last_source_x)begin
                        ix<=0;ir<=ir+1'b1;
                        if(ir==last_source_row)state<=IDLE;
                    end else ix<=ix+1'b1;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule

// Restoring setup division: one 14-bit compare/subtract per clock, no DSP or
// combinational runtime divide. Start operands are immutable for all 32 steps.
module scaler_setup_divider(
    input wire clk,reset,start,
    input wire [31:0] dividend,
    input wire [12:0] divisor,
    output reg done,
    output reg [31:0] quotient,
    output reg [12:0] remainder
);
    reg active;
    reg [5:0] count;
    reg [31:0] work;
    reg [12:0] den;
    wire [13:0] trial={remainder,work[31]};
    wire ge=trial>={1'b0,den};
    always @(posedge clk or posedge reset)begin
        if(reset)begin done<=0;quotient<=0;remainder<=0;active<=0;count<=0;work<=0;den<=1;end
        else begin
            done<=0;
            if(start && !active)begin
                work<=dividend;den<=divisor;remainder<=0;count<=0;active<=1;
            end else if(active)begin
                remainder<=ge?trial-{1'b0,den}:trial;
                work<={work[30:0],ge};count<=count+1'b1;
                if(count==31)begin quotient<={work[30:0],ge};active<=0;done<=1;end
            end
        end
    end
endmodule
