
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,
    parameter TEST_ALLOW_SIZE = 0,
    parameter ALLOW_720P = 0,
    parameter GENERIC_SCALE = 0,
    parameter SCALE_MODE = 0,
    parameter KEY_EVENTS=0,
    parameter OUTPUT_WIDTH = 640,
    parameter OUTPUT_HEIGHT = 480,
    parameter integer SD_TIMEOUT_CYCLES = 10000000,
    // Preserve the reusable legacy module's 1s default; the board top selects
    // code 2 (5s). Existing protocol regressions therefore retain their timing.
    parameter [1:0] DEFAULT_INTERVAL_CODE = 2'd0,
    // Opt-in: fill only the non-displayed buffer during an AUTO dwell.
    // Legacy callers keep their original request/load protocol unchanged.
    parameter PREFETCH_ENABLE = 0,
    parameter GUARD_VIDEO_BUSY = 0
)(
    input                       clk,
    input                       rst,
    input                       cancel,
    input                       key_next,
    input                       key_auto,
    input wire                  key_interval,
    input wire                  key_auto_event,key_interval_event,
    input wire                  video_busy_observed,
    output reg [43:0]           osd_scaling_meta,
    output [1:0]                osd_interval_code,
    output [9:0]                playback_progress,
    output [7:0]                playback_error,
    output [3:0]                state_code,
    output [7:0]                debug_status_code,
    output [3:0]                debug_image_number,
    output                      debug_image_valid,
    output [1:0]                osd_image_index,
    output                      osd_auto_play_enable,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,

    input                       write_finish_toggle,
    input                       display_swap_commit_pulse,
    input                       transition_done_pulse,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            pending_buf_idx,
    output [1:0]                pending_image_idx,
    output reg                  transition_request_toggle,
    output reg                  next_frame_ready_toggle,
    output reg                  transition_cancel_toggle,

    output                      write_req,
    input                       write_req_ack,
    input                       write_ready,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire key_next_press;
wire key_auto_press;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        disp_buf_idx;         // SD域镜像：最近一次已提交显示的缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg              next_req_pending;
reg              load_busy;
reg              frame_ready_waiting;
reg              transition_commit_seen;
reg              transition_requested;
reg              frame_complete_latched;

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
wire             source_done_seen;
wire             scale_done_seen, memory_done_seen, completion_ready;
wire             source_done, scale_done, frame_start, load_error;
wire [7:0]       error_code, normal_debug_status;
reg [7:0]        latched_error;
// Publishing ready is irrevocable: all three completion events have already
// arrived. Late cancel/error notifications must not strand the SD mirror while
// the video domain commits a complete frame. K1 still resets every domain.
wire commit_in_flight = frame_ready_waiting || transition_commit_seen;
wire transaction_abort = (cancel || load_error) && !commit_in_flight;
wire [(ALLOW_720P?11:10)-1:0] source_width, source_height;
wire             pixel_ready, scaled_valid;
wire [23:0]      scaled_data;
wire [10:0] scaled_content_width,scaled_content_height;
reg [43:0] pending_scaling_meta;
wire [10:0] metadata_source_width=source_width;
wire [10:0] metadata_source_height=source_height;
always @(posedge clk or posedge rst)begin
    if(rst)begin osd_scaling_meta<=0;pending_scaling_meta<=0;end
    else begin
        // Only a fully guarded transaction can reach display commit. Leaving
        // abandoned metadata unobserved avoids adding 44 loads to the hot
        // load_error/cancel net; the next guarded completion replaces it.
        if(completion_ready)pending_scaling_meta<=
            {metadata_source_width,metadata_source_height,scaled_content_width,scaled_content_height};
        if(display_swap_commit_pulse)osd_scaling_meta<=pending_scaling_meta;
    end
end

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
wire interval_press;
wire timer_enable = sd_init_done && scan_done && auto_play_en && display_valid &&
                    (!GUARD_VIDEO_BUSY || !video_busy_observed) &&
                    (PREFETCH_ENABLE ? !transition_requested : !load_busy) &&
                    !next_req_pending && first_image_committed &&
                    (img_found_count > 3'd1) && latched_error==0;
wire auto_advance = auto_tick && !key_auto_press && !key_next_press && !interval_press;
wire [1:0] next_from_current;

assign write_en   = scaled_valid && write_ready;
assign write_data = {scaled_data,8'b0};
assign debug_status_code = latched_error!=0 ? latched_error : normal_debug_status;
assign playback_error = latched_error;
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign osd_image_index = img_idx;
assign osd_auto_play_enable = auto_play_en;
assign pending_image_idx = load_idx;

playback_interval_control #(.CLK_FREQ_HZ(CLK_FREQ_HZ),
    .EXTERNAL_EVENTS(KEY_EVENTS),
    .DEFAULT_INTERVAL_CODE(DEFAULT_INTERVAL_CODE)) interval_control (
    .clk(clk),.reset(rst),.key_interval(key_interval),.key_event(key_interval_event),
    .timer_enable(timer_enable),
    .timer_restart(key_auto_press || key_next_press || cancel ||
                   (load_start_pulse && (!PREFETCH_ENABLE || transition_requested))),
    .interval_code(osd_interval_code),.interval_press(interval_press),.auto_tick(auto_tick),
    .progress_running(playback_progress[9]),.progress_units(playback_progress[8:0]));

wire raw_auto_press;
assign key_auto_press=KEY_EVENTS?key_auto_event:raw_auto_press;
key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(raw_auto_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

function [1:0] next_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: next_index_limited = 2'd0;
            3'd1: next_index_limited = 2'd0;
            3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : (cur + 2'd1);
            3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : (cur + 2'd1);
            default: next_index_limited = (cur == 2'd3) ? 2'd0 : (cur + 2'd1);
        endcase
    end
endfunction

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        frame_ready_waiting   <= 1'b0;
        transition_commit_seen<= 1'b0;
        transition_requested  <= 1'b0;
        frame_complete_latched<= 1'b0;
        latched_error         <= 0;
        transition_cancel_toggle <= 0;
        display_valid         <= 1'b0;
        transition_request_toggle <= 1'b0;
        next_frame_ready_toggle   <= 1'b0;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            next_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            frame_ready_waiting   <= 1'b0;
            transition_commit_seen<= 1'b0;
            transition_requested  <= 1'b0;
            frame_complete_latched<= 1'b0;
            display_valid         <= 1'b0;
        end else begin
            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    default: ;
                endcase

                if (img_found_count < 3'd4)
                    img_found_count <= img_found_count + 3'd1;
            end

            // 整帧真正写完后只发布 ready；显示提交由视频域黑场帧边界决定。
            if (load_busy && completion_ready)
                frame_complete_latched <= 1'b1;
            // A completed speculative load is NOT permission to start fading.
            // Keep the bundle stable until an actual manual/deadline request.
            if (load_busy && (completion_ready || frame_complete_latched) &&
                (!PREFETCH_ENABLE || transition_requested) && !frame_ready_waiting &&
                !transition_commit_seen &&
                !load_error && !cancel) begin
                frame_ready_waiting     <= 1'b1;
                next_frame_ready_toggle <= ~next_frame_ready_toggle;
            end

            // 视频域完成黑场换帧后才提交 SD 域的显示镜像和图片编号。
            if (load_busy && frame_ready_waiting && display_swap_commit_pulse) begin
                frame_ready_waiting   <= 1'b0;
                transition_commit_seen<= 1'b1;
                frame_complete_latched<= 1'b0;
                disp_buf_idx          <= pending_buf_idx;
                img_idx               <= load_idx;
                display_valid         <= 1'b1;
                first_image_committed <= 1'b1;
            end

            // busy covers the entire fade-in; only the video-domain done event
            // releases the source side for another manual or automatic load.
            if (load_busy && transition_commit_seen && transition_done_pulse) begin
                load_busy              <= 1'b0;
                transition_commit_seen <= 1'b0;
                transition_requested   <= 1'b0;
                frame_complete_latched <= 1'b0;
            end

            // 上电后自动发起一次“扫描前 4 张 BMP”
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                next_req_pending      <= 1'b0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                frame_ready_waiting   <= 1'b0;
                transition_commit_seen<= 1'b0;
                transition_requested  <= 1'b0;
                frame_complete_latched<= 1'b0;
            end else begin
                // 转场/加载 busy 时忽略额外 next；第一版不建立请求队列。
                if (key_next_press && scan_done && bmp_ready && !load_busy &&
                    (!GUARD_VIDEO_BUSY || !video_busy_observed) &&
                    (display_valid || latched_error!=0) &&
                    (img_found_count > 3'd0))
                    next_req_pending <= 1'b1;

                // 自动播放开/关
                if (key_auto_press && scan_done && (img_found_count > 3'd1)) begin
                    auto_play_en <= ~auto_play_en;
                end

                // An AUTO preload may still be running, or already be complete.
                // K2 and the real timer consume THAT same transaction exactly
                // once. Other requests during a visible transition stay ignored.
                if (PREFETCH_ENABLE && load_busy && !transition_requested &&
                    display_valid && latched_error==0 && !cancel && !load_error &&
                    (key_next_press || (auto_play_en && auto_advance))) begin
                    transition_requested <= 1'b1;
                    transition_request_toggle <= ~transition_request_toggle;
                end

                // 首图自动加载到 buffer0
                if (scan_done && !first_image_committed && bmp_ready && !load_busy &&
                    (latched_error==0 || next_req_pending) && (img_found_count != 3'd0)) begin
                    load_idx         <= 2'd0;
                    load_sector      <= img_sector0;
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    frame_ready_waiting <= 1'b0;
                    transition_commit_seen <= 1'b0;
                    transition_requested <= 1'b1;
                    frame_complete_latched <= 1'b0;
                    latched_error    <= 0;
                    next_req_pending <= 1'b0;
                    transition_request_toggle <= ~transition_request_toggle;
                end
                // 手动和自动请求统一进入同一个加载/转场入口。
                else if (scan_done && bmp_ready && display_valid && !load_busy &&
                         (img_found_count != 3'd0) &&
                         (next_req_pending ||
                          (auto_play_en && auto_advance && (img_found_count > 3'd1)))) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    frame_ready_waiting <= 1'b0;
                    transition_commit_seen <= 1'b0;
                    transition_requested <= 1'b1;
                    frame_complete_latched <= 1'b0;
                    latched_error    <= 0;
                    next_req_pending <= 1'b0;
                    transition_request_toggle <= ~transition_request_toggle;
                end
                else if (PREFETCH_ENABLE && timer_enable && bmp_ready &&
                         !load_busy && !next_req_pending && !key_next_press &&
                         !key_auto_press && !interval_press && !auto_tick &&
                         !cancel && !load_error) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    frame_ready_waiting <= 1'b0;
                    transition_commit_seen <= 1'b0;
                    transition_requested <= 1'b0;
                    frame_complete_latched <= 1'b0;
                end
            end
            // A scan which found no supported BMP has a real, bounded outcome,
            // not an indefinitely ambiguous LOADING state. Do not race the
            // final scan_found_valid pulse that updates img_found_count.
            if (scan_done && !scan_found_valid && img_found_count==0 && latched_error==0)
                latched_error <= 8'hE4;
            // Before ready, rejected/cancelled data can never publish/commit.
            // After ready the data is complete; let the existing black commit
            // and done acknowledgement finish, preserving both domain mirrors.
            // No automatic retry or guessed-sector skip is performed.
            if (transaction_abort && (load_error || load_busy)) begin
                latched_error <= load_error ? error_code : 8'hEF;
                if (load_busy) transition_cancel_toggle <= ~transition_cancel_toggle;
                load_busy <= 0;
                load_start_pulse <= 0;
                scan_start_pulse <= 0;
                frame_ready_waiting <= 0;
                transition_commit_seen <= 0;
                transition_requested <= 0;
                frame_complete_latched <= 0;
                next_req_pending <= 0;
                auto_play_en <= 0;
            end
        end
    end
end

debug_status debug_status_m0 (
    .clk                 (clk),
    .rst                 (rst),
    .sd_init_done        (sd_init_done),
    .scan_active         (scan_kicked && !scan_done),
    .scan_done           (scan_done),
    .bmp_found           (img_found_count != 3'd0),
    .found_count         (img_found_count),
    .load_busy           (load_busy),
    .source_done_seen    (source_done_seen),
    .display_valid       (display_valid),
    .auto_play_en        (auto_play_en),
    .display_image_index (img_idx),
    .load_image_index    (load_idx),
    .status_code         (normal_debug_status),
    .image_number        (debug_image_number),
    .image_number_valid  (debug_image_valid)
);

bmp_read #(.TEST_ALLOW_SIZE(TEST_ALLOW_SIZE), .ALLOW_720P(ALLOW_720P),.GENERIC_SIZE(GENERIC_SCALE),
    .SECTOR_TIMEOUT_CYCLES(SD_TIMEOUT_CYCLES)) bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .cancel                 (cancel),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data),
    .pixel_ready            (pixel_ready),
    .pixel_row_last         (),
    .source_width           (source_width),
    .source_height          (source_height),
    .frame_start            (frame_start),
    .source_done            (source_done),
    .load_error             (load_error),
    .error_code             (error_code)
);

wire legacy_pixel_ready,legacy_scaled_valid,legacy_scale_done;
wire [23:0] legacy_scaled_data;
generate if(GENERIC_SCALE)begin:g_generic
image_scaler_generic #(.OUT_WIDTH(OUTPUT_WIDTH),.OUT_HEIGHT(OUTPUT_HEIGHT),.MODE(SCALE_MODE)) scaler(
    .content_width(scaled_content_width),.content_height(scaled_content_height),
    .clk(clk),.reset(rst),.cancel(transaction_abort || !sd_init_done),
    .start(frame_start),.source_width(source_width),.source_height(source_height),
    .in_rgb(bmp_data),.in_valid(bmp_data_wr_en),.in_ready(pixel_ready),
    .out_rgb(scaled_data),.out_valid(scaled_valid),.out_ready(write_ready),
    .out_x(),.out_row(),.scale_done(scale_done),.busy());
end else begin:g_legacy
assign scaled_content_width=OUTPUT_WIDTH;
assign scaled_content_height=OUTPUT_HEIGHT;
assign pixel_ready=legacy_pixel_ready;
assign scaled_data=legacy_scaled_data;
assign scaled_valid=legacy_scaled_valid;
assign scale_done=legacy_scale_done;
end endgenerate
// Keep the legacy instance hierarchy for unmodified historical assertions.
// In the opt-in generic build its outputs are unused and synthesis removes it.
image_scaler #(.OUT_WIDTH(OUTPUT_WIDTH), .OUT_HEIGHT(OUTPUT_HEIGHT)) scaler (
    .clk(clk), .reset(rst), .cancel(transaction_abort || !sd_init_done),
    .start(GENERIC_SCALE?1'b0:frame_start), .source_width(source_width), .source_height(source_height),
    .in_rgb(bmp_data), .in_valid(GENERIC_SCALE?1'b0:bmp_data_wr_en), .in_ready(legacy_pixel_ready),
    .out_rgb(legacy_scaled_data), .out_valid(legacy_scaled_valid), .out_ready(write_ready),
    .out_x(), .out_row(), .scale_done(legacy_scale_done), .busy()
);
frame_completion_guard completion (
    .clk(clk), .reset(rst), .start(load_start_pulse),
    .cancel(transaction_abort || !sd_init_done), .memory_arm(frame_start),
    .source_done(source_done), .scale_done(scale_done), .memory_done(write_finish_pulse),
    .source_seen(source_done_seen), .scale_seen(scale_done_seen), .memory_seen(memory_done_seen),
    .ready_pulse(completion_ready)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
