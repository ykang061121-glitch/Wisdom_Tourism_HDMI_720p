// The same audited 3-request-stage, held-data request/ACK mailbox protocol.
// Extra payload is observational metadata / display coefficients only.
module compliance_control_bridge #(
    parameter CLK_FREQ_HZ=100000000
)(
    input wire sd_clk,video_clk,reset,frame_boundary,
    input wire key3_n,key4_n,
    input wire [1:0] switches_async,
    input wire [43:0] scaling_meta_sd,
    input wire [1:0] image_sd,image_video,
    input wire signed [7:0] preset_brightness,
    input wire [1:0] preset_contrast,
    output wire normal_key3,normal_key4,
    output reg signed [7:0] brightness,
    output reg [7:0] contrast,
    output reg [1:0] preset_mode,
    output reg [11:0] brightness_digits,contrast_digits,
    output reg adjust_mode,target_contrast,fast_step,
    output reg meta_valid,
    output reg [63:0] meta_bcd
);
    wire mode_sd,target_sd,fast_sd;
    wire signed [7:0] bri_sd;
    wire [7:0] con_sd;
    wire [1:0] preset_sd,formatted_image;
    wire formatted_valid;
    wire [63:0] formatted_bcd;
    wire [87:0] received;
    reg [87:0] snapshot;
    reg apply_pending;
    function [11:0] decimal3;
      input [7:0] value;
      reg[3:0]h,t,u;
      begin h=value/100;t=(value/10)%10;u=value%10;decimal3={h,t,u};end
    endfunction
    adjustment_key_control #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) keys(
        .clk(sd_clk),.reset(reset),.key3_n(key3_n),.key4_n(key4_n),
        .switches_async(switches_async),.normal_key3(normal_key3),.normal_key4(normal_key4),
        .adjust_mode(mode_sd),.brightness(bri_sd),.contrast(con_sd),
        .preset_mode(preset_sd),
        .target_contrast(target_sd),.fast_step(fast_sd));
    scaling_metadata_format formatter(.clk(sd_clk),.reset(reset),
        .image_index(image_sd),.scaling_meta(scaling_meta_sd),
        .valid(formatted_valid),.formatted_image(formatted_image),.bcd(formatted_bcd));
    osd_status_cdc #(.WIDTH(88)) mailbox(
        .src_clk(sd_clk),.src_reset(reset),
        .src_status({formatted_valid,formatted_image,formatted_bcd,
                     mode_sd,target_sd,fast_sd,bri_sd,con_sd,preset_sd}),
        .dst_clk(video_clk),.dst_reset(reset),.dst_status(received));
    // Original preset registers also update at frame_boundary. Applying one
    // clock later consumes their NEW values, still inside blanking.
    always @(posedge video_clk or posedge reset)begin
        if(reset)begin snapshot<=0;apply_pending<=0;brightness<=0;contrast<=100;preset_mode<=0;
            brightness_digits<=0;contrast_digits<=12'h100;
            adjust_mode<=0;target_contrast<=0;fast_step<=0;meta_valid<=0;meta_bcd<=0;end
        else begin
            apply_pending<=frame_boundary;
            if(frame_boundary)snapshot<=received;
            if(apply_pending)begin
                if(snapshot[9:2]>=50 && snapshot[9:2]<=200)begin
                    brightness<=$signed(snapshot[17:10]);
                    contrast<=snapshot[9:2];preset_mode<=snapshot[1:0];
                    brightness_digits<=decimal3(snapshot[17]?-snapshot[17:10]:snapshot[17:10]);
                    contrast_digits<=decimal3(snapshot[9:2]);
                end
                adjust_mode<=snapshot[20];target_contrast<=snapshot[19];fast_step<=snapshot[18];
                meta_valid<=snapshot[87] && snapshot[86:85]==image_video;
                meta_bcd<=snapshot[84:21];
            end
        end
    end
endmodule
