`timescale 1ns/1ps
// Capability probe of the installed vendor models. No behavioral memory stub.
module tb_sdram_vendor_probe;
    reg clk=0,reset=1;
    always #4 clk=~clk;
    wire shifted=~clk;
    wire initialized,refresh,busy,rdvalid,sdclk,ras,cas,we;
    wire [31:0] rddata,dq;
    wire [10:0] addr;
    wire [1:0] bank;
    wire [3:0] dm;
    reg wr=0,rd=0;
    reg [20:0] wa=0,ra=0;
    reg [31:0] wd=0;
    sdr_as_ram #(.self_refresh_open(1'b1)) dut(.Sdr_clk(clk),.Sdr_clk_sft(shifted),.Rst(reset),
        .Sdr_init_done(initialized),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),.App_ref_req(1'b0),
        .App_wr_en(wr),.App_wr_addr(wa),.App_wr_dm(4'd0),.App_wr_din(wd),
        .App_rd_en(rd),.App_rd_addr(ra),.Sdr_rd_en(rdvalid),.Sdr_rd_dout(rddata),
        .SDRAM_CLK(sdclk),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),.SDR_BA(bank),
        .SDR_ADDR(addr),.SDR_DM(dm),.SDR_DQ(dq));
    EG_PHY_SDRAM_2M_32 memory(.clk(sdclk),.ras_n(ras),.cas_n(cas),.we_n(we),
        .addr(addr),.ba(bank),.dq(dq),.cs_n(1'b0),.cke(1'b1),
        .dm0(dm[0]),.dm1(dm[1]),.dm2(dm[2]),.dm3(dm[3]));
    integer i,seen=0,refreshes=0,auto_refresh_commands=0;
    time previous_refresh=0,maximum_refresh_gap=0;
    always @(posedge sdclk)begin
        if(!reset && !ras && !cas && we)begin
            auto_refresh_commands=auto_refresh_commands+1;
            if(previous_refresh && $time-previous_refresh>maximum_refresh_gap)
                maximum_refresh_gap=$time-previous_refresh;
            previous_refresh=$time;
            $display("VENDOR_REFRESH_OBSERVATION t=%0t count=%0d",$time,auto_refresh_commands);
        end
    end
    always @(posedge clk)begin
        if(!reset && refresh)refreshes=refreshes+1;
        if(!reset && rdvalid)begin
            if(rddata !== (32'h5a3c0000+seen))begin
                $display("VENDOR_SDRAM_PROBE_UNAVAILABLE data=%h expected=%h sample=%0d",rddata,32'h5a3c0000+seen,seen);
                $fatal(1,"installed vendor model did not reproduce stored data");
            end
            seen=seen+1;
        end
    end
    initial begin
        repeat(8)@(negedge clk);reset=0;
        wait(initialized);
        $display("VENDOR_INITIALIZATION_OBSERVATION t=%0t",$time);
        #200000;
        $display("VENDOR_REFRESH_SUMMARY commands=%0d max_gap_ns=%0t",auto_refresh_commands,maximum_refresh_gap);
        wait(!busy && !refresh);repeat(30)@(negedge clk);
        for(i=0;i<128;i=i+1)begin @(negedge clk);wr=1;wa=i;wd=32'h5a3c0000+i;end
        @(negedge clk);wr=0;repeat(100)@(negedge clk);
        wait(!busy && !refresh);
        for(i=0;i<128;i=i+1)begin @(negedge clk);rd=1;ra=i;end
        @(negedge clk);rd=0;repeat(200)@(negedge clk);
        if(seen!=128)$fatal(1,"VENDOR_SDRAM_PROBE_UNAVAILABLE read count %0d",seen);
        $display("VENDOR_SDRAM_PROBE_PASS samples=%0d",seen);$finish;
    end
    initial begin #3000000;$fatal(1,"VENDOR_SDRAM_PROBE_UNAVAILABLE init/read timeout");end
endmodule
