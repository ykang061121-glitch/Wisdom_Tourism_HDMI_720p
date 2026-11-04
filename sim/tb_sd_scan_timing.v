`timescale 1ns/1ps
// Differential transactions, NOT cycle-identical FSMs. The reference parser
// is the exact unmodified dynamic-subtitle snapshot, in a separate test model.
module tb_sd_scan_timing;
    reg clk=0,video_clk=0,rst=1,cancel=0,init_done=1,scan_start=0,load_start=0;
    always #5 clk=~clk;
    always #20 video_clk=~video_clk;
    reg [31:0] start_sector=0,policy_max=0,dut_max=0,load_sector=0;
    reg [2:0] policy_target=4,dut_target=4;
    wire [1:0] ready,scan_done,found_valid,req,read_req,pixel_valid,row_last,source_done,error,frame_start;
    wire [31:0] found_sector[0:1],read_addr[0:1];
    wire [2:0] found_total[0:1];
    wire [23:0] rgb[0:1];
    wire [9:0] width[0:1],height[0:1];
    wire [7:0] error_code[0:1];
    reg [7:0] sd_data[0:1];
    reg [1:0] sd_valid=0,sd_end=0,ack=0;
    wire [1:0] pixel_ready;
    reg loading=0,check_scan=0,check_load=0;
    reg inject_advance=0,inject_boundary=0,advance_injected=0,boundary_injected=0;
    reg [32:0] corrupt_next;
    integer case_number=0,total_scan_cases=0,total_requests=0,total_found=0;
    reg [31:0] f_addr[0:15],f_len[0:15],f_off[0:15],f_w[0:15],f_h[0:15];
    integer f_bad[0:15],fixture_count=0;
    reg [31:0] expected_req[0:63],expected_found[0:3];
    integer expected_requests=0,expected_matches=0;
    integer requests[0:1],matches_seen[0:1],raw_pixels[0:1],eofs[0:1],errors_seen[0:1];
    integer position[0:1],delay_count[0:1],ack_delay[0:1];
    reg [31:0] packet_addr[0:1],seed[0:1];
    reg [1:0] active=0,previous_read=0;
    integer transport_mode=0; // 0 normal, 1 missing response, 2 short packet
    integer n,cancel_requests0,cancel_requests1;

    bmp_read #(.TEST_ALLOW_SIZE(1),.SECTOR_TIMEOUT_CYCLES(4096)) dut (
        .clk(clk),.rst(rst),.cancel(cancel),.ready(ready[0]),.scan_start(scan_start),
        .scan_start_sector(start_sector),.scan_max_sector(dut_max),.scan_target_count(dut_target),
        .scan_done(scan_done[0]),.scan_found_valid(found_valid[0]),.scan_found_sector(found_sector[0]),
        .scan_found_total(found_total[0]),.load_start(load_start),.load_sector(load_sector),
        .sd_init_done(init_done),.state_code(),.bmp_width(16'd4),.bmp_height(16'd2),
        .write_req(req[0]),.write_req_ack(ack[0]),.sd_sec_read(read_req[0]),.sd_sec_read_addr(read_addr[0]),
        .sd_sec_read_data(sd_data[0]),.sd_sec_read_data_valid(sd_valid[0]),.sd_sec_read_end(sd_end[0]),
        .bmp_data_wr_en(pixel_valid[0]),.bmp_data(rgb[0]),.pixel_ready(pixel_ready[0]),
        .pixel_row_last(row_last[0]),.source_width(width[0]),.source_height(height[0]),
        .frame_start(frame_start[0]),.source_done(source_done[0]),.load_error(error[0]),.error_code(error_code[0]));
    bmp_read_scan_baseline #(.TEST_ALLOW_SIZE(1),.SECTOR_TIMEOUT_CYCLES(4096)) reference (
        .clk(clk),.rst(rst),.cancel(cancel),.ready(ready[1]),.scan_start(scan_start),
        .scan_start_sector(start_sector),.scan_max_sector(policy_max),.scan_target_count(policy_target),
        .scan_done(scan_done[1]),.scan_found_valid(found_valid[1]),.scan_found_sector(found_sector[1]),
        .scan_found_total(found_total[1]),.load_start(load_start),.load_sector(load_sector),
        .sd_init_done(init_done),.state_code(),.bmp_width(16'd4),.bmp_height(16'd2),
        .write_req(req[1]),.write_req_ack(ack[1]),.sd_sec_read(read_req[1]),.sd_sec_read_addr(read_addr[1]),
        .sd_sec_read_data(sd_data[1]),.sd_sec_read_data_valid(sd_valid[1]),.sd_sec_read_end(sd_end[1]),
        .bmp_data_wr_en(pixel_valid[1]),.bmp_data(rgb[1]),.pixel_ready(pixel_ready[1]),
        .pixel_row_last(row_last[1]),.source_width(width[1]),.source_height(height[1]),
        .frame_start(frame_start[1]),.source_done(source_done[1]),.load_error(error[1]),.error_code(error_code[1]));

    // Actual scaler, completion guard and fade CDC/controller. Small 4x2 is a
    // test-only fast fixture; the unchanged full-frame regression tests all
    // three production sizes and actual FIFO/writer SDRAM addresses.
    wire scaler_ready,scaled_valid,scale_done,scale_busy;
    wire [23:0] scaled_rgb;
    wire [9:0] scaled_x,scaled_row;
    reg scaled_ready=0,memory_done=0;
    integer scaled_pixels=0,memory_delay=-1,ready_events=0,swaps=0;
    wire ss,cs,ms,frame_ready;
    reg request_toggle=0,ready_toggle=0,cancel_toggle=0;
    reg [1:0] pending_bank=1;
    wire request_video,ready_video,cancel_video,commit_video,done_video,commit_sd,done_sd;
    wire [3:0] pending_payload;
    wire [1:0] display_bank;
    wire display_valid,transition_busy;
    wire [2:0] fade,transition_state;
    reg video_frame=0,pre_frame;
    reg [2:0] pre_state;
    integer video_count=0,load_successes=0;
    assign pixel_ready[0]=loading ? scaler_ready : 1'b1;
    assign pixel_ready[1]=1'b1;
    image_scaler #(.OUT_WIDTH(4),.OUT_HEIGHT(2)) scaler(
        .clk(clk),.reset(rst),.cancel(cancel || error[0] || !init_done),.start(frame_start[0]),
        .source_width(width[0]),.source_height(height[0]),.in_rgb(rgb[0]),
        .in_valid(pixel_valid[0]),.in_ready(scaler_ready),.out_rgb(scaled_rgb),
        .out_valid(scaled_valid),.out_ready(scaled_ready),.out_x(scaled_x),.out_row(scaled_row),
        .scale_done(scale_done),.busy(scale_busy));
    frame_completion_guard guard(.clk(clk),.reset(rst),.start(load_start),
        .cancel(cancel || error[0] || !init_done),.memory_arm(frame_start[0]),
        .source_done(source_done[0]),.scale_done(scale_done),.memory_done(memory_done),
        .source_seen(ss),.scale_seen(cs),.memory_seen(ms),.ready_pulse(frame_ready));
    fade_transition_cdc cdc(
        .src_clk(clk),.src_reset(rst),.src_request_toggle(request_toggle),.src_ready_toggle(ready_toggle),
        .src_cancel_toggle(cancel_toggle),.src_pending_payload({2'd0,pending_bank}),
        .src_commit_pulse(commit_sd),.src_transition_done_pulse(done_sd),
        .dst_clk(video_clk),.dst_reset(rst),.dst_request_pulse(request_video),
        .dst_next_frame_ready(ready_video),.dst_cancel_pulse(cancel_video),.dst_pending_payload(pending_payload),
        .dst_commit_pulse(commit_video),.dst_transition_done_pulse(done_video));
    fade_transition_ctrl #(.FRAMES_PER_STEP(1)) transition(
        .video_clk(video_clk),.reset(rst),.frame_start_pulse(video_frame),
        .transition_request_pulse(request_video),.transition_cancel_pulse(cancel_video),
        .next_frame_ready(ready_video),.pending_buf_idx(pending_payload[1:0]),
        .pending_image_idx(pending_payload[3:2]),.display_buf_idx(display_bank),
        .display_image_idx(),.display_valid(display_valid),.fade_level(fade),
        .transition_busy(transition_busy),.transition_state(transition_state),
        .swap_commit_pulse(commit_video),.transition_done_pulse(done_video));
    always @(negedge video_clk) begin
        if(rst) begin video_count=0;video_frame=0;end
        else begin video_frame=(video_count==0);video_count=(video_count+1)%20;end
    end
    always @(posedge video_clk) begin
        pre_frame=video_frame;pre_state=transition_state;
        #0.1;
        if(!rst && commit_video) begin
            if(fade!==0 || !pre_frame || pre_state!=3 || !ss || !cs || !ms ||
               scaled_pixels!=8 || ready_events!=swaps+1)
                $fatal(1,"unsafe scan/load/fade buffer commit");
            swaps=swaps+1;
            if(display_bank!==pending_bank)$fatal(1,"wrong pending buffer");
        end
    end
    function automatic [23:0] reference_pixel(input integer col,row);
        reg [7:0] red,green,blue;
        begin
            red=8'h22+col*17;green=8'h44+row;blue=8'h66+col;
            reference_pixel={red,green,blue};
        end
    endfunction
    // Header layout is generated from file metadata, not from DUT counters.
    function automatic [7:0] file_byte(input [31:0] address,input integer byte_pos);
        integer k,relative,row,col,component,stride;
        reg [23:0] color;
        begin
            file_byte=0;k=-1;relative=byte_pos;
            for(integer t=0;t<fixture_count;t=t+1)
                if(address==f_addr[t])k=t;
            if(k<0 && loading)
                for(integer t=0;t<fixture_count;t=t+1)
                    if(address>f_addr[t] && address<f_addr[t]+((f_len[t]+511)/512)) begin
                        k=t;relative=(address-f_addr[t])*512+byte_pos;
                    end
            if(k>=0) begin
                case(relative)
                    0:file_byte=(f_bad[k]==1)?"X":"B";1:file_byte="M";
                    2,3,4,5:file_byte=f_len[k]>>((relative-2)*8);
                    10,11,12,13:file_byte=f_off[k]>>((relative-10)*8);
                    14:file_byte=(f_bad[k]==2)?108:40;
                    18,19,20,21:file_byte=f_w[k]>>((relative-18)*8);
                    22,23,24,25:file_byte=f_h[k]>>((relative-22)*8);
                    26:file_byte=(f_bad[k]==3)?0:1;
                    28:file_byte=(f_bad[k]==4)?16:24;
                    30:file_byte=(f_bad[k]==5)?1:0;
                    default:if(loading && relative>=f_off[k]) begin
                        stride=((f_w[k]*3+3)/4)*4;row=(relative-f_off[k])/stride;
                        col=((relative-f_off[k])%stride)/3;component=(relative-f_off[k])%stride%3;
                        if(row<f_h[k] && col<f_w[k]) begin
                            color=reference_pixel(col,row);
                            case(component)0:file_byte=color[7:0];1:file_byte=color[15:8];2:file_byte=color[23:16];endcase
                        end else file_byte=8'hEC;
                    end
                endcase
            end
        end
    endfunction
    // Independent integer/file-format model, with 64-bit overflow checking.
    task build_scan_reference;
        longint unsigned address,next_address,payload,extent,sectors;
        integer k,steps;
        bit legal;
        begin
            expected_requests=0;expected_matches=0;address=start_sector;steps=0;
            while(address<=policy_max && policy_target!=0 && expected_matches<policy_target) begin
                if(steps>=64)$fatal(1,"test reference request table overflow");
                expected_req[expected_requests]=address;expected_requests++;steps++;
                k=-1;for(integer t=0;t<fixture_count;t++)if(address==f_addr[t])k=t;
                legal=0;
                if(k>=0) begin
                    legal=f_bad[k]==0 && ((f_w[k]==320 && f_h[k]==240) ||
                        (f_w[k]==640 && f_h[k]==480) || (f_w[k]==800 && f_h[k]==600) ||
                        (f_w[k]==4 && f_h[k]==2));
                    payload=((64'(f_w[k])*3+3)/4)*4*64'(f_h[k]);
                    extent=64'(f_off[k])+payload;
                    sectors=(64'(f_len[k])+511)/512;next_address=address+sectors;
                    legal=legal && f_off[k]>=54 && extent<=32'hFFFFFFFF &&
                        f_len[k]>=extent && sectors!=0 && next_address<=131072;
                end
                if(legal) begin
                    expected_found[expected_matches]=address;expected_matches++;
                    if(expected_matches>=policy_target || next_address>policy_max) break;
                    address=next_address;
                end else address++;
            end
        end
    endtask
    task clear_scoreboard;
        begin
            for(integer t=0;t<2;t++)begin
                requests[t]=0;matches_seen[t]=0;raw_pixels[t]=0;eofs[t]=0;errors_seen[t]=0;
            end
        end
    endtask
    task reset_case;
        begin
            @(negedge clk);rst=1;cancel=0;init_done=1;scan_start=0;load_start=0;
            check_scan=0;check_load=0;loading=0;transport_mode=0;fixture_count=0;
            repeat(5)@(negedge clk);clear_scoreboard;rst=0;repeat(5)@(negedge clk);
        end
    endtask
    task add_file(input [31:0] address,w,h,offset,declared_length,input integer bad_kind);
        begin
            f_addr[fixture_count]=address;f_w[fixture_count]=w;f_h[fixture_count]=h;
            f_off[fixture_count]=offset;f_len[fixture_count]=declared_length;f_bad[fixture_count]=bad_kind;
            fixture_count++;
        end
    endtask
    task begin_scan(input [31:0] first,last,input [2:0] target);
        begin
            wait(&ready);@(negedge clk);
            start_sector=first;policy_max=last;dut_max=last;policy_target=target;dut_target=target;
            build_scan_reference;check_scan=1;scan_start=1;
            @(negedge clk);scan_start=0;
        end
    endtask
    task finish_scan;
        begin
            wait(&scan_done);wait(&ready);repeat(8)@(negedge clk);
            for(integer t=0;t<2;t++)
                if(requests[t]!=expected_requests || matches_seen[t]!=expected_matches ||
                   found_total[t]!=expected_matches || raw_pixels[t]!=0 || eofs[t]!=0 || errors_seen[t]!=0)
                    $fatal(1,"case %0d scanner totals differ model=%0d requests=%0d/%0d matches=%0d/%0d",
                           case_number,t,requests[t],expected_requests,matches_seen[t],expected_matches);
            total_requests+=requests[0];total_found+=matches_seen[0];total_scan_cases++;
            $display("SD_SCAN_CASE_PASS id=%0d requests=%0d found=%0d differential",case_number,requests[0],matches_seen[0]);
            check_scan=0;case_number++;
        end
    endtask

    always @(posedge clk) begin
        if(rst) begin
            active=0;previous_read=0;sd_valid<=0;sd_end<=0;ack<=0;
            seed[0]=32'h8542AB91;seed[1]=32'hBC731045;
            request_toggle<=0;ready_toggle<=0;cancel_toggle<=0;memory_done<=0;
            scaled_pixels=0;ready_events=0;swaps=0;memory_delay=-1;
            for(integer t=0;t<2;t++)begin position[t]=0;delay_count[t]=0;ack_delay[t]=0;end
        end else begin
            if(load_start)request_toggle<=~request_toggle;
            if(error[0] || cancel)cancel_toggle<=~cancel_toggle;
            memory_done<=0;
            if(cancel || error[0])memory_delay=-1;
            else if(memory_delay==0)begin memory_done<=1;memory_delay=-1;end
            else if(memory_delay>0)memory_delay--;
            if(scaled_valid && scaled_ready)begin
                if(scaled_pixels>=8 || scaled_x!==scaled_pixels%4 || scaled_row!==scaled_pixels/4 ||
                   scaled_rgb!==reference_pixel(scaled_pixels%4,scaled_pixels/4))
                    $fatal(1,"post-scan load/scaler pixel mismatch");
                scaled_pixels++;if(scaled_pixels==8)memory_delay=31;
            end
            if(frame_ready)begin
                if(!(ss&&cs&&ms) || scaled_pixels!=8)$fatal(1,"premature next_frame_ready");
                ready_events++;ready_toggle<=~ready_toggle;
            end
            for(integer t=0;t<2;t++)begin
                seed[t]={seed[t][30:0],seed[t][31]^seed[t][21]^seed[t][1]^seed[t][0]};
                sd_valid[t]<=0;sd_end[t]<=0;
                if(req[t])begin ack[t]<=1;ack_delay[t]=0;end
                else if(ack[t])begin if(ack_delay[t]==5)ack[t]<=0;else ack_delay[t]++;end
                if(read_req[t] && !previous_read[t])begin
                    if(check_scan && (requests[t]>=expected_requests || read_addr[t]!==expected_req[requests[t]]))begin
                        $display("SD_SCAN_CHECKER_REJECT request case=%0d model=%0d index=%0d address=%0d expected=%0d",
                                 case_number,t,requests[t],read_addr[t],expected_req[requests[t]]);
                        $fatal(1,"scan advance/order/range mismatch");
                    end
                    if(check_load && read_addr[t]!==load_sector+((requests[t]==2)?1:0))
                        $fatal(1,"header replay/cross-sector load request mismatch");
                    requests[t]++;
                end
                previous_read[t]=read_req[t];
                if(!active[t] && read_req[t] && !sd_end[t])begin
                    active[t]=1;packet_addr[t]=read_addr[t];position[t]=0;delay_count[t]=7+seed[t][4:0];
                end else if(active[t])begin
                    if(read_req[t] && read_addr[t]!==packet_addr[t])$fatal(1,"CMD17 address changed during packet");
                    if(transport_mode==1)begin end
                    else if(delay_count[t]>0)delay_count[t]--;
                    else if(position[t]==((transport_mode==2)?510:512))begin
                        active[t]=0;sd_end[t]<=1;
                    end else begin
                        sd_data[t]<=file_byte(packet_addr[t],position[t]);sd_valid[t]<=1;
                        position[t]++;delay_count[t]=seed[t][3:2];
                    end
                end
                if(found_valid[t])begin
                    if(check_scan && (matches_seen[t]>=expected_matches ||
                       found_sector[t]!==expected_found[matches_seen[t]] || found_total[t]!=matches_seen[t]+1))begin
                        $display("SD_SCAN_CHECKER_REJECT found case=%0d model=%0d sector=%0d",case_number,t,found_sector[t]);
                        $fatal(1,"scan boundary/validity/index mismatch");
                    end
                    matches_seen[t]++;
                end
                if(error[t])errors_seen[t]++;
                if(pixel_valid[t] && pixel_ready[t])begin
                    if(!loading || ack[t] || req[t] ||
                       rgb[t]!==reference_pixel(raw_pixels[t]%4,raw_pixels[t]/4))
                        $fatal(1,"pixel before ACK return-low or incorrect BGR");
                    raw_pixels[t]++;
                end
                if(source_done[t])begin
                    if(raw_pixels[t]!=8)$fatal(1,"source EOF before complete pixels");eofs[t]++;
                end
            end
        end
    end
    // Registered comparisons must consume one stable transaction snapshot.
    reg [32:0] held_next;
    reg [31:0] held_length,held_scan;
    always @(negedge clk)begin
        scaled_ready=seed[0][0] && seed[0][2];
        if(!rst && dut.state==10)begin held_next=dut.next_file_sector;held_length=dut.file_len;held_scan=dut.scan_sector;end
        if(!rst && dut.state==12)begin
            if(dut.next_file_sector!==held_next || dut.file_len!==held_length || dut.scan_sector!==held_scan ||
               dut.scan_max_latched!==policy_max || (check_scan && dut.scan_target_latched!==policy_target))
                $fatal(1,"range evaluate/commit transaction was overwritten");
            if(inject_advance && !advance_injected && check_scan && !dut.range_invalid && !dut.scan_stop_after_match)begin
                corrupt_next=dut.next_file_sector+1;force dut.next_file_sector=corrupt_next;advance_injected=1;
            end
            if(inject_boundary && !boundary_injected && check_scan && dut.range_invalid)begin
                force dut.range_invalid=0;boundary_injected=1;
            end
        end else begin
            if(advance_injected)release dut.next_file_sector;
            if(boundary_injected)release dut.range_invalid;
        end
    end
    initial begin
        inject_advance=$test$plusargs("INJECT_SCAN_ADVANCE");
        inject_boundary=$test$plusargs("INJECT_SCAN_BOUNDARY");
        reset_case;begin_scan(17,22,4);finish_scan;
        reset_case;add_file(10,320,240,54,230454,0);add_file(462,4,2,54,78,0);
        begin_scan(10,462,4);finish_scan;
        reset_case;
        add_file(0,320,240,54,230454,0);add_file(451,640,480,1023,922623,0);
        add_file(2253,800,600,513,1440513,0);add_file(5067,640,480,54,921654,0);
        begin_scan(0,10000,4);finish_scan;
        reset_case;add_file(131071,4,2,54,78,0);begin_scan(131071,131071,4);finish_scan;
        reset_case;add_file(131070,320,240,54,230454,0);begin_scan(131070,131071,4);finish_scan;
        reset_case;add_file(131070,640,480,54,32'hFFFFFFFF,0);begin_scan(131070,131071,4);finish_scan;
        reset_case;add_file(3,4,2,54,512,0);add_file(4,4,2,54,513,0);
        add_file(6,4,2,54,1024,0);add_file(8,4,2,54,1025,0);begin_scan(3,13,4);finish_scan;
        reset_case;for(n=1;n<=5;n++)add_file(n-1,640,480,54,921654,n);
        add_file(5,32'd66176,480,54,921654,0);add_file(6,640,32'hFFFFFE20,54,921654,0);
        add_file(7,640,480,32'hFFFFFFF0,32'hFFFFFFFF,0);add_file(8,640,480,54,921653,0);
        add_file(9,640,480,53,921654,0);add_file(10,4,2,54,0,0);
        add_file(11,640,480,54,921654,0);begin_scan(0,11,4);finish_scan;
        reset_case;add_file(7,4,2,54,78,0);begin_scan(5,7,4);finish_scan;
        reset_case;begin_scan(12,11,4);finish_scan;
        reset_case;begin_scan(0,8,0);finish_scan;
        // Change board-facing scan inputs while the accepted header is evaluated.
        // The baseline receives the original stable policy as its environment.
        reset_case;add_file(0,4,2,54,78,0);add_file(1,4,2,54,78,0);
        begin_scan(0,1,4);wait(dut.state==10);@(negedge clk);dut_max=0;dut_target=0;finish_scan;
        // 33-bit addition must reject a wrapped file address, not scan sector 0.
        reset_case;add_file(32'hFFFFFFFE,640,480,54,32'hFFFFFFFF,0);
        begin_scan(32'hFFFFFFFE,32'hFFFFFFFF,4);finish_scan;
        // Cancellation at FETCH, compare and commit; no new packet after cancel.
        for(n=0;n<3;n++)begin
            reset_case;add_file(0,4,2,54,78,0);begin_scan(0,2,4);
            if(n==0)wait(dut.sector_buffer.state==1);else if(n==1)wait(dut.state==10);else wait(dut.state==12);
            @(negedge clk);check_scan=0;
            // SD request becomes high with the preceding registered FETCH
            // transition; this model counts it at the next rising edge.
            // An already asserted level belongs to the in-flight CMD17, NOT
            // a post-cancel request (FETCH holds it until completion/cancel).
            cancel_requests0=requests[0]+(read_req[0] && !previous_read[0]);
            cancel_requests1=requests[1]+(read_req[1] && !previous_read[1]);
            cancel=1;
            @(negedge clk);cancel=0;wait(&ready);repeat(10)@(negedge clk);
            if(req || read_req || pixel_valid || frame_ready ||
               requests[0]!=cancel_requests0 || requests[1]!=cancel_requests1)
                $fatal(1,"cancel emitted new CMD17/request/data/frame ready stage=%0d requests=%0d/%0d expected=%0d/%0d",
                       n,requests[0],requests[1],cancel_requests0,cancel_requests1);
            clear_scoreboard;begin_scan(0,0,4);finish_scan;
        end
        // Reset and init loss in the newly added stage must discard old flags.
        reset_case;add_file(0,4,2,54,78,0);begin_scan(0,0,4);wait(dut.state==12);
        @(negedge clk);check_scan=0;rst=1;repeat(5)@(negedge clk);clear_scoreboard;rst=0;
        begin_scan(0,0,4);finish_scan;
        reset_case;add_file(0,4,2,54,78,0);begin_scan(0,0,4);wait(dut.state==12);
        @(negedge clk);check_scan=0;init_done=0;repeat(5)@(negedge clk);
        if(dut.range_invalid || dut.scan_stop_after_match || found_total[0]!=0)$fatal(1,"init loss retained flags");
        init_done=1;wait(&ready);clear_scoreboard;begin_scan(0,0,4);finish_scan;
        // Transport timeout and short CMD17 fail rather than looping forever.
        for(n=1;n<=2;n++)begin
            reset_case;transport_mode=n;begin_scan(0,0,4);
            wait(errors_seen[0]==1 && errors_seen[1]==1);check_scan=0;
            if(found_total[0] || found_total[1] || req || frame_ready)$fatal(1,"bad packet accepted");
            if(n==1)begin
                repeat(8)@(negedge clk);if(ready)$fatal(1,"timeout did not drain in-flight CMD17");
                transport_mode=0;position[0]=512;position[1]=512;delay_count[0]=0;delay_count[1]=0;
            end
            wait(&ready);if(requests[0]!=1 || requests[1]!=1)$fatal(1,"transport error issued extra CMD17");
        end
        // Scan -> load -> actual scaler -> three-condition guard -> black commit.
        reset_case;add_file(100,4,2,511,535,0);begin_scan(100,101,4);finish_scan;
        clear_scoreboard;loading=1;check_load=1;load_sector=100;
        wait(&ready);@(negedge clk);load_start=1;@(negedge clk);load_start=0;
        wait(swaps==1);wait(!transition_busy);wait(&ready);repeat(10)@(negedge clk);
        if(requests[0]!=3 || requests[1]!=3 || raw_pixels[0]!=8 || raw_pixels[1]!=8 ||
           eofs[0]!=1 || eofs[1]!=1 || ready_events!=1 || errors_seen[0] || errors_seen[1])
            $fatal(1,"scan/load/scale/completion totals");load_successes++;
        // Repeat after initialization: an ordinary BUF1 -> BUF0 load must use
        // the same ready handshake, real fade-out and black-frame commit.
        clear_scoreboard;pending_bank=0;scaled_pixels=0;
        @(negedge clk);load_start=1;@(negedge clk);load_start=0;
        wait(swaps==2);wait(!transition_busy);wait(&ready);repeat(10)@(negedge clk);
        if(requests[0]!=3 || requests[1]!=3 || raw_pixels[0]!=8 || raw_pixels[1]!=8 ||
           eofs[0]!=1 || eofs[1]!=1 || ready_events!=2 || display_bank!=0 || errors_seen[0] || errors_seen[1])
            $fatal(1,"repeated scan/load/scale/completion totals");load_successes++;
        // A rejected follow-up load must leave BUF0 displayed and emit no ready.
        clear_scoreboard;check_load=0;f_bad[0]=1;pending_bank=1;scaled_pixels=0;
        @(negedge clk);load_start=1;@(negedge clk);load_start=0;
        wait(errors_seen[0]==1 && errors_seen[1]==1);wait(&ready);repeat(250)@(negedge clk);
        if(ready_events!=2 || swaps!=2 || display_bank!=0 || transition_busy || raw_pixels[0] || raw_pixels[1])
            $fatal(1,"failed load published stale ready/swapped");
        $display("SD_SCAN_TIMING_TEST_PASS differential_cases=%0d requests=%0d found=%0d load_scale_black_commit=%0d cancel_reset_init_timeout_snapshot",
                 total_scan_cases,total_requests,total_found,load_successes);$finish;
    end
    initial begin #20000000;$fatal(1,"SD_SCAN_TIMING_TIMEOUT");end
endmodule
