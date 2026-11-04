`timescale 1ns/1ps

// Real BMP parser, buffer manager, memory write FSM and fade handshake.
// Only SD-sector delivery and FIFO/SDRAM storage are controlled models.
module write_ack_case #(parameter integer PHASE_PS=0, parameter integer CASE_ID=0)
    (output reg passed=0);
    reg sd_clk=0, mem_clk=0, video_clk=0, rst=1;
    reg key_next=1, key_auto=1;
    reg drain_enable=0;
    wire req, ack, clear_fifo, write_en, mem_we, finish;
    wire [31:0] write_data;
    wire [20:0] mem_addr;
    wire [1:0] write_buf, pending_buf, pending_img;
    wire request_toggle, ready_toggle, commit_sd, done_sd;
    reg finish_toggle=0;
    wire request_video, ready_video;
    wire [3:0] payload;
    wire [1:0] display_buf;
    wire display_valid, busy, commit_video, done_video;
    wire [2:0] fade, trn;
    reg frame_pulse=0;
    integer video_count=0;
    integer fifo_count=0, wr_ptr=0, rd_ptr=0;
    reg [31:0] fifo [0:1023];
    integer reset_count=0, ack_count=0, finish_count=0, swap_count=0;
    integer accepted_pixels=0, memory_pixels=0, ready_count=0;
    reg ack_prev=0, clear_prev=0, ready_prev=0;
    reg [1:0] old_display=0;
    reg pre_frame;
    reg [2:0] pre_state;
    reg [1:0] fifo_wr_reset=2'b11, fifo_rd_reset=2'b11;
    wire [9:0] used_words=fifo_rd_reset[1] ? 10'd0 : fifo_count;

    always #5 sd_clk=~sd_clk;
    initial begin
        #(PHASE_PS/1000.0);
        forever #4 mem_clk=~mem_clk;
    end
    always #20 video_clk=~video_clk;

    sd_card_bmp #(.CLK_FREQ_HZ(1000), .SCAN_MAX_SECTOR(1),
        .SCAN_TARGET_COUNT(2), .TEST_ALLOW_SIZE(1), .OUTPUT_WIDTH(4), .OUTPUT_HEIGHT(2)) source (
        .clk(sd_clk), .rst(rst), .key_next(key_next), .key_auto(key_auto),.key_interval(1'b1),
        .cancel(1'b0), .write_ready(!fifo_wr_reset[1] && !clear_fifo),
        .bmp_width(16'd4), .bmp_height(16'd2),
        .write_finish_toggle(finish_toggle),
        .display_swap_commit_pulse(commit_sd), .transition_done_pulse(done_sd),
        .write_buf_idx(write_buf), .pending_buf_idx(pending_buf),
        .pending_image_idx(pending_img), .transition_request_toggle(request_toggle),
        .next_frame_ready_toggle(ready_toggle),
        .write_req(req), .write_req_ack(ack), .write_en(write_en),
        .write_data(write_data), .SD_MISO(1'b1), .state_code(),
        .debug_status_code(), .debug_image_number(), .debug_image_valid(),
        .osd_image_index(), .osd_auto_play_enable(), .display_valid(),
        .SD_nCS(), .SD_DCLK(), .SD_MOSI());

    frame_fifo_write #(.BURST_SIZE(4), .FRAME_WIDTH(4), .FRAME_HEIGHT(2)) writer (
        .rst(rst), .mem_clk(mem_clk), .Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(1'b0), .Sdr_busy(1'b0), .App_rd_busy(!drain_enable),
        .App_wr_en(mem_we), .App_wr_addr(mem_addr), .write_req(req),
        .write_req_ack(ack), .write_finish(finish),
        .write_addr_0(21'd0), .write_addr_1(21'd32),
        .write_addr_2(21'd0), .write_addr_3(21'd32),
        .write_addr_index(write_buf), .write_len(21'd8),
        .fifo_aclr(clear_fifo), .rdusedw(used_words), .O_wr_busy());

    fade_transition_cdc bridge (
        .src_cancel_toggle(1'b0), .dst_cancel_pulse(),
        .src_clk(sd_clk), .src_reset(rst), .src_request_toggle(request_toggle),
        .src_ready_toggle(ready_toggle), .src_pending_payload({pending_img,pending_buf}),
        .src_commit_pulse(commit_sd), .src_transition_done_pulse(done_sd),
        .dst_clk(video_clk), .dst_reset(rst), .dst_request_pulse(request_video),
        .dst_next_frame_ready(ready_video), .dst_pending_payload(payload),
        .dst_commit_pulse(commit_video), .dst_transition_done_pulse(done_video));
    fade_transition_ctrl #(.FRAMES_PER_STEP(2)) transition (
        .transition_cancel_pulse(1'b0),
        .video_clk(video_clk), .reset(rst), .frame_start_pulse(frame_pulse),
        .transition_request_pulse(request_video), .next_frame_ready(ready_video),
        .pending_buf_idx(payload[1:0]), .pending_image_idx(payload[3:2]),
        .display_buf_idx(display_buf), .display_valid(display_valid),
        .fade_level(fade), .transition_busy(busy), .transition_state(trn),
        .swap_commit_pulse(commit_video), .transition_done_pulse(done_video),
        .display_image_idx());

    always @(negedge video_clk) begin
        if(rst) begin frame_pulse=0; video_count=0; end
        else begin
            frame_pulse=(video_count==0);
            video_count=(video_count==15)?0:video_count+1;
        end
    end
    always @(posedge video_clk) begin
        pre_frame=frame_pulse; pre_state=trn;
        #0.01;
        if(!rst) begin
            if(commit_video) begin
                if(fade!==0 || !pre_frame || pre_state!==3 || finish_count<swap_count+1)
                    $fatal(1,"CASE %0d unsafe or premature buffer swap",CASE_ID);
                swap_count=swap_count+1;
                if(display_buf!==((swap_count-1)%2))
                    $fatal(1,"CASE %0d buffer order",CASE_ID);
            end
            if(display_buf!==old_display && !commit_video)
                $fatal(1,"CASE %0d buffer changed without commit",CASE_ID);
            old_display=display_buf;
        end else old_display=0;
    end

    // Behavioral queue: asynchronous clear, no pixel accepted during reset.
    // Match the supplied FIFO wrapper's two-clock synchronous reset release.
    always @(posedge sd_clk or posedge clear_fifo or posedge rst) begin
        if(rst || clear_fifo) fifo_wr_reset<=2'b11;
        else fifo_wr_reset<={fifo_wr_reset[0],1'b0};
    end
    always @(posedge mem_clk or posedge clear_fifo or posedge rst) begin
        if(rst || clear_fifo) fifo_rd_reset<=2'b11;
        else fifo_rd_reset<={fifo_rd_reset[0],1'b0};
    end
    always @(posedge clear_fifo or posedge rst) begin
        fifo_count=0; wr_ptr=0; rd_ptr=0;
    end
    always @(posedge sd_clk) begin
        if(!rst && source.bmp_read_m0.state==4 && (ack || clear_fifo))
            $fatal(1,"CASE %0d pixel-read phase entered while FIFO clear active",CASE_ID);
        if(!rst && write_en) begin
            if(clear_fifo || fifo_wr_reset[1] || ack || req || !source.completion.armed)
                $fatal(1,"CASE %0d pixel before handshake/clear completion",CASE_ID);
            fifo[wr_ptr]=write_data; wr_ptr=wr_ptr+1; fifo_count=fifo_count+1;
            accepted_pixels=accepted_pixels+1;
        end
        #0.02;
        if(!rst && ready_toggle!==ready_prev) begin
            ready_count=ready_count+1;
            if(!source.source_done_seen || finish_count<ready_count)
                $fatal(1,"CASE %0d ready before source/memory finish",CASE_ID);
        end
        ready_prev=ready_toggle;
    end
    always @(posedge mem_clk or posedge rst) begin
        if(rst) finish_toggle<=0;
        else begin
            if(finish) begin
                finish_toggle<=~finish_toggle;
                finish_count=finish_count+1;
                if(memory_pixels!==finish_count*8)
                    $fatal(1,"CASE %0d frame not fully written",CASE_ID);
            end
            if(mem_we) begin
                if(fifo_count<=0 || clear_fifo || fifo_rd_reset[1])
                    $fatal(1,"CASE %0d FIFO underrun/reset read",CASE_ID);
                if(fifo[rd_ptr]!=={8'h80+source.load_idx,8'h40,8'h20,8'h00})
                    $fatal(1,"CASE %0d stale/incorrect FIFO pixel %h",CASE_ID,fifo[rd_ptr]);
                if(mem_addr!==((finish_count%2)*32+((memory_pixels%8)<4?4:0)+(memory_pixels%4)))
                    $fatal(1,"CASE %0d pixel order/address %0d",CASE_ID,mem_addr);
                rd_ptr=rd_ptr+1; fifo_count=fifo_count-1;
                memory_pixels=memory_pixels+1;
            end
        end
        #0.01;
        if(!rst) begin
            if(ack!==clear_fifo) $fatal(1,"CASE %0d ack/clear not equivalent",CASE_ID);
            if(ack && !ack_prev) ack_count=ack_count+1;
            if(clear_fifo && !clear_prev) reset_count=reset_count+1;
        end
        ack_prev=ack; clear_prev=clear_fifo;
    end

    task press_next;
        begin
            @(negedge sd_clk); key_next=0;
            repeat(28) @(negedge sd_clk);
            key_next=1;
            repeat(28) @(negedge sd_clk);
        end
    endtask
    task complete_frame;
        input integer number;
        begin
            wait(source.bmp_read_m0.state==4);
            wait(source.bmp_ready);
            wait(source.source_done_seen);
            wait(source.scale_done_seen);
            repeat(12) @(negedge sd_clk);
            if(ready_count!==number-1 || swap_count!==number-1 || memory_pixels!==(number-1)*8)
                $fatal(1,"CASE %0d source completion advanced ready/swap",CASE_ID);
            if(fifo_count!==8) $fatal(1,"CASE %0d pixels lost before drain",CASE_ID);
            drain_enable=1;
            wait(finish_count==number);
            wait(!source.load_busy);
            @(negedge sd_clk); drain_enable=0;
            if(swap_count!==number || ready_count!==number || ack_count!==number || reset_count!==number)
                $fatal(1,"CASE %0d duplicate/missing handshake/ready/commit",CASE_ID);
        end
    endtask
    initial begin
        repeat(5) @(negedge sd_clk); #1.3; rst=0;
        complete_frame(1);
        press_next; complete_frame(2);
        press_next; complete_frame(3);
        if(accepted_pixels!==24 || memory_pixels!==24)
            $fatal(1,"CASE %0d frame pixel total",CASE_ID);
        // Reset in-flight while ack and FIFO clear are held high.
        press_next; wait(ack); #0.1; rst=1;
        #1;
        if(req || ack || clear_fifo || write_en || finish_toggle || ready_toggle || busy)
            $fatal(1,"CASE %0d reset did not clear handshake",CASE_ID);
        repeat(5) @(negedge sd_clk);
        accepted_pixels=0; memory_pixels=0; finish_count=0; swap_count=0;
        ready_count=0; ack_count=0; reset_count=0; ready_prev=0; ack_prev=0; clear_prev=0;
        #2.7; rst=0;
        complete_frame(1);
        $display("WRITE_ACK_PHASE_%0d_PASS phase_ps=%0d",CASE_ID,PHASE_PS);
        passed=1;
    end
endmodule

// Test-only SD sector model. Two 4x2/24bpp uncompressed BMP fixtures at 0/1.
// Three SD clocks per byte; no SPI or encrypted memory-controller simulation.
module sd_card_top (
    input clk,rst,SD_MISO,sd_sec_read,sd_sec_write,
    input [31:0] sd_sec_read_addr,sd_sec_write_addr,
    output SD_nCS,SD_DCLK,SD_MOSI,
    output reg sd_init_done=0,
    output reg [7:0] sd_sec_read_data=0,
    output reg sd_sec_read_data_valid=0,sd_sec_read_end=0,
    input [7:0] sd_sec_write_data,
    output sd_sec_write_data_req,sd_sec_write_end
);
    integer pos=0, pace=0, init_count=0;
    reg active=0;
    reg [31:0] sector;
    assign SD_nCS=1; assign SD_DCLK=0; assign SD_MOSI=0;
    assign sd_sec_write_data_req=0; assign sd_sec_write_end=0;
    function [7:0] byte_at;
        input integer n;
        input [31:0] s;
        begin
            byte_at=0;
            case(n)
                0:byte_at="B"; 1:byte_at="M"; 2:byte_at=78;
                10:byte_at=54; 14:byte_at=40; 18:byte_at=4;
                22:byte_at=2; 26:byte_at=1; 28:byte_at=24;
                default:if(n>=54 && n<78) begin
                    case((n-54)%3)
                        0:byte_at=8'h20;
                        1:byte_at=8'h40;
                        2:byte_at=8'h80+s[7:0];
                    endcase
                end
            endcase
        end
    endfunction
    always @(posedge clk) begin
        sd_sec_read_data_valid<=0; sd_sec_read_end<=0;
        if(rst) begin
            sd_init_done<=0; init_count=0; active=0; pos=0; pace=0;
        end else begin
            if(init_count<5) init_count=init_count+1; else sd_init_done<=1;
            if(!active && sd_sec_read && !sd_sec_read_end) begin
                active=1; sector=sd_sec_read_addr; pos=0; pace=0;
            end else if(active) begin
                if(pace==2) begin
                    pace=0;
                    if(pos<512) begin
                        sd_sec_read_data<=byte_at(pos,sector);
                        sd_sec_read_data_valid<=1;
                        pos=pos+1;
                    end else begin sd_sec_read_end<=1; active=0; end
                end else pace=pace+1;
            end
        end
    end
endmodule

module tb_write_ack;
    wire [3:0] passed;
    write_ack_case #(.PHASE_PS(0),.CASE_ID(0)) c0(passed[0]);
    write_ack_case #(.PHASE_PS(500),.CASE_ID(1)) c1(passed[1]);
    write_ack_case #(.PHASE_PS(1900),.CASE_ID(2)) c2(passed[2]);
    write_ack_case #(.PHASE_PS(3900),.CASE_ID(3)) c3(passed[3]);
    initial begin
        wait(&passed);
        $display("WRITE_ACK_TEST_PASS");
        $finish;
    end
    initial begin #2000000; $fatal(1,"WRITE_ACK_TIMEOUT"); end
endmodule
