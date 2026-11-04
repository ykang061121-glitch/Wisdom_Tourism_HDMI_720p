// SD control domain only. A short active-low K3 press selects a dwell time.
// The dwell starts AFTER loading/fade-in has released the existing busy flag.
module playback_interval_control #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter [1:0] DEFAULT_INTERVAL_CODE = 2'd2,
    parameter EXTERNAL_EVENTS=0
)(
    input wire clk,
    input wire reset,
    input wire key_interval,
    input wire key_event,
    input wire timer_enable,
    input wire timer_restart,
    output reg [1:0] interval_code,
    output wire interval_press,
    output reg auto_tick,
    output wire progress_running,
    output wire [8:0] progress_units
);
    localparam integer COUNT_BITS = CLK_FREQ_HZ<=1 ? 1 : $clog2(CLK_FREQ_HZ);
    reg [COUNT_BITS-1:0] subsecond_count;
    reg [3:0] elapsed_seconds;
    reg [3:0] last_second;

    wire raw_interval_press;
    assign interval_press=EXTERNAL_EVENTS?key_event:raw_interval_press;
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(20)) interval_key (
        .clk(clk),.rst(reset),.button_in(key_interval),.press_pulse(raw_interval_press));

    // 01=3s,10=5s,11=10s. 00 reserved. Cycle 5->10->3->5.
    // Original 100-MHz counter and progress DDA are retained.
    always @* begin
        case(interval_code)
            1:last_second=2;
            3:last_second=9;
            default:last_second=4;
        endcase
    end
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            interval_code<=(DEFAULT_INTERVAL_CODE==1||DEFAULT_INTERVAL_CODE==3)?DEFAULT_INTERVAL_CODE:2'd2;
            subsecond_count<=0;elapsed_seconds<=0;auto_tick<=0;
        end else begin
            auto_tick<=0;
            // Exact next-code truth table: 00->10, 01->10, 10->11, 11->01.
            if(interval_press)interval_code<={~(interval_code[1]&interval_code[0]),interval_code[1]};
            // A setting/mode/manual change restarts a FULL selected interval,
            // never creates an immediate request even at the old expiration.
            if(!timer_enable || timer_restart || interval_press) begin
                subsecond_count<=0;elapsed_seconds<=0;
            end else if(subsecond_count==CLK_FREQ_HZ-1) begin
                subsecond_count<=0;
                if(elapsed_seconds==last_second) begin
                    elapsed_seconds<=0;auto_tick<=1;
                end else elapsed_seconds<=elapsed_seconds+1'b1;
            end else subsecond_count<=subsecond_count+1'b1;
        end
    end

    // Observation only: derive 1/256-second bins from the REAL subsecond
    // counter. Neither this threshold nor the display value feeds auto_tick.
    // For 100MHz the divisor is exact (390625 clocks); the remainder DDA also
    // preserves accelerated simulations whose clock frequency is not /256.
    localparam integer Q_BASE=CLK_FREQ_HZ/256;
    localparam integer Q_REM=CLK_FREQ_HZ%256;
    wire [7:0] fraction;
    generate if(CLK_FREQ_HZ>=256)begin: progress_fraction
        reg [7:0] bin;
        reg [7:0] remainder;
        reg [COUNT_BITS:0] next_boundary;
        wire [8:0] rem_sum={1'b0,remainder}+Q_REM;
        assign fraction=bin;
        always @(posedge clk or posedge reset)begin
            if(reset)begin
                bin<=0;remainder<=Q_REM;next_boundary<=Q_BASE+(Q_REM!=0)-1;
            end else if(!timer_enable || timer_restart || interval_press ||
                        subsecond_count==CLK_FREQ_HZ-1)begin
                bin<=0;remainder<=Q_REM;next_boundary<=Q_BASE+(Q_REM!=0)-1;
            end else if(subsecond_count==next_boundary)begin
                bin<=bin+1'b1;
                remainder<=rem_sum[7:0];
                next_boundary<=next_boundary+Q_BASE+rem_sum[8]+
                               (rem_sum[7:0]!=0)-(remainder!=0);
            end
        end
    end else begin: small_simulation_frequency
        assign fraction=(subsecond_count*256)/CLK_FREQ_HZ;
    end endgenerate
    wire [11:0] elapsed_quanta={elapsed_seconds,fraction};
    reg [8:0] progress_observed;
    always @(posedge clk or posedge reset)begin
        if(reset)progress_observed<=0;
        else if(!timer_enable || timer_restart || interval_press)progress_observed<=0;
        else case(interval_code)
            1:progress_observed<=elapsed_quanta/3;
            3:progress_observed<=elapsed_quanta/10;
            default:progress_observed<=elapsed_quanta/5;
        endcase
    end
    // 256 is the actual expiration event, not an early visual countdown.
    // Busy/restart hides and clears the line until a new stable dwell begins.
    assign progress_running=timer_enable && !timer_restart && !auto_tick;
    assign progress_units=auto_tick?9'd256:
        ((!timer_enable || timer_restart)?9'd0:progress_observed);
endmodule
