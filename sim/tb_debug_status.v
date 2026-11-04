`timescale 1ns/1ps

module tb_debug_status;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sd_init_done = 1'b0;
    reg scan_active = 1'b0;
    reg scan_done = 1'b0;
    reg bmp_found = 1'b0;
    reg [2:0] found_count = 3'd0;
    reg load_busy = 1'b0;
    reg source_done_seen = 1'b0;
    reg display_valid = 1'b0;
    reg auto_play_en = 1'b0;
    reg [1:0] display_image_index = 2'd0;
    reg [1:0] load_image_index = 2'd0;
    wire [7:0] status_code;
    wire [3:0] image_number;
    wire image_number_valid;
    integer errors = 0;

    always #5 clk = ~clk;

    debug_status dut (
        .clk(clk), .rst(rst),
        .sd_init_done(sd_init_done),
        .scan_active(scan_active), .scan_done(scan_done),
        .bmp_found(bmp_found), .found_count(found_count),
        .load_busy(load_busy), .source_done_seen(source_done_seen),
        .display_valid(display_valid), .auto_play_en(auto_play_en),
        .display_image_index(display_image_index),
        .load_image_index(load_image_index),
        .status_code(status_code), .image_number(image_number),
        .image_number_valid(image_number_valid)
    );

    task check_status;
        input [7:0] expected_status;
        input       expected_valid;
        input [3:0] expected_image;
        input [8*40-1:0] label;
        begin
            @(posedge clk);
            #1;
            if (status_code !== expected_status) begin
                errors = errors + 1;
                $error("%0s status expected=%02h actual=%02h", label,
                       expected_status, status_code);
            end
            if (image_number_valid !== expected_valid) begin
                errors = errors + 1;
                $error("%0s image-valid mismatch", label);
            end
            if (expected_valid && (image_number !== expected_image)) begin
                errors = errors + 1;
                $error("%0s image expected=%0d actual=%0d", label,
                       expected_image, image_number);
            end
        end
    endtask

    initial begin
        #1;
        if (status_code !== 8'h00) begin
            errors = errors + 1;
            $error("RESET status expected=00 actual=%02h", status_code);
        end

        @(negedge clk); rst = 1'b0;
        check_status(8'h01, 1'b0, 4'd0, "SD_WAIT");

        @(negedge clk); sd_init_done = 1'b1; scan_active = 1'b1;
        check_status(8'h02, 1'b0, 4'd0, "BMP_SCAN");

        @(negedge clk); bmp_found = 1'b1; found_count = 3'd1;
        check_status(8'h03, 1'b1, 4'd1, "BMP_FOUND");

        @(negedge clk); scan_active = 1'b0; scan_done = 1'b1;
        load_busy = 1'b1; load_image_index = 2'd0;
        check_status(8'h04, 1'b1, 4'd1, "FRAME_LOAD");

        @(negedge clk); source_done_seen = 1'b1;
        check_status(8'h05, 1'b1, 4'd1, "FRAME_WRITE_WAIT");

        @(negedge clk); load_busy = 1'b0; source_done_seen = 1'b0;
        display_valid = 1'b1; display_image_index = 2'd0;
        check_status(8'h06, 1'b1, 4'd1, "DISPLAY_READY");

        @(negedge clk); auto_play_en = 1'b1;
        check_status(8'h07, 1'b1, 4'd1, "AUTO_PLAY");

        // The only defined error has a direct hardware basis: completed scan
        // with zero accepted BMP images.
        @(negedge clk); auto_play_en = 1'b0; display_valid = 1'b0;
        bmp_found = 1'b0; found_count = 3'd0;
        check_status(8'hE0, 1'b0, 4'd0, "NO_VALID_BMP");

        if (errors == 0) begin
            $display("DEBUG_STATUS_TEST_PASS");
            $finish;
        end else begin
            $fatal(1, "DEBUG_STATUS_TEST_FAIL errors=%0d", errors);
        end
    end

    initial begin
        #10000;
        $fatal(1, "DEBUG_STATUS_TEST_TIMEOUT");
    end
endmodule
