`timescale 1ns/1ps
// Real first sectors from ALL FOUR delivered BMPs. This is an explicit VGA
// compatibility gate, NOT a claim that this version decodes 720p pictures.
module tb_tourism_input_gate;
    reg clk=0,reset=1,start=0;always #5 clk=~clk;
    reg [7:0] bytes[0:2047];
    reg [7:0] sd_data=0;reg sd_valid=0,sd_end=0,packet=0;
    integer selected=0,offset=0,requests=0,gap=0;
    wire rd,wr,pv,done,err,ready;wire [31:0] addr;wire [7:0] code;
    bmp_read dut(.clk(clk),.rst(reset),.cancel(1'b0),.ready(ready),.scan_start(1'b0),.scan_start_sector(32'd0),
        .scan_max_sector(32'd0),.scan_target_count(3'd4),.scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
        .load_start(start),.load_sector(32'd0),.sd_init_done(1'b1),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
        .write_req(wr),.write_req_ack(1'b0),.sd_sec_read(rd),.sd_sec_read_addr(addr),.sd_sec_read_data(sd_data),
        .sd_sec_read_data_valid(sd_valid),.sd_sec_read_end(sd_end),.bmp_data_wr_en(pv),.bmp_data(),.pixel_ready(1'b1),
        .pixel_row_last(),.source_width(),.source_height(),.frame_start(),.source_done(done),.load_error(err),.error_code(code));
    always @(posedge clk)begin
        sd_valid<=0;sd_end<=0;
        if(reset)begin packet=0;offset=0;end
        else if(!packet && rd && !sd_end)begin packet=1;offset=0;gap=3;requests++;end
        else if(packet)begin
            if(gap>0)gap--;else if(offset<512)begin sd_data<=bytes[selected*512+offset];sd_valid<=1;offset++;gap=offset%3;end
            else begin sd_end<=1;packet=0;end
        end
        if(!reset && (wr || pv || done))begin
            $display("TOURISM_GATE_CHECKER_REJECT unsupported BMP reached the writer");$fatal(1,"unsafe 720p input");end
    end
    integer before_count;
    initial begin
        $readmemh("../../fixtures/tourism_720_first_sectors.hex",bytes);
        repeat(6)@(negedge clk);reset=0;
        for(selected=0;selected<4;selected++)begin
            before_count=requests;@(negedge clk);start=1;@(negedge clk);start=0;
            if($test$plusargs("INJECT_INPUT_ACCEPT"))force dut.write_req=1'b1;
            wait(err);if(code!=8'hE1 || requests!=before_count+1)$fatal(1,"wrong explicit size rejection");
            repeat(20)@(negedge clk);if(!ready)$fatal(1,"unsupported input hung parser");
        end
        $display("TOURISM_INPUT_GATE_TEST_PASS four_real_720p_BMPs_rejected_E1 no_write_no_overflow");$finish;
    end
    initial begin #1000000;$fatal(1,"input compatibility watchdog");end
endmodule
