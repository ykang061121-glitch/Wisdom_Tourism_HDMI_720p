`timescale 1ns/1ps

// Real FIFO wrappers (including Gray-pointer CDC/BRAM behavioral RTL), real
// read/write FSMs, and a test-only two-cycle memory-response model.
module tb_memory_arbitration;
    localparam integer WORDS=768, BURST=256, READ_BASE=8192;
    reg mem_clk=0, source_clk=0, pixel_clk=0, rst=1;
    always #4 mem_clk=~mem_clk;
    always #5 source_clk=~source_clk;
    always #20 pixel_clk=~pixel_clk;
    reg write_req=0, read_req=0, source_en=0, pixel_en=0;
    reg [31:0] source_data=0;
    reg [1:0] bank=0;
    wire write_ack, read_ack, write_finish, read_finish, wr_busy, rd_busy;
    wire wr_en, rd_en, wr_clear, rd_clear, wf_full, wf_empty, rf_full, rf_empty;
    wire [20:0] wr_addr, rd_addr;
    wire [31:0] wf_data, rf_data;
    wire [8:0] wf_used, rf_used;
    wire ref_ack, ref_finish, ref_busy, ref_en, ref_clear;
    wire [20:0] ref_addr;
    reg [1:0] response_valid=0;
    reg [31:0] response0=0, response1=0;
    reg [31:0] memory [0:9215];
    integer produced=0, written=0, commanded=0, consumed=0;
    integer write_finishes=0, read_finishes=0, epoch=0;
    integer overlap_requests=0, write_blocks_read=0, read_blocks_write=0;
    integer write_burst_starts=0, read_burst_starts=0;
    integer consecutive_source_beats=0, source_gaps=0, max_wf_used=0;
    reg previous_source_en=0;
    reg previous_wbusy=0, previous_rbusy=0;
    reg monitor_enable=0;
    integer expected_addr;

    wfifo_32_32_512 wf (
        .rst(wr_clear), .clkw(source_clk), .clkr(mem_clk),
        .we(source_en), .re(wr_en), .di(source_data), .dout(wf_data),
        .full_flag(wf_full), .empty_flag(wf_empty), .rdusedw(wf_used),
        .wrusedw(), .afull(), .aempty(), .valid());
    rfifo_32_32_512 rf (
        .rst(rd_clear), .clkw(mem_clk), .clkr(pixel_clk),
        .we(response_valid[1]), .re(pixel_en), .di(response1), .dout(rf_data),
        .full_flag(rf_full), .empty_flag(rf_empty), .wrusedw(rf_used),
        .rdusedw(), .afull(), .aempty(), .valid());

    frame_fifo_write #(.BURST_SIZE(BURST), .FRAME_WIDTH(256), .FRAME_HEIGHT(3)) writer (
        .rst(rst), .mem_clk(mem_clk), .Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(1'b0), .Sdr_busy(1'b0), .App_rd_busy(rd_busy),
        .O_wr_busy(wr_busy), .App_wr_en(wr_en), .App_wr_addr(wr_addr),
        .write_req(write_req), .write_req_ack(write_ack), .write_finish(write_finish),
        .write_addr_0(21'd0), .write_addr_1(21'd2048),
        .write_addr_2(21'd0), .write_addr_3(21'd2048), .write_addr_index(bank),
        .write_len(21'd768), .fifo_aclr(wr_clear), .rdusedw({1'b0,wf_used}));
    frame_fifo_write_baseline #(.BURST_SIZE(BURST), .FRAME_WIDTH(256), .FRAME_HEIGHT(3)) reference_writer (
        .rst(rst), .mem_clk(mem_clk), .Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(1'b0), .Sdr_busy(1'b0), .App_rd_busy(rd_busy),
        .O_wr_busy(ref_busy), .App_wr_en(ref_en), .App_wr_addr(ref_addr),
        .write_req(write_req), .write_req_ack(ref_ack), .write_finish(ref_finish),
        .write_addr_0(21'd0), .write_addr_1(21'd2048),
        .write_addr_2(21'd0), .write_addr_3(21'd2048), .write_addr_index(bank),
        .write_len(21'd768), .fifo_aclr(ref_clear), .rdusedw({1'b0,wf_used}));
    frame_fifo_read #(.BURST_SIZE(BURST)) reader (
        .rst(rst), .mem_clk(mem_clk), .Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(1'b0), .Sdr_busy(1'b0), .Sdr_rd_en(response_valid[1]),
        .App_wr_busy(wr_busy), .O_rd_busy(rd_busy), .App_rd_en(rd_en), .App_rd_addr(rd_addr),
        .read_req(read_req), .read_req_ack(read_ack), .read_finish(read_finish),
        .read_addr_0(21'd8192), .read_addr_1(21'd8192),
        .read_addr_2(21'd8192), .read_addr_3(21'd8192), .read_addr_index(2'd0),
        .read_len(21'd768), .fifo_aclr(rd_clear), .wrusedw({1'b0,rf_used}));

    // Differential check: no added latency or changed priority is permitted.
    always @(negedge mem_clk) begin
        if({write_ack,write_finish,wr_busy,wr_en,wr_addr,wr_clear} !==
           {ref_ack,ref_finish,ref_busy,ref_en,ref_addr,ref_clear} ||
           writer.state !== reference_writer.state ||
           writer.write_cnt !== reference_writer.write_cnt)
            $fatal(1,"writer cycle equivalence failed");
        if(monitor_enable && writer.state==2 && writer.into_burst !== reference_writer.into_burst)
            $fatal(1,"burst predicate differs from original");
    end

    always @(posedge source_clk) begin
        if(monitor_enable && source_en) begin
            if(wf_full || wr_clear || wf.wr_rst) $fatal(1,"write FIFO overflow/reset write");
            if(previous_source_en) consecutive_source_beats=consecutive_source_beats+1;
            produced=produced+1;
        end
        if(monitor_enable && !source_en && previous_source_en) source_gaps=source_gaps+1;
        previous_source_en=source_en;
    end
    always @(posedge mem_clk) begin
        if(rst) begin response_valid<=0; response0<=0; response1<=0; end
        else begin
            response_valid<={response_valid[0],rd_en};
            if(rd_en) response0<=memory[rd_addr];
            response1<=response0;
        end
        if(monitor_enable && !rst) begin
            if(wf_used>max_wf_used) max_wf_used=wf_used;
            if(wr_en && rd_en) $fatal(1,"simultaneous memory read/write commands");
            if(wr_busy && reader.state==2) write_blocks_read=write_blocks_read+1;
            if(rd_busy && writer.state==2 && wf_used>BURST) read_blocks_write=read_blocks_write+1;
            if(wr_busy && !previous_wbusy) write_burst_starts=write_burst_starts+1;
            if(rd_busy && !previous_rbusy) read_burst_starts=read_burst_starts+1;
            if(wr_en) begin
                if(wf_empty || wr_clear || wf.rd_rst) $fatal(1,"write FIFO underflow/reset read");
                expected_addr=(bank*2048)+(2-(written/256))*256+(written%256);
                if(wr_addr!==expected_addr || wf_data!==(32'hb0000000|(epoch<<16)|written))
                    $fatal(1,"write data/address sequence error word=%0d addr=%0d data=%h",written,wr_addr,wf_data);
                memory[wr_addr]=wf_data;
                written=written+1;
                if(written>WORDS || written>produced) $fatal(1,"extra memory write");
            end
            if(rd_en) begin
                if(rd_addr!==READ_BASE+commanded) $fatal(1,"read command address/order error");
                commanded=commanded+1;
                if(commanded>WORDS) $fatal(1,"extra memory read");
            end
            if(response_valid[1] && (rf_full || rd_clear || rf.wr_rst))
                $fatal(1,"read FIFO overflow/reset response");
            if(write_finish) begin
                if(written!==WORDS || produced!==WORDS) $fatal(1,"early/incomplete frame write_finish");
                write_finishes=write_finishes+1;
            end
            if(read_finish) begin
                if(commanded!==WORDS) $fatal(1,"incomplete read frame");
                read_finishes=read_finishes+1;
            end
        end
        previous_wbusy=wr_busy; previous_rbusy=rd_busy;
    end
    always @(posedge pixel_clk) begin
        if(monitor_enable && !rst && pixel_en) begin
            if(rf_empty || rd_clear || rf.rd_rst) $fatal(1,"read FIFO underflow/reset pop");
            #0.1;
            if(rf_data!==(32'ha5000000|consumed)) $fatal(1,"pixel order/duplicate error %0d %h",consumed,rf_data);
            consumed=consumed+1;
            if(consumed>WORDS) $fatal(1,"extra pixel pop");
        end
    end

    task begin_frame;
        begin
            produced=0; written=0; commanded=0; consumed=0;
            write_finishes=0; read_finishes=0;
            fork
                begin
                    @(negedge source_clk); write_req=1;
                    wait(write_ack); repeat(3) @(negedge source_clk); write_req=0;
                    wait(!write_ack); repeat(5) @(negedge source_clk);
                end
                begin
                    @(negedge pixel_clk); read_req=1;
                    wait(read_ack); repeat(2) @(negedge pixel_clk); read_req=0;
                    wait(!read_ack); repeat(5) @(negedge pixel_clk);
                end
            join
            overlap_requests=overlap_requests+1;
        end
    endtask
    task push_words;
        input integer count;
        input integer intermittent;
        integer n;
        begin
            for(n=0;n<count;n=n+1) begin
                @(negedge source_clk);
                while(wf_full) begin source_en=0; @(negedge source_clk); end
                source_en=1; source_data=32'hb0000000|(epoch<<16)|produced;
                if(intermittent && n%3==0) begin
                    @(negedge source_clk); source_en=0;
                    repeat(3) @(negedge source_clk);
                end
            end
            @(negedge source_clk); source_en=0;
        end
    endtask
    task consume_frame;
        begin
            while(consumed<WORDS) begin
                @(negedge pixel_clk);
                pixel_en=(!rf_empty && !rf.rd_rst);
            end
            @(negedge pixel_clk); pixel_en=0;
        end
    endtask
    task run_frame;
        input integer frame_number;
        begin
            epoch=frame_number; bank=frame_number%2;
            begin_frame;
            repeat(40) @(negedge mem_clk);
            if(written!==0 || wf_used!==0) $fatal(1,"empty FIFO started write burst");
            // For a non-tail burst the original threshold is STRICTLY >256.
            push_words(255,frame_number%2);
            repeat(40) @(negedge mem_clk);
            if(wf_used!==255 || written!==0) $fatal(1,"low watermark behavior");
            push_words(1,0);
            repeat(40) @(negedge mem_clk);
            if(wf_used!==256 || written!==0) $fatal(1,"exact burst watermark changed");
            fork
                begin wait(rd_busy); push_words(512,frame_number%2); end
                begin consume_frame; end
            join
            wait(write_finishes==1 && read_finishes==1);
            repeat(24) @(negedge mem_clk);
            if(written!==WORDS || commanded!==WORDS || consumed!==WORDS ||
               write_finishes!==1 || read_finishes!==1)
                $fatal(1,"missing/duplicate frame operation");
            if(writer.state!==0 || reader.state!==0) $fatal(1,"frame did not return idle");
            $display("MEMORY_FRAME_%0d_PASS writes=%0d reads=%0d pixels=%0d",frame_number,written,commanded,consumed);
        end
    endtask

    // Actual candidate expression vs the old modular ADDR_BITS expression.
    // Exhaustive occupancy 0..511 for every configured full-frame burst count;
    // extra small/non-aligned lengths check the algebra outside the main fixture.
    reg [20:0] math_count=0, math_length=0;
    reg [9:0] math_fifo=0;
    wire probe_predicate;
    reg math_done=0;
    integer c,f,l;
    reg [20:0] original_sum;
    frame_fifo_write #(.BURST_SIZE(256)) probe (
        .rst(1'b1), .mem_clk(mem_clk), .Sdr_init_done(1'b0), .Sdr_init_ref_vld(1'b0),
        .Sdr_busy(1'b0), .App_rd_busy(1'b0), .write_req(1'b0), .write_len(21'd0),
        .write_addr_index(2'd0), .write_addr_0(21'd0), .write_addr_1(21'd0),
        .write_addr_2(21'd0), .write_addr_3(21'd0), .rdusedw(math_fifo),
        .O_wr_busy(), .App_wr_en(), .App_wr_addr(), .write_req_ack(), .write_finish(), .fifo_aclr());
    assign probe_predicate=probe.into_burst;
    initial begin
        force probe.write_cnt=math_count;
        force probe.write_len_latch=math_length;
        math_length=307200;
        for(c=0;c<=307456;c=c+256) begin
            math_count=c;
            for(f=0;f<512;f=f+1) begin
                math_fifo=f; original_sum=math_count+math_fifo; #0.001;
                if(probe_predicate !== ((math_length<=original_sum)||f>256))
                    $fatal(1,"configured-frame predicate mismatch count=%0d fifo=%0d",c,f);
            end
        end
        for(l=0;l<=1024;l=l+127) begin
            math_length=l;
            for(c=0;c<=1280;c=c+128) begin
                math_count=c;
                for(f=0;f<512;f=f+1) begin
                    math_fifo=f; original_sum=math_count+math_fifo; #0.001;
                    if(probe_predicate !== ((math_length<=original_sum)||f>256))
                        $fatal(1,"small-frame predicate mismatch");
                end
            end
        end
        release probe.write_cnt; release probe.write_len_latch;
        math_done=1;
        $display("MEMORY_BURST_PREDICATE_EQUIVALENCE_PASS");
    end
    integer i;
    initial begin
        for(i=0;i<WORDS;i=i+1) memory[READ_BASE+i]=32'ha5000000|i;
        repeat(8) @(negedge mem_clk); rst=0; monitor_enable=1;
        run_frame(0); run_frame(1); run_frame(2);
        // Recover from reset with no stale enables or response pipeline.
        monitor_enable=0; @(negedge mem_clk); rst=1;
        repeat(5) @(negedge mem_clk);
        if(wr_en || rd_en || write_ack || read_ack || wr_busy || rd_busy || response_valid)
            $fatal(1,"reset did not clear control state");
        rst=0; monitor_enable=1;
        run_frame(3);
        wait(math_done);
        if(overlap_requests!==4 || write_burst_starts<12 || read_burst_starts<12 || write_blocks_read==0 || read_blocks_write==0)
            $fatal(1,"required arbitration coverage missing");
        if(consecutive_source_beats==0 || source_gaps==0 || max_wf_used<=BURST)
            $fatal(1,"continuous/intermittent/high-water coverage missing");
        $display("MEMORY_ARBITRATION_COVERAGE overlap=%0d write_blocks_read=%0d read_blocks_write=%0d",overlap_requests,write_blocks_read,read_blocks_write);
        $display("MEMORY_FIFO_COVERAGE consecutive=%0d gaps=%0d max_used=%0d",consecutive_source_beats,source_gaps,max_wf_used);
        $display("MEMORY_ARBITRATION_TEST_PASS"); $finish;
    end
    initial begin #2000000; $fatal(1,"MEMORY_ARBITRATION_TIMEOUT"); end
endmodule
