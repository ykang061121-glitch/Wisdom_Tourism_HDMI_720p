// Events are transaction-local and latched independently, not pulse-coincident.
// Memory events are armed only AFTER this transaction's return-to-zero ACK.
module frame_completion_guard (
    input wire clk, reset, start, cancel, memory_arm,
    input wire source_done, scale_done, memory_done,
    output reg source_seen, scale_seen, memory_seen,
    output reg ready_pulse
);
    reg active, armed, published;
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            active<=0; armed<=0; published<=0; source_seen<=0;
            scale_seen<=0; memory_seen<=0; ready_pulse<=0;
        end else begin
            ready_pulse<=0;
            if(cancel || start) begin
                active<=start && !cancel; armed<=0; published<=0;
                source_seen<=0; scale_seen<=0; memory_seen<=0;
            end else if(active) begin
                if(memory_arm) armed<=1;
                if(source_done) source_seen<=1;
                if(scale_done) scale_seen<=1;
                if(memory_done && armed) memory_seen<=1;
                if(source_seen && scale_seen && memory_seen && !published) begin
                    ready_pulse<=1; published<=1;
                end
            end
        end
    end
endmodule
