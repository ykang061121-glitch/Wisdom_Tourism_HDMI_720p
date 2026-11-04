`timescale 1ns/1ps

module tb_bmp_read;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg scan_start = 1'b0;
    reg load_start = 1'b0;
    reg [31:0] load_sector = 32'd7;
    reg sd_init_done = 1'b1;
    reg write_req_ack = 1'b0;
    reg [7:0] sd_sec_read_data = 8'd0;
    reg sd_sec_read_data_valid = 1'b0;
    reg sd_sec_read_end = 1'b0;
    wire ready;
    wire scan_done;
    wire scan_found_valid;
    wire [31:0] scan_found_sector;
    wire [2:0] scan_found_total;
    wire [3:0] state_code;
    wire write_req;
    wire sd_sec_read;
    wire [31:0] sd_sec_read_addr;
    wire bmp_data_wr_en;
    wire [23:0] bmp_data;

    reg [7:0] sector [0:511];
    integer i;
    integer errors = 0;
    integer pixel_pulses = 0;
    reg [23:0] last_pixel = 24'd0;
    reg [23:0] first_pixel = 24'd0;
    wire load_error;

    always #5 clk = ~clk;

    bmp_read dut (
        .clk(clk), .rst(rst), .cancel(1'b0), .ready(ready),
        .pixel_ready(1'b1), .load_error(load_error),
        .scan_start(scan_start), .scan_start_sector(32'd0),
        .scan_max_sector(32'd0), .scan_target_count(3'd1),
        .scan_done(scan_done), .scan_found_valid(scan_found_valid),
        .scan_found_sector(scan_found_sector), .scan_found_total(scan_found_total),
        .load_start(load_start), .load_sector(load_sector),
        .sd_init_done(sd_init_done), .state_code(state_code),
        .bmp_width(16'd640), .bmp_height(16'd480),
        .write_req(write_req), .write_req_ack(write_req_ack),
        .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),
        .bmp_data_wr_en(bmp_data_wr_en), .bmp_data(bmp_data)
    );

    always @(posedge clk) begin
        if (bmp_data_wr_en) begin
            if (pixel_pulses==0) first_pixel = bmp_data;
            pixel_pulses = pixel_pulses + 1;
            last_pixel = bmp_data;
        end
    end

    task fail;
        input [8*120-1:0] message;
        begin
            errors = errors + 1;
            $error("%0s", message);
        end
    endtask

    task set_u16;
        input integer offset;
        input integer value;
        begin
            sector[offset] = value[7:0];
            sector[offset+1] = value[15:8];
        end
    endtask

    task set_u32;
        input integer offset;
        input [31:0] value;
        begin
            sector[offset] = value[7:0];
            sector[offset+1] = value[15:8];
            sector[offset+2] = value[23:16];
            sector[offset+3] = value[31:24];
        end
    endtask

    task make_valid_sector;
        begin
            for (i = 0; i < 512; i = i + 1)
                sector[i] = 8'd0;
            sector[0] = "B";
            sector[1] = "M";
            set_u32(2, 32'd921654); // complete 640x480 BMP length
            set_u32(10, 32'd54);
            set_u32(14, 32'd40);
            set_u32(18, 32'd640);
            set_u32(22, 32'd480);
            set_u16(26, 1);
            set_u16(28, 24);
            set_u32(30, 0);
            sector[54] = 8'h12; // B
            sector[55] = 8'h34; // G
            sector[56] = 8'h56; // R
        end
    endtask

    task reset_dut;
        begin
            rst = 1'b1;
            load_start = 1'b0;
            write_req_ack = 1'b0;
            sd_sec_read_data_valid = 1'b0;
            sd_sec_read_end = 1'b0;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            repeat (2) @(posedge clk);
            pixel_pulses = 0;
            last_pixel = 24'd0;
        end
    endtask

    task start_load;
        begin
            @(negedge clk);
            load_start = 1'b1;
            @(negedge clk);
            load_start = 1'b0;
            wait (sd_sec_read === 1'b1);
        end
    endtask

    task send_sector;
        begin
            for (i = 0; i < 512; i = i + 1) begin
                @(negedge clk);
                sd_sec_read_data = sector[i];
                sd_sec_read_data_valid = 1'b1;
            end
            @(negedge clk);
            sd_sec_read_data_valid = 1'b0;
            sd_sec_read_end = 1'b1;
            @(negedge clk);
            sd_sec_read_end = 1'b0;
        end
    endtask

    task expect_reject;
        input integer case_number;
        begin
            start_load;
            send_sector;
            wait(load_error);
            wait(ready);
            if (!ready)
                fail("invalid BMP did not return to idle");
            if (write_req)
                fail("invalid BMP asserted write_req");
            if (pixel_pulses != 0)
                fail("invalid BMP emitted pixel data");
            $display("BMP_CASE_%0d_REJECT_OK", case_number);
        end
    endtask

    initial begin
        // CASE 1 and CASE 7: valid header and B,G,R -> R,G,B packing.
        make_valid_sector;
        reset_dut;
        start_load;
        send_sector;
        wait(write_req);
        if (!write_req)
            fail("valid BMP header was not accepted");
        if ((dut.header_0 != "B") || (dut.header_1 != "M"))
            fail("BM signature was not captured");
        if ((dut.width != 640) || (dut.height != 480))
            fail("640x480 dimensions were not captured");
        if (dut.bit_count != 24)
            fail("24-bit depth was not captured");
        if (dut.compression != 0)
            fail("compression=0 was not captured");
        if (dut.pixel_offset != 54)
            fail("pixel offset was not captured");

        @(negedge clk);
        write_req_ack = 1'b1;
        wait(!write_req);
        @(negedge clk); write_req_ack = 1'b0;
        wait (sd_sec_read === 1'b1);
        send_sector;
        repeat (1100) @(posedge clk);
        if (pixel_pulses != 152)
            fail("512-byte sector did not emit exactly 152 complete pixels after 54-byte header");
        if (first_pixel != 24'h563412)
            fail("B,G,R bytes were not packed as R,G,B");
        $display("BMP_CASE_1_AND_7_OK");

        // CASE 2: not BM.
        make_valid_sector; sector[0] = "X";
        reset_dut; expect_reject(2);

        // CASE 3: wrong width.
        make_valid_sector; set_u32(18, 32'd639);
        reset_dut; expect_reject(3);

        // CASE 4: wrong height.
        make_valid_sector; set_u32(22, 32'd479);
        reset_dut; expect_reject(4);

        // CASE 5: not 24-bit.
        make_valid_sector; set_u16(28, 16);
        reset_dut; expect_reject(5);

        // CASE 6: compressed.
        make_valid_sector; set_u32(30, 32'd1);
        reset_dut; expect_reject(6);

        if (errors == 0) begin
            $display("BMP_READ_TEST_PASS");
            $finish;
        end else begin
            $fatal(1, "BMP_READ_TEST_FAIL errors=%0d", errors);
        end
    end

    initial begin
        #2000000;
        $fatal(1, "BMP_READ_TEST_TIMEOUT");
    end
endmodule
