// One complete CMD17 packet before exposing a stoppable byte stream.
// Cancel never aborts SPI midway: discard/drain its current packet first.
module sd_sector_buffer #(
    parameter integer TIMEOUT_CYCLES = 10000000
)(
    input wire clk, reset, cancel,
    input wire start,
    input wire [31:0] sector,
    output wire start_ready,
    output wire sd_read,
    output reg [31:0] sd_addr,
    input wire [7:0] sd_data,
    input wire sd_valid, sd_end,
    output wire [7:0] byte_data,
    output wire byte_valid, byte_last,
    input wire byte_ready,
    output reg error_pulse,
    output reg [1:0] error_kind
);
    localparam IDLE=0, FETCH=1, PREFETCH=2, SEND=3, DRAIN=4;
    reg [2:0] state;
    reg [7:0] ram [0:511]; // No array reset; synchronous read, single writer.
    reg [7:0] read_q;
    reg [9:0] received;
    reg [8:0] read_index;
    reg [23:0] watchdog;
    assign start_ready=(state==IDLE);
    assign sd_read=(state==FETCH);
    assign byte_data=read_q;
    assign byte_valid=(state==SEND) && !cancel;
    assign byte_last=(read_index==9'd511);
    always @(posedge clk) begin
        if(state==FETCH && sd_valid && received<10'd512 && !cancel)
            ram[received[8:0]]<=sd_data;
        if(state==PREFETCH) read_q<=ram[read_index];
    end
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            state<=IDLE; sd_addr<=0; received<=0; read_index<=0;
            watchdog<=0; error_pulse<=0; error_kind<=0;
        end else begin
            error_pulse<=0;
            if(cancel) begin
                if(state==FETCH || state==DRAIN)
                    state<=sd_end ? IDLE : DRAIN;
                else state<=IDLE;
            end else case(state)
                IDLE: if(start) begin
                    sd_addr<=sector; received<=0; watchdog<=0; state<=FETCH;
                end
                FETCH: begin
                    if(sd_valid) begin
                        if(received<512) received<=received+1'b1;
                        else begin error_pulse<=1; error_kind<=2; state<=DRAIN; end
                    end
                    if(sd_end) begin
                        if((received==512 && !sd_valid) || (received==511 && sd_valid)) begin
                            read_index<=0; state<=PREFETCH;
                        end else begin
                            error_pulse<=1; error_kind<=1; state<=IDLE;
                        end
                    end else if(watchdog==TIMEOUT_CYCLES-1) begin
                        error_pulse<=1; error_kind<=3; state<=DRAIN;
                    end else watchdog<=watchdog+1'b1;
                end
                PREFETCH: state<=SEND;
                SEND: if(byte_ready) begin
                    if(byte_last) state<=IDLE;
                    else begin read_index<=read_index+1'b1; state<=PREFETCH; end
                end
                DRAIN: if(sd_end) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
