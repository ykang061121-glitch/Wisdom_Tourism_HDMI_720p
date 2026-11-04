`timescale 1ns/1ps
module tb_spectrum;
    reg clk=0; always #5 clk=~clk;
    reg reset=1, sample_valid=0;
    reg signed [23:0] pcm_sample=0;
    wire snapshot_valid, busy, overrun;
    wire [127:0] levels;
    wire [511:0] powers;
    integer stimulus [0:32767];
    integer case_count, case_id, n, k, fd, wait_cycles, total_cycles;
    pcm_spectrum_dft512 dut(.clk(clk),.reset(reset),.sample_valid(sample_valid),
        .pcm_sample(pcm_sample),.snapshot_valid(snapshot_valid),
        .snapshot_levels(levels),.snapshot_power(powers),.busy(busy),.overrun(overrun));
    task hard_reset;
        begin
            @(negedge clk); reset=1; sample_valid=0; pcm_sample=0;
            repeat(3) @(negedge clk);
            reset=0;
            @(negedge clk);
            if(levels!==0 || powers!==0 || overrun!==0) $fatal(1,"reset did not clear outputs");
        end
    endtask
    task send_sample;
        input integer p;
        input integer gap;
        begin
            pcm_sample=p; sample_valid=1;
            @(negedge clk); sample_valid=0;
            repeat(gap-1) @(negedge clk);
        end
    endtask
    initial begin
        $readmemh("stimulus.hex",stimulus);
        fd=$fopen("rtl_snapshots.csv","w");
        if(!$value$plusargs("CASES=%d",case_count)) case_count=1;
        for(case_id=0;case_id<case_count;case_id=case_id+1) begin
            hard_reset;
            // Interrupt both a partial capture and an active DFT before case 0.
            if(case_id==0) begin
                for(n=0;n<113;n=n+1) send_sample(8388607,8);
                hard_reset;
                for(n=0;n<512;n=n+1) send_sample(8388607,8);
                repeat(500) @(negedge clk);
                hard_reset;
            end
            for(n=0;n<512;n=n+1) begin
                send_sample(stimulus[case_id*512+n],case_id==1?1546:8);
                if(case_id==6 && n==211) repeat(2000) @(negedge clk);
            end
            wait_cycles=0;
            while(!snapshot_valid && wait_cycles<700000) begin
                @(negedge clk); wait_cycles=wait_cycles+1;
            end
            if(!snapshot_valid || overrun) $fatal(1,"no clean snapshot case %0d",case_id);
            $fwrite(fd,"%0d,%0d",case_id,wait_cycles);
            for(k=0;k<16;k=k+1) $fwrite(fd,",%0d",powers[k*32+:32]);
            for(k=0;k<16;k=k+1) $fwrite(fd,",%0d",levels[k*8+:8]);
            $fwrite(fd,"\n");
            $display("PASS snapshot case %0d, process wait %0d cycles",case_id,wait_cycles);
        end
        // Too-fast source is reported, never fed back to PCM.
        hard_reset;
        for(n=0;n<16;n=n+1) send_sample(1000000,1);
        if(!overrun) $fatal(1,"overrun stress was not detected");
        hard_reset;
        $fclose(fd); $display("PASS spectrum snapshots, pause/reset/overrun"); $finish;
    end
endmodule
