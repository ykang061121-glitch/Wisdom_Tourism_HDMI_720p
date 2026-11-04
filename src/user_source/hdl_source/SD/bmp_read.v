// CMD17 is captured in full before decoding; only accepted bytes advance.
module bmp_read #(
    parameter TEST_ALLOW_SIZE = 0,
    parameter ALLOW_720P = 0,
    parameter GENERIC_SIZE = 0,
    parameter SECTOR_TIMEOUT_CYCLES = 10000000,
    parameter [31:0] MAX_DATA_SECTOR = 32'd131071
)(
    input clk, rst, cancel,
    output ready,
    input scan_start,
    input [31:0] scan_start_sector, scan_max_sector,
    input [2:0] scan_target_count,
    output reg scan_done, scan_found_valid,
    output reg [31:0] scan_found_sector,
    output reg [2:0] scan_found_total,
    input load_start,
    input [31:0] load_sector,
    input sd_init_done,
    output reg [3:0] state_code,
    input [15:0] bmp_width, bmp_height,
    output reg write_req,
    input write_req_ack,
    output sd_sec_read,
    output [31:0] sd_sec_read_addr,
    input [7:0] sd_sec_read_data,
    input sd_sec_read_data_valid, sd_sec_read_end,
    output bmp_data_wr_en,
    output [23:0] bmp_data,
    input pixel_ready,
    output pixel_row_last,
    output [(ALLOW_720P?11:10)-1:0] source_width, source_height,
    output reg frame_start,
    output source_done,
    output reg load_error,
    output reg [7:0] error_code
);
localparam ST_IDLE=0, ST_SCAN=1, ST_LOAD_HDR=2, ST_LOAD_WAIT=3,
           ST_LOAD_DATA=4, ST_LOAD_RELEASE=5, ST_FIELDS=6, ST_LENGTH=7,
           ST_LENGTH_CHECK=8, ST_ADDRESS=9, ST_RANGE=10, ST_SCAN_ADVANCE=11,
           ST_RANGE_COMMIT=12, ST_STRIDE=13, ST_PAYLOAD=14;
reg [3:0] state;
// Preserve the audited four-phase handshake: synchronize high, lower request,
// wait for synchronized low before permitting any frame data.
reg write_ack_meta, write_ack_sync;
always @(posedge clk or posedge rst)
    if (rst) begin write_ack_meta<=0; write_ack_sync<=0; end
    else begin write_ack_meta<=write_req_ack; write_ack_sync<=write_ack_meta; end

reg [7:0] header_0, header_1;
reg [31:0] file_len, pixel_offset, width, height, dib_size, compression;
reg [15:0] planes, bit_count;
reg [5:0] header_pos;
reg [31:0] scan_sector, load_sector_latched, current_sector;
// Snapshot scan policy at acceptance. No later input change can mix with the
// header/address transaction during the range-evaluate/commit pipeline.
reg [31:0] scan_max_latched;
reg [2:0] scan_target_latched;
reg range_invalid, scan_stop_after_match;
reg scan_mode, sector_requested, sector_start;
reg [31:0] payload_bytes;
reg [12:0] stride_bytes;
// 1920 * align4(1920*3) = 11,059,200 bytes: requires 24 bits.
reg [23:0] payload_acc;
reg [10:0] payload_rows_left;
reg [32:0] pixel_end, next_file_sector;
reg [23:0] file_sector_count;
reg [31:0] last_file_sector;
wire sector_ready, sector_error;
wire [1:0] sector_error_kind;
wire [7:0] byte_data;
wire byte_valid, byte_last, decoder_byte_ready, decoder_busy;
wire header_phase = state==ST_SCAN || state==ST_LOAD_HDR;
wire byte_ready = header_phase || (state==ST_LOAD_DATA && decoder_byte_ready);
wire abort_stream = cancel || !sd_init_done || state==ST_FIELDS || load_error || source_done;
wire format_ok = header_0=="B" && header_1=="M" && dib_size==32'd40 &&
                 planes==16'd1 && bit_count==16'd24 && compression==0;
wire bounded_size_ok=width>=32'd16 && width<=32'd1920 &&
                     height>=32'd16 && height<=32'd1920;
wire size_ok = (GENERIC_SIZE && ALLOW_720P) ? bounded_size_ok :
              (width==32'd320 && height==32'd240) ||
               (width==32'd640 && height==32'd480) ||
               (width==32'd800 && height==32'd600) ||
               (ALLOW_720P && width==32'd1280 && height==32'd720) ||
               (TEST_ALLOW_SIZE && width=={16'd0,bmp_width} &&
                height=={16'd0,bmp_height} && width>0 && width<=800 && height>0 && height<=600);
assign source_width=width[(ALLOW_720P?11:10)-1:0];
assign source_height=height[(ALLOW_720P?11:10)-1:0];
assign ready=state==ST_IDLE && sector_ready && !write_ack_sync;

sd_sector_buffer #(.TIMEOUT_CYCLES(SECTOR_TIMEOUT_CYCLES)) sector_buffer (
    .clk(clk), .reset(rst), .cancel(abort_stream), .start(sector_start),
    .sector(current_sector), .start_ready(sector_ready),
    .sd_read(sd_sec_read), .sd_addr(sd_sec_read_addr),
    .sd_data(sd_sec_read_data), .sd_valid(sd_sec_read_data_valid), .sd_end(sd_sec_read_end),
    .byte_data(byte_data), .byte_valid(byte_valid), .byte_last(byte_last), .byte_ready(byte_ready),
    .error_pulse(sector_error), .error_kind(sector_error_kind)
);
bmp_pixel_decoder #(.COORD_BITS(ALLOW_720P?11:10)) decoder (
    .clk(clk), .reset(rst), .cancel(cancel || load_error || !sd_init_done),
    .start(frame_start), .width(source_width), .height(source_height), .pixel_offset(pixel_offset),
    .byte_data(byte_data), .byte_valid(byte_valid && state==ST_LOAD_DATA),
    .byte_ready(decoder_byte_ready), .pixel_data(bmp_data), .pixel_valid(bmp_data_wr_en),
    .pixel_ready(pixel_ready), .row_last(pixel_row_last), .source_done(source_done), .busy(decoder_busy)
);
// Header writes use a local registered acceptance/data/slot snapshot.
// byte_ready is unconditionally 1 during header_phase. All useful fields end
// at byte 33; ST_FIELDS follows byte 53, so the delayed write is already stable.
reg header_capture_valid;
reg [5:0] header_capture_slot;
reg [7:0] header_capture_data;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        header_capture_valid<=0;header_capture_slot<=0;header_capture_data<=0;
    end else begin
        header_capture_valid<=header_phase && byte_valid;
        if(header_phase && byte_valid) begin
            header_capture_slot<=header_pos;header_capture_data<=byte_data;
        end
    end
end
always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0<=0; header_1<=0; file_len<=0; pixel_offset<=0;
        width<=0; height<=0; dib_size<=0; compression<=0; planes<=0; bit_count<=0;
    end else if (header_capture_valid) begin
        case(header_capture_slot)
            0:header_0<=header_capture_data; 1:header_1<=header_capture_data;
            2:file_len[7:0]<=header_capture_data; 3:file_len[15:8]<=header_capture_data;
            4:file_len[23:16]<=header_capture_data; 5:file_len[31:24]<=header_capture_data;
            10:pixel_offset[7:0]<=header_capture_data; 11:pixel_offset[15:8]<=header_capture_data;
            12:pixel_offset[23:16]<=header_capture_data; 13:pixel_offset[31:24]<=header_capture_data;
            14:dib_size[7:0]<=header_capture_data; 15:dib_size[15:8]<=header_capture_data;
            16:dib_size[23:16]<=header_capture_data; 17:dib_size[31:24]<=header_capture_data;
            18:width[7:0]<=header_capture_data; 19:width[15:8]<=header_capture_data;
            20:width[23:16]<=header_capture_data; 21:width[31:24]<=header_capture_data;
            22:height[7:0]<=header_capture_data; 23:height[15:8]<=header_capture_data;
            24:height[23:16]<=header_capture_data; 25:height[31:24]<=header_capture_data;
            26:planes[7:0]<=header_capture_data; 27:planes[15:8]<=header_capture_data;
            28:bit_count[7:0]<=header_capture_data; 29:bit_count[15:8]<=header_capture_data;
            30:compression[7:0]<=header_capture_data; 31:compression[15:8]<=header_capture_data;
            32:compression[23:16]<=header_capture_data; 33:compression[31:24]<=header_capture_data;
            default:;
        endcase
    end
end
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state<=ST_IDLE; state_code<=0; write_req<=0; scan_done<=0;
        scan_found_valid<=0; scan_found_sector<=0; scan_found_total<=0;
        header_pos<=0; scan_sector<=0; load_sector_latched<=0; current_sector<=0;
        scan_max_latched<=0; scan_target_latched<=0;
        range_invalid<=0; scan_stop_after_match<=0;
        scan_mode<=0; sector_requested<=0; sector_start<=0; payload_bytes<=0;
        pixel_end<=0; file_sector_count<=0; next_file_sector<=0; last_file_sector<=0;
        frame_start<=0; load_error<=0; error_code<=0;
        stride_bytes<=0;payload_acc<=0;payload_rows_left<=0;
    end else begin
        scan_found_valid<=0; sector_start<=0; frame_start<=0; load_error<=0;
        if (cancel || !sd_init_done) begin
            state<=ST_IDLE; write_req<=0; sector_requested<=0;
            range_invalid<=0; scan_stop_after_match<=0;
            if (cancel && state!=ST_IDLE) begin load_error<=1; error_code<=8'hEF; scan_done<=1; end
            if (!sd_init_done) begin scan_done<=0; scan_found_total<=0; state_code<=0; end
        end else if (sector_error) begin
            state<=ST_IDLE; write_req<=0; sector_requested<=0;
            range_invalid<=0; scan_stop_after_match<=0;
            load_error<=1; error_code<=8'hE3;
            if (scan_mode) scan_done<=1;
        end else case(state)
            ST_IDLE: begin
                state_code<=1; write_req<=0;
                if (ready && scan_start) begin
                    scan_mode<=1; scan_sector<=scan_start_sector; current_sector<=scan_start_sector;
                    scan_max_latched<=scan_max_sector; scan_target_latched<=scan_target_count;
                    range_invalid<=0; scan_stop_after_match<=0;
                    header_pos<=0; sector_requested<=0; scan_done<=0; scan_found_total<=0; state<=ST_SCAN;
                end else if (ready && load_start) begin
                    scan_mode<=0; load_sector_latched<=load_sector; current_sector<=load_sector;
                    range_invalid<=0; scan_stop_after_match<=0;
                    header_pos<=0; sector_requested<=0; error_code<=0; state<=ST_LOAD_HDR;
                end
            end
            ST_SCAN, ST_LOAD_HDR: begin
                state_code<=2;
                if (scan_mode && (scan_sector>scan_max_latched || scan_target_latched==0)) begin
                    scan_done<=1; state<=ST_IDLE;
                end else begin
                    if (sector_ready && !sector_requested) begin sector_start<=1; sector_requested<=1; end
                    if (byte_valid && byte_ready) begin
                        if (header_pos==53) state<=ST_FIELDS;
                        else header_pos<=header_pos+1'b1;
                    end
                end
            end
            ST_FIELDS: begin
                if (!format_ok || !size_ok) begin
                    if (scan_mode) state<=ST_SCAN_ADVANCE;
                    else begin state<=ST_IDLE; load_error<=1; error_code<=format_ok ? 8'hE1 : 8'hE0; end
                end else if(GENERIC_SIZE && ALLOW_720P) begin
                    // Full 32-bit eligibility has already succeeded.
                    state<=ST_STRIDE;
                end else begin
                    // Valid production dimensions have zero row padding. The
                    // generic test fixture exercises decoder padding separately.
                    case(width)
                        320:payload_bytes<=32'd230400;
                        640:payload_bytes<=32'd921600;
                        800:payload_bytes<=32'd1440000;
                        1280:payload_bytes<=32'd2764800;
                        default: if (TEST_ALLOW_SIZE) payload_bytes<=(((width*3+3)>>2)<<2)*height;
                                 else payload_bytes<=0;
                    endcase
                    state<=ST_LENGTH;
                end
            end
            ST_LENGTH: begin
                pixel_end<={1'b0,pixel_offset}+{1'b0,payload_bytes};
                file_sector_count<={1'b0,file_len[31:9]}+(|file_len[8:0]);
                state<=ST_LENGTH_CHECK;
            end
            ST_STRIDE:begin
                stride_bytes<=((({2'd0,width[10:0]}<<1)+
                                {2'd0,width[10:0]}+13'd3)>>2)<<2;
                payload_acc<=0;payload_rows_left<=height[10:0];
                state<=ST_PAYLOAD;
            end
            ST_PAYLOAD:begin
                payload_acc<=payload_acc+{11'd0,stride_bytes};
                payload_rows_left<=payload_rows_left-1'b1;
                if(payload_rows_left==1)begin
                    payload_bytes<={8'd0,payload_acc}+{19'd0,stride_bytes};
                    state<=ST_LENGTH;
                end
            end
            ST_LENGTH_CHECK: begin
                if (pixel_offset<54 || pixel_end[32] || {1'b0,file_len}<pixel_end) begin
                    if (scan_mode) state<=ST_SCAN_ADVANCE;
                    else begin state<=ST_IDLE; load_error<=1; error_code<=8'hE2; end
                end else state<=ST_ADDRESS;
            end
            ST_ADDRESS: begin
                next_file_sector<={1'b0,(scan_mode ? scan_sector : load_sector_latched)}+{9'd0,file_sector_count};
                state<=ST_RANGE;
            end
            ST_RANGE: begin
                // Compare only here; do not drive the wide scan/address CE
                // fanout through this comparator. All operands remain held.
                range_invalid<=next_file_sector>({1'b0,MAX_DATA_SECTOR}+33'd1) || file_sector_count==0;
                scan_stop_after_match<=scan_found_total+1'b1>=scan_target_latched ||
                                       next_file_sector>{1'b0,scan_max_latched};
                state<=ST_RANGE_COMMIT;
            end
            ST_RANGE_COMMIT: begin
                if (range_invalid) begin
                    if (scan_mode) state<=ST_SCAN_ADVANCE;
                    else begin state<=ST_IDLE; load_error<=1; error_code<=8'hE2; end
                end else if (scan_mode) begin
                    scan_found_valid<=1; scan_found_sector<=scan_sector; scan_found_total<=scan_found_total+1'b1;
                    if (scan_stop_after_match) begin
                        scan_done<=1; state<=ST_IDLE;
                    end else begin
                        scan_sector<=next_file_sector[31:0]; current_sector<=next_file_sector[31:0];
                        header_pos<=0; sector_requested<=0; state<=ST_SCAN;
                    end
                end else begin
                    last_file_sector<=next_file_sector[31:0]-1'b1; current_sector<=load_sector_latched;
                    sector_requested<=0; write_req<=1; state<=ST_LOAD_WAIT;
                end
            end
            ST_SCAN_ADVANCE: begin
                if (scan_sector>=scan_max_latched) begin scan_done<=1; state<=ST_IDLE; end
                else begin
                    scan_sector<=scan_sector+1'b1; current_sector<=scan_sector+1'b1;
                    header_pos<=0; sector_requested<=0; state<=ST_SCAN;
                end
            end
            ST_LOAD_WAIT: begin
                state_code<=3;
                if (write_ack_sync) begin write_req<=0; state<=ST_LOAD_RELEASE; end
            end
            ST_LOAD_RELEASE: begin
                state_code<=3;
                if (!write_ack_sync) begin frame_start<=1; state<=ST_LOAD_DATA; end
            end
            ST_LOAD_DATA: begin
                state_code<=4;
                if (source_done) begin state<=ST_IDLE; sector_requested<=0; end
                else if (decoder_busy && sector_ready && !sector_requested && current_sector<=last_file_sector) begin
                    sector_start<=1; sector_requested<=1;
                end
                if (byte_valid && byte_ready && byte_last) begin
                    current_sector<=current_sector+1'b1; sector_requested<=0;
                end
            end
            default:state<=ST_IDLE;
        endcase
    end
end
endmodule
