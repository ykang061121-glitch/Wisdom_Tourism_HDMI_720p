`timescale 1ns/1ps
module tb_streaming;
    reg clk=0; always #5 clk=~clk;
    reg reset=1, sample_valid=0;
    reg signed [23:0] pcm_sample=0;
    wire snapshot_valid,busy,overrun;
    wire [127:0] levels;
    wire [511:0] powers;
    reg [127:0] previous_levels;
    reg [511:0] previous_powers;
    integer stimulus [0:32767];
    integer n,k,case_index,fd,snapshots,cycles,last_snapshot_cycle;
    pcm_spectrum_dft512 dut(.clk(clk),.reset(reset),.sample_valid(sample_valid),
        .pcm_sample(pcm_sample),.snapshot_valid(snapshot_valid),
        .snapshot_levels(levels),.snapshot_power(powers),.busy(busy),.overrun(overrun));
    always @(negedge clk) begin
        if(reset) begin
            previous_levels=0;previous_powers=0;cycles=0;last_snapshot_cycle=0;
        end else begin
            cycles=cycles+1;
            if(!snapshot_valid && (levels!==previous_levels || powers!==previous_powers))
                $fatal(1,"outputs changed outside atomic snapshot");
            if(snapshot_valid) begin
                $fwrite(fd,"%0d,%0d,%0d",snapshots,cycles,cycles-last_snapshot_cycle);
                for(k=0;k<16;k=k+1) $fwrite(fd,",%0d",powers[k*32+:32]);
                $fwrite(fd,"\n");
                if(snapshots>0 && cycles-last_snapshot_cycle!=2048*521)
                    $fatal(1,"snapshot cadence changed");
                last_snapshot_cycle=cycles;snapshots=snapshots+1;
            end
            previous_levels=levels;previous_powers=powers;
        end
    end
    initial begin
        snapshots=0;
        fd=$fopen("streaming_snapshots.csv","w");
        $readmemh("stimulus.hex",stimulus);
        repeat(3) @(posedge clk);
        @(posedge clk); #1 reset=0;
        // 25 MHz-equivalent cadence, tighter than production 74.25 MHz.
        for(n=0;n<6144;n=n+1) begin
            @(posedge clk); #1;
            case_index=(n<2048)?1:(n<4096)?2:0;
            pcm_sample=stimulus[case_index*512+(n%512)];sample_valid=1;
            @(posedge clk); #1 sample_valid=0;
            repeat(519) @(posedge clk);
        end
        repeat(10) @(posedge clk);
        if(snapshots!=3 || overrun) $fatal(1,"streaming failed snapshots=%0d overrun=%0d",snapshots,overrun);
        $fclose(fd);$display("PASS continuous 3 hops, atomic stable outputs, no overrun, 2048-sample cadence");$finish;
    end
endmodule
