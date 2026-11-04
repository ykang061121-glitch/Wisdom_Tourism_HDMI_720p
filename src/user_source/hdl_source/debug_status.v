module debug_status (
    input  wire       clk,
    input  wire       rst,

    input  wire       sd_init_done,
    input  wire       scan_active,
    input  wire       scan_done,
    input  wire       bmp_found,
    input  wire [2:0] found_count,
    input  wire       load_busy,
    input  wire       source_done_seen,
    input  wire       display_valid,
    input  wire       auto_play_en,
    input  wire [1:0] display_image_index,
    input  wire [1:0] load_image_index,

    output reg  [7:0] status_code,
    output reg  [3:0] image_number,
    output reg        image_number_valid
);

localparam [7:0] STATUS_RESET            = 8'h00;
localparam [7:0] STATUS_SD_WAIT          = 8'h01;
localparam [7:0] STATUS_BMP_SCAN         = 8'h02;
localparam [7:0] STATUS_BMP_FOUND        = 8'h03;
localparam [7:0] STATUS_FRAME_LOAD       = 8'h04;
localparam [7:0] STATUS_FRAME_WRITE_WAIT = 8'h05;
localparam [7:0] STATUS_DISPLAY_READY    = 8'h06;
localparam [7:0] STATUS_AUTO_PLAY        = 8'h07;
localparam [7:0] ERROR_NO_VALID_BMP      = 8'hE0;

// Observation-only state encoder. All inputs are already in the sd_card_clk
// domain. No output from this module feeds back into the functional datapath.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        status_code        <= STATUS_RESET;
        image_number       <= 4'd0;
        image_number_valid <= 1'b0;
    end else begin
        image_number_valid <= bmp_found;
        if (load_busy)
            image_number <= {2'b00, load_image_index} + 4'd1;
        else if (display_valid)
            image_number <= {2'b00, display_image_index} + 4'd1;
        else if (bmp_found)
            image_number <= {1'b0, found_count};
        else
            image_number <= 4'd0;

        if (!sd_init_done)
            status_code <= STATUS_SD_WAIT;
        else if (scan_active && !bmp_found)
            status_code <= STATUS_BMP_SCAN;
        else if (scan_active && bmp_found)
            status_code <= STATUS_BMP_FOUND;
        else if (scan_done && !bmp_found)
            status_code <= ERROR_NO_VALID_BMP;
        else if (load_busy && !source_done_seen)
            status_code <= STATUS_FRAME_LOAD;
        else if (load_busy && source_done_seen)
            status_code <= STATUS_FRAME_WRITE_WAIT;
        else if (display_valid && auto_play_en)
            status_code <= STATUS_AUTO_PLAY;
        else if (display_valid)
            status_code <= STATUS_DISPLAY_READY;
        else if (bmp_found)
            status_code <= STATUS_BMP_FOUND;
        else
            status_code <= STATUS_SD_WAIT;
    end
end

endmodule
