module fade_transition_cdc (
    input  wire       src_clk,
    input  wire       src_reset,
    input  wire       src_request_toggle,
    input  wire       src_ready_toggle,
    input  wire       src_cancel_toggle,
    input  wire [3:0] src_pending_payload,
    output wire       src_commit_pulse,
    output wire       src_transition_done_pulse,

    input  wire       dst_clk,
    input  wire       dst_reset,
    output wire       dst_request_pulse,
    output wire       dst_cancel_pulse,
    output wire       dst_next_frame_ready,
    output reg  [3:0] dst_pending_payload,
    input  wire       dst_commit_pulse,
    input  wire       dst_transition_done_pulse
);

reg [2:0] request_sync;
reg [2:0] cancel_sync;
reg [2:0] ready_sync;
reg       ready_seen;
reg       commit_toggle;
reg [2:0] commit_sync;
reg       done_toggle;
reg [2:0] done_sync;

assign dst_request_pulse    = request_sync[2] ^ request_sync[1];
assign dst_cancel_pulse     = cancel_sync[2] ^ cancel_sync[1];
assign dst_next_frame_ready = ready_sync[2] ^ commit_toggle;
assign src_commit_pulse     = commit_sync[2] ^ commit_sync[1];
assign src_transition_done_pulse = done_sync[2] ^ done_sync[1];

// Request and ready events cross as toggles.  The multi-bit payload is bundled
// data: the source writes it before toggling ready and holds it until commit is
// acknowledged back in the source domain.
always @(posedge dst_clk or posedge dst_reset) begin
    if (dst_reset) begin
        request_sync       <= 3'b000;
        cancel_sync        <= 3'b000;
        ready_sync         <= 3'b000;
        ready_seen         <= 1'b0;
        commit_toggle      <= 1'b0;
        done_toggle        <= 1'b0;
        dst_pending_payload<= 4'd0;
    end else begin
        request_sync <= {request_sync[1:0], src_request_toggle};
        cancel_sync <= {cancel_sync[1:0], src_cancel_toggle};
        ready_sync   <= {ready_sync[1:0], src_ready_toggle};

        if (ready_sync[2] != ready_seen) begin
            dst_pending_payload <= src_pending_payload;
            ready_seen          <= ready_sync[2];
        end

        if (dst_commit_pulse && dst_next_frame_ready)
            commit_toggle <= ready_sync[2];
        if (dst_cancel_pulse) commit_toggle <= ready_sync[2];
        if (dst_transition_done_pulse)
            done_toggle <= ~done_toggle;
    end
end

always @(posedge src_clk or posedge src_reset) begin
    if (src_reset)
        begin
            commit_sync <= 3'b000;
            done_sync   <= 3'b000;
        end
    else begin
        commit_sync <= {commit_sync[1:0], commit_toggle};
        done_sync   <= {done_sync[1:0], done_toggle};
    end
end

endmodule
