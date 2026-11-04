`timescale 1ns/1ps
// Actual parser/buffer manager/scaler, unchanged FIFO IP and writer, fade CDC.
// Only the SPI packet source and SDRAM chip are behavioral models.
module tb_image_scaling;
    reg clk=0, mem_clk=0, video_clk=0, rst=1, cancel=0;
    always #5 clk=~clk;
    initial begin #1.9; forever #4 mem_clk=~mem_clk; end
    always #20 video_clk=~video_clk;
    reg key_next=1;
    wire req, ack, we, wr_ready, finish, app_we;
    wire [31:0] data, app_data;
    wire [20:0] addr;
    wire [1:0] bank, pending_bank, pending_image;
    wire req_toggle, ready_toggle, cancel_toggle, commit_sd, done_sd;
    wire req_video, ready_video, cancel_video, commit_video, done_video;
    wire [3:0] payload;
    wire [2:0] fade, state;
    wire [1:0] display_bank;
    wire display_valid, busy;
    reg finish_toggle=0, frame_pulse=0, memory_block=0;
    reg random_block_enable=0;
    reg [31:0] random_seed=32'hCA751023;
    integer video_count=0, transaction=0, accepted=0, written=0;
    integer swaps=0, finishes=0, ready_events=0, full_cycles=0;
    integer sd_requests=0, mem_x, mem_y, sx, sy, expected_addr;
    reg old_ready=0, old_bank=0, prev_frame;
    reg [2:0] prev_state;
    reg [23:0] expected_rgb, checked_rgb;
    reg [20:0] checked_addr;
    reg stalled=0;
    reg [43:0] held;
    reg inject_pixel=0, inject_coord=0, inject_count=0;
    wire [7:0] debug_code;
    // Model a long read-side arbitration grant, not an SDRAM data stall.
    // The unchanged writer does not use Sdr_busy to pause accepted bursts.
    initial force memory_path.App_rd_busy=memory_block || (random_block_enable && random_seed[3:0]==0);
    always @(negedge mem_clk) random_seed={random_seed[30:0],random_seed[31]^random_seed[21]^random_seed[1]^random_seed[0]};

    sd_card_bmp #(.CLK_FREQ_HZ(1000), .SCAN_TARGET_COUNT(3)) source (
        .clk(clk), .rst(rst), .cancel(cancel), .key_next(key_next), .key_auto(1'b1),.key_interval(1'b1),
        .bmp_width(16'd640), .bmp_height(16'd480), .write_finish_toggle(finish_toggle),
        .display_swap_commit_pulse(commit_sd), .transition_done_pulse(done_sd),
        .write_buf_idx(bank), .pending_buf_idx(pending_bank), .pending_image_idx(pending_image),
        .transition_request_toggle(req_toggle), .next_frame_ready_toggle(ready_toggle),
        .transition_cancel_toggle(cancel_toggle), .write_req(req), .write_req_ack(ack),
        .write_ready(wr_ready), .write_en(we), .write_data(data),
        .SD_MISO(1'b1), .SD_nCS(), .SD_DCLK(), .SD_MOSI(),
        .state_code(), .debug_status_code(debug_code), .debug_image_number(), .debug_image_valid(),
        .osd_image_index(), .osd_auto_play_enable(), .display_valid());
    frame_read_write memory_path (
        .rst(rst), .mem_clk(mem_clk), .Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(1'b0), .Sdr_busy(memory_block),
        .App_rd_en(), .App_rd_addr(), .Sdr_rd_en(1'b0), .Sdr_rd_dout(32'd0),
        .read_clk(video_clk), .read_req(1'b0), .read_req_ack(), .read_finish(),
        .read_addr_0(21'd0), .read_addr_1(21'd0), .read_addr_2(21'd0), .read_addr_3(21'd0),
        .read_addr_index(2'd0), .read_len(21'd307200), .read_en(1'b0), .read_data(),
        .App_wr_en(app_we), .App_wr_addr(addr), .App_wr_din(app_data), .App_wr_dm(),
        .write_clk(clk), .write_req(req), .write_req_ack(ack), .write_ready(wr_ready),
        .write_finish(finish), .write_addr_0(21'd0), .write_addr_1(21'd307200),
        .write_addr_2(21'd0), .write_addr_3(21'd307200), .write_addr_index(bank),
        .write_len(21'd307200), .write_en(we), .write_data(data));
    fade_transition_cdc bridge (
        .src_clk(clk), .src_reset(rst), .src_request_toggle(req_toggle),
        .src_ready_toggle(ready_toggle), .src_cancel_toggle(cancel_toggle),
        .src_pending_payload({pending_image,pending_bank}), .src_commit_pulse(commit_sd),
        .src_transition_done_pulse(done_sd), .dst_clk(video_clk), .dst_reset(rst),
        .dst_request_pulse(req_video), .dst_cancel_pulse(cancel_video),
        .dst_next_frame_ready(ready_video), .dst_pending_payload(payload),
        .dst_commit_pulse(commit_video), .dst_transition_done_pulse(done_video));
    fade_transition_ctrl #(.FRAMES_PER_STEP(1)) transition (
        .video_clk(video_clk), .reset(rst), .frame_start_pulse(frame_pulse),
        .transition_request_pulse(req_video), .transition_cancel_pulse(cancel_video),
        .next_frame_ready(ready_video), .pending_buf_idx(payload[1:0]), .pending_image_idx(payload[3:2]),
        .display_buf_idx(display_bank), .display_image_idx(), .display_valid(display_valid),
        .fade_level(fade), .transition_busy(busy), .transition_state(state),
        .swap_commit_pulse(commit_video), .transition_done_pulse(done_video));

    // Independent mathematical RGB fixture: asymmetric R/G gradients, checker
    // tiles, corners and a center marker prevent flips/channel/order ambiguity.
    function [23:0] reference_color;
        input integer w,h,x,y;
        reg [7:0] r,g,b;
        begin
            r=(x*251/(w-1)); g=(y*247/(h-1)); b=((x/7+y/11)%2)?8'hD3:8'h29;
            if(x==0 && y==0) begin r=255;g=0;b=0;end
            if(x==w-1 && y==0) begin r=0;g=255;b=0;end
            if(x==0 && y==h-1) begin r=0;g=0;b=255;end
            if(x==w-1 && y==h-1) begin r=255;g=255;b=255;end
            if(x==w/2 && y==h/2) begin r=8'h12;g=8'hAB;b=8'hCD;end
            reference_color={r,g,b};
        end
    endfunction
    function integer source_w; input integer n; begin case(n) 0:source_w=320;1:source_w=640;default:source_w=800;endcase end endfunction
    function integer source_h; input integer n; begin case(n) 0:source_h=240;1:source_h=480;default:source_h=600;endcase end endfunction

    always @(negedge video_clk) begin
        if(rst) begin frame_pulse=0;video_count=0;end
        else begin frame_pulse=(video_count==0);video_count=(video_count+1)%40;end
    end
    always @(posedge video_clk) begin
        prev_frame=frame_pulse;prev_state=state;
        #0.02;
        if(!rst) begin
            if(commit_video) begin
                if(fade!==0 || !prev_frame || prev_state!==3 || written!=307200 ||
                   !source.source_done_seen || !source.scale_done_seen || !source.memory_done_seen)
                    $fatal(1,"BUFFER_SWAP_WHILE_NONBLACK_OR_INCOMPLETE");
                swaps=swaps+1;
                if(display_bank!==bank) $fatal(1,"wrong display bank");
            end
            if(display_bank!==old_bank && !commit_video) $fatal(1,"uncommitted bank change");
            old_bank=display_bank;
        end else old_bank=0;
    end
    always @(posedge clk) begin
        if(!rst) begin
            if(!wr_ready && source.scaled_valid) full_cycles=full_cycles+1;
            if(source.scaler.state==2 && (source.scaler.sample_x>=source.source_width ||
               source.scaler.sample_x>=800 || source.scaler.input_row<=source.scaler.sample_row))
                $fatal(1,"invalid/incomplete line RAM read");
            if(stalled && {source.scaled_data,source.scaler.out_x,source.scaler.out_row}!==held)
                $fatal(1,"scaler changed held pixel/coordinates under backpressure");
            stalled=source.scaled_valid && !wr_ready && !cancel;
            held={source.scaled_data,source.scaler.out_x,source.scaler.out_row};
            if(we) begin
                if(memory_path.write_fifo_full || memory_path.write_buf.wr_rst || ack || req ||
                   (display_valid && bank==display_bank))
                    $fatal(1,"FIFO overflow or write before handshake release");
                accepted=accepted+1;
                if(accepted>307200) $fatal(1,"extra scaled output");
            end
        end else stalled=0;
        #0.03;
        if(!rst && ready_toggle!==old_ready) begin
            ready_events=ready_events+1;
            if(written!=307200 || accepted!=307200 || finishes!=ready_events)
                $fatal(1,"next_frame_ready before complete SDRAM frame");
        end
        old_ready=ready_toggle;
    end
    always @(posedge mem_clk) begin
        if(rst) finish_toggle<=0;
        else begin
            if(app_we) begin
                if(memory_path.write_buf.empty_flag || memory_path.write_buf.rd_rst)
                    $fatal(1,"real FIFO underflow/reset read");
                // Negative COUNT models a duplicated accepted-write count.
                if(inject_count && written==123) written=written+1;
                mem_x=written%640;mem_y=479-written/640;
                sx=((2*mem_x+1)*source_w(transaction))/(2*640);
                sy=((2*mem_y+1)*source_h(transaction))/(2*480);
                expected_rgb=reference_color(source_w(transaction),source_h(transaction),sx,sy);
                expected_addr=bank*307200+mem_y*640+mem_x;
                checked_rgb=app_data[31:8]; checked_addr=addr;
                if(inject_pixel && written==123) checked_rgb=checked_rgb^24'd1;
                if(inject_coord && written==123) checked_addr=checked_addr+1;
                if(checked_addr!==expected_addr || checked_rgb!==expected_rgb || app_data[7:0]!==0) begin
                    $display("SCALING_CHECKER_REJECT frame=%0d pixel=%0d addr=%0d/%0d RGB=%h/%h",transaction,written,checked_addr,expected_addr,checked_rgb,expected_rgb);
                    $fatal(1,"per-pixel SDRAM address/RGB mismatch");
                end
                if(written>=307200 || written>=accepted) $fatal(1,"extra/out-of-order SDRAM pixel");
                written=written+1;
            end
            if(finish) begin
                if(written!=307200) $fatal(1,"early memory_done");
                finish_toggle<=~finish_toggle;finishes=finishes+1;
            end
        end
    end
    task next_key;
        begin @(negedge clk);key_next=0;repeat(28)@(negedge clk);key_next=1;repeat(28)@(negedge clk);end
    endtask
    always @(posedge ack) if(!rst)begin accepted=0;written=0;end
    initial begin
        inject_pixel=$test$plusargs("INJECT_PIXEL");inject_coord=$test$plusargs("INJECT_COORD");inject_count=$test$plusargs("INJECT_COUNT");
        repeat(7)@(negedge clk);rst=0;
        for(transaction=0;transaction<3;transaction=transaction+1) begin
            accepted=0;written=0;memory_block=1;random_block_enable=0;
            if(transaction!=0) next_key;
            // Fill the REAL 511-word FIFO and hold it full for 2000 clocks.
            wait(memory_path.write_fifo_full);repeat(2000)@(negedge clk);
            if(accepted!=511 || written!=0 || ready_events!=transaction || swaps!=transaction)
                $fatal(1,"FIFO full did not backpressure the entire chain");
            memory_block=0;random_block_enable=1;
            wait(swaps==transaction+1);wait(!source.load_busy);
            repeat(30)@(negedge clk);
            if(accepted!=307200 || written!=307200 || finishes!=transaction+1 || ready_events!=transaction+1)
                $fatal(1,"missing/duplicate completion");
            $display("IMAGE_SCALING_%0dx%0d_PASS pixels=307200 all SDRAM addresses/RGB verified",source_w(transaction),source_h(transaction));
        end
        transaction=0;accepted=0;written=0;
        next_key;wait(source.bmp_read_m0.sector_buffer.state==1);
        @(negedge clk);cancel=1;@(negedge clk);cancel=0;
        wait(!source.load_busy);repeat(80)@(negedge video_clk);
        if(busy || swaps!=3 || debug_code!=8'hEF) $fatal(1,"cancel failed / swapped buffer");
        wait(source.bmp_ready);next_key;
        wait(written>=512);memory_block=1;
        @(negedge clk);cancel=1;@(negedge clk);cancel=0;
        wait(!source.load_busy);wait(source.bmp_ready);repeat(100)@(negedge mem_clk);
        repeat(80)@(negedge video_clk);
        if(busy||swaps!=3||ready_events!=3)$fatal(1,"cancel partial SDRAM frame published ready");
        next_key;wait(ack);wait(source.frame_start);
        memory_block=0;
        wait(swaps==4);wait(!source.load_busy);
        if(accepted!=307200||written!=307200||ready_events!=4||finishes!=4)
            $fatal(1,"retry after partial cancel mixed transactions");
        $display("IMAGE_SCALING_CANCEL_RETRY_PASS complete frame after partial SDRAM write");
        // Reset the COMPLETE real-FIFO/manager/CDC pipeline while the next
        // image is stalled at FIFO full, then verify a fresh full boot frame.
        transaction=1;memory_block=1;next_key;wait(memory_path.write_fifo_full);
        @(negedge clk);rst=1;key_next=1;cancel=0;
        repeat(12)@(negedge video_clk);
        accepted=0;written=0;finishes=0;swaps=0;ready_events=0;old_ready=0;old_bank=0;
        transaction=0;memory_block=0;rst=0;
        wait(swaps==1);wait(!source.load_busy);
        if(accepted!=307200||written!=307200||finishes!=1||ready_events!=1)
            $fatal(1,"global reset retained partial FIFO/transaction data");
        $display("IMAGE_SCALING_GLOBAL_RESET_PASS complete frame after reset while FIFO full");
        if(full_cycles<6000) $fatal(1,"long FIFO stall not exercised");
        $display("IMAGE_SCALING_TEST_PASS full_stall_cycles=%0d",full_cycles);$finish;
    end
    initial begin #400000000;
        $display("timeout parser=%0d scaler=%0d accepted=%0d written=%0d scan=%0d error=%h",source.bmp_read_m0.state,source.scaler.state,accepted,written,source.scan_done,debug_code);
        $fatal(1,"IMAGE_SCALING_TIMEOUT");end
endmodule

// Packet delivery model: no pause within an active CMD17 requested by upstream.
// SD response and byte gaps are deterministic irregular delays (repeatable).
module sd_card_top (
    input clk,rst, input SD_MISO, output SD_nCS,SD_DCLK,SD_MOSI,
    output reg sd_init_done=0, input sd_sec_read, input [31:0] sd_sec_read_addr,
    output reg [7:0] sd_sec_read_data=0, output reg sd_sec_read_data_valid=0,sd_sec_read_end=0,
    input sd_sec_write,input [31:0] sd_sec_write_addr,
    output [7:0] sd_sec_write_data,output sd_sec_write_data_req,sd_sec_write_end
);
    assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=0;
    assign sd_sec_write_data=0;assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
    integer byte_index=0,delay_count=0,address=0,sequence_number=0;
    reg active=0;
    reg [31:0] rng=32'h1234CAFE;
    function [7:0] file_byte;
        input integer sector,offset;
        integer n,base,w,h,pixel_offset,length,stride,pos,row,col,component;
        reg [23:0] rgb;
        reg [31:0] field;
        begin
            if(sector<451)begin n=0;base=0;w=320;h=240;pixel_offset=511;end
            else if(sector<2254)begin n=1;base=451;w=640;h=480;pixel_offset=1025;end
            else begin n=2;base=2254;w=800;h=600;pixel_offset=54;end
            pos=(sector-base)*512+offset;stride=((w*3+3)/4)*4;length=pixel_offset+stride*h;
            file_byte=0;field=0;
            case(pos)
                0:file_byte="B";1:file_byte="M";
                2,3,4,5:begin field=length;file_byte=field>>((pos-2)*8);end
                10,11,12,13:begin field=pixel_offset;file_byte=field>>((pos-10)*8);end
                14:file_byte=40;
                18,19,20,21:begin field=w;file_byte=field>>((pos-18)*8);end
                22,23,24,25:begin field=h;file_byte=field>>((pos-22)*8);end
                26:file_byte=1;28:file_byte=24;
                default: if(pos>=pixel_offset && pos<length) begin
                    pos=pos-pixel_offset;row=pos/stride;col=(pos%stride)/3;component=pos%3;
                    rgb=tb_image_scaling.reference_color(w,h,col,h-1-row);
                    case(component)0:file_byte=rgb[7:0];1:file_byte=rgb[15:8];2:file_byte=rgb[23:16];endcase
                end
            endcase
        end
    endfunction
    always @(posedge clk) begin
        if(rst)begin active<=0;sd_init_done<=0;sd_sec_read_data_valid<=0;sd_sec_read_end<=0;delay_count<=0;rng<=32'h1234CAFE;end
        else begin
            rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            sd_init_done<=1;sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
            if(!active && sd_sec_read && !sd_sec_read_end) begin
                active<=1;address=sd_sec_read_addr;byte_index=0;delay_count=(sequence_number%11)+2;sequence_number=sequence_number+1;
            end else if(active) begin
                if(delay_count>0)delay_count=delay_count-1;
                else if(byte_index==512)begin active<=0;sd_sec_read_end<=1;end
                else begin
                    sd_sec_read_data<=file_byte(address,byte_index);sd_sec_read_data_valid<=1;
                    byte_index=byte_index+1;delay_count=(rng[2:0]==0)?3:0;
                end
            end
        end
    end
endmodule
