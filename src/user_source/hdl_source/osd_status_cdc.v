module osd_status_cdc #(parameter integer WIDTH=4)(
    input  wire       src_clk,
    input  wire       src_reset,
    input  wire [WIDTH-1:0] src_status,
    input  wire       dst_clk,
    input  wire       dst_reset,
    output reg  [WIDTH-1:0] dst_status
);

reg [WIDTH-1:0] src_hold;
reg [WIDTH-1:0] src_last_sent;
reg       src_request_toggle;
reg [1:0] src_ack_sync;

reg [WIDTH-1:0] dst_data_sync0;
reg [WIDTH-1:0] dst_data_sync1;
// One extra request settle stage: the two-stage data snapshot is
// sampled one full destination cycle before it is committed. With the
// separately checked <=8ns bundled-data route bound, even a first sample
// arriving before the slowest data bit cannot commit a torn bundle.
reg [2:0] dst_request_sync;
reg       dst_ack_toggle;

// Bundled-data source side.  src_hold is not changed again until the
// destination acknowledges the current request.  A later change is retained
// by comparing the live status with src_last_sent after the acknowledgement.
always @(posedge src_clk or posedge src_reset) begin
    if (src_reset) begin
        src_hold           <= 4'd0;
        src_last_sent      <= 4'd0;
        src_request_toggle <= 1'b0;
        src_ack_sync       <= 2'b00;
    end else begin
        src_ack_sync <= {src_ack_sync[0], dst_ack_toggle};
        if ((src_request_toggle == src_ack_sync[1]) &&
            (src_status != src_last_sent)) begin
            src_hold           <= src_status;
            src_last_sent      <= src_status;
            src_request_toggle <= ~src_request_toggle;
        end
    end
end

// The held data and request each pass through two destination registers.
// Because the source holds the bundle until acknowledgement, dst_data_sync1
// is coherent before the request edge is acted upon.
always @(posedge dst_clk or posedge dst_reset) begin
    if (dst_reset) begin
        dst_data_sync0    <= 4'd0;
        dst_data_sync1    <= 4'd0;
        dst_request_sync  <= 3'b000;
        dst_ack_toggle    <= 1'b0;
        dst_status        <= 4'd0;
    end else begin
        dst_data_sync0   <= src_hold;
        dst_data_sync1   <= dst_data_sync0;
        dst_request_sync <= {dst_request_sync[1:0], src_request_toggle};

        if (dst_request_sync[2] != dst_ack_toggle) begin
            dst_status     <= dst_data_sync1;
            dst_ack_toggle <= dst_request_sync[2];
        end
    end
end

endmodule
