`ifndef PCM_SPECTRUM_DFT512_V
`define PCM_SPECTRUM_DFT512_V
// v3: read-only real PCM; 512-point Hann, complete bins 1..255, 16 bands.
// One signed 16x16 multiplier; independently registered memory/control paths.
module pcm_spectrum_dft512 (
    input wire clk, reset, sample_valid,
    input wire signed [23:0] pcm_sample,
    output reg snapshot_valid,
    output reg [127:0] snapshot_levels,
    output reg [511:0] snapshot_power,
    output wire busy,
    output reg overrun
);
    localparam WAIT_SAMPLE=0, WINDOW_MUL=1, WINDOW_STORE=2,
        CLEAR_START=3, CLEAR_WRITE=4, BAND_SETUP=5,
        LOAD_SAMPLE=6, REAL_MUL=7, REAL_ACC=8, IMAG_MUL=9, IMAG_ACC=10,
        POWER_SETUP=11, POWER_REAL=12, POWER_IMAG_SETUP=13, POWER_IMAG=14,
        POWER_SUM=15, BAND_READ=16, BAND_COMPARE=17, BAND_WRITE=18, NEXT_BIN=19,
        COMPRESS_START=20, COMPRESS_READ=21, COMPRESS_LATCH=22,
        COMPRESS_EXP=23, COMPRESS_FRACTION=24, COMPRESS_HEIGHT=25,
        COMPRESS_CLIP=26, COMPRESS_WRITE=27, COMMIT=28;
    reg [4:0] state;
    reg [10:0] hop_count;
    reg [8:0] capture_index, sample_index, phase_index;
    reg [7:0] bin_index;
    reg capture_enabled;
    wire capture_event=sample_valid && state==WAIT_SAMPLE &&
        (hop_count==0 || (hop_count<512 && capture_enabled));
    assign busy=state!=WAIT_SAMPLE;

    // Official TD RAM/ROM inference style: separate unreset synchronous ports.
    (* ram_style="bram" *) reg signed [15:0] sample_memory [0:511];
    (* rom_style="bram" *) reg signed [15:0] hann_rom [0:511];
    (* rom_style="bram" *) reg signed [15:0] sine_rom [0:511];
    (* ram_style="bram" *) reg [31:0] band_power [0:15];
    reg signed [15:0] sample_q,hann_q,sine_q;
    reg [31:0] band_q;
    reg [3:0] current_band,clear_index,compress_index;
    wire [8:0] cosine_address=phase_index+9'd128;
    wire [8:0] sine_address=(state==REAL_ACC || state==IMAG_MUL)?phase_index:cosine_address;
    wire [3:0] band_read_address=(state==COMPRESS_READ)?compress_index:current_band;
    reg [31:0] candidate_power;
    reg band_update;
    reg signed [15:0] mul_a,mul_b;
    reg signed [31:0] product;
    reg signed [39:0] real_sum,imag_sum;
    reg [31:0] real_power;
    initial begin
`include "pcm_spectrum_tables.vh"
    end
    always @(posedge clk) begin
        if(!reset && state==WINDOW_STORE)
            sample_memory[capture_index]<=product>>>15;
        sample_q<=sample_memory[sample_index];
        hann_q<=hann_rom[hop_count[8:0]];
        sine_q<=sine_rom[sine_address];
    end
    // Band memory has no asynchronous reset or wide shared CE. Clear it after
    // capture, before the first bin; all real input capture samples are retained.
    always @(posedge clk) begin
        if(!reset) begin
            if(state==CLEAR_WRITE) band_power[clear_index]<=0;
            else if(state==BAND_WRITE && band_update)
                band_power[current_band]<=candidate_power;
        end
        if(state==BAND_READ || state==COMPRESS_READ)
            band_q<=band_power[band_read_address];
    end

    function [3:0] band_for_bin;
        input [7:0] k;
        begin
            if(k<2) band_for_bin=0; else if(k<3) band_for_bin=1;
            else if(k<4) band_for_bin=2; else if(k<5) band_for_bin=3;
            else if(k<7) band_for_bin=4; else if(k<9) band_for_bin=5;
            else if(k<12) band_for_bin=6; else if(k<16) band_for_bin=7;
            else if(k<22) band_for_bin=8; else if(k<30) band_for_bin=9;
            else if(k<41) band_for_bin=10; else if(k<56) band_for_bin=11;
            else if(k<77) band_for_bin=12; else if(k<106) band_for_bin=13;
            else if(k<146) band_for_bin=14; else band_for_bin=15;
        end
    endfunction
    function [4:0] highest_bit;
        input [31:0] p;
        integer j;
        begin
            highest_bit=0;
            for(j=0;j<32;j=j+1) if(p[j]) highest_bit=j;
        end
    endfunction

    // State/counters only. Arithmetic and output enables are local below.
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            state<=WAIT_SAMPLE;hop_count<=0;capture_index<=0;capture_enabled<=0;
            sample_index<=0;phase_index<=0;bin_index<=1;
            clear_index<=0;compress_index<=0;overrun<=0;
        end else begin
            if(sample_valid) begin
                hop_count<=hop_count+11'd1;
                if(hop_count==0) begin
                    if(state==WAIT_SAMPLE) capture_enabled<=1;
                    else begin capture_enabled<=0;overrun<=1;end
                end else if(hop_count<512 && capture_enabled && state!=WAIT_SAMPLE) begin
                    capture_enabled<=0;overrun<=1;
                end
            end
            if(capture_event) begin capture_index<=hop_count[8:0];state<=WINDOW_MUL;end
            case(state)
                WAIT_SAMPLE: begin end
                WINDOW_MUL: state<=WINDOW_STORE;
                WINDOW_STORE: begin
                    if(capture_index==511 && capture_enabled) state<=CLEAR_START;
                    else state<=WAIT_SAMPLE;
                end
                CLEAR_START: begin clear_index<=0;state<=CLEAR_WRITE;end
                CLEAR_WRITE: begin
                    if(clear_index==15) begin bin_index<=1;state<=BAND_SETUP;end
                    else clear_index<=clear_index+4'd1;
                end
                BAND_SETUP: begin sample_index<=0;phase_index<=0;state<=LOAD_SAMPLE;end
                LOAD_SAMPLE: state<=REAL_MUL;
                REAL_MUL: state<=REAL_ACC;
                REAL_ACC: state<=IMAG_MUL;
                IMAG_MUL: state<=IMAG_ACC;
                IMAG_ACC: begin
                    if(sample_index==511) state<=POWER_SETUP;
                    else begin
                        sample_index<=sample_index+9'd1;
                        phase_index<=phase_index+{1'b0,bin_index};state<=LOAD_SAMPLE;
                    end
                end
                POWER_SETUP: state<=POWER_REAL;
                POWER_REAL: state<=POWER_IMAG_SETUP;
                POWER_IMAG_SETUP: state<=POWER_IMAG;
                POWER_IMAG: state<=POWER_SUM;
                POWER_SUM: state<=BAND_READ;
                BAND_READ: state<=BAND_COMPARE;
                BAND_COMPARE: state<=BAND_WRITE;
                BAND_WRITE: state<=NEXT_BIN;
                NEXT_BIN: begin
                    if(bin_index==255) state<=COMPRESS_START;
                    else begin bin_index<=bin_index+8'd1;state<=BAND_SETUP;end
                end
                COMPRESS_START: begin compress_index<=0;state<=COMPRESS_READ;end
                COMPRESS_READ: state<=COMPRESS_LATCH;
                COMPRESS_LATCH: state<=COMPRESS_EXP;
                COMPRESS_EXP: state<=COMPRESS_FRACTION;
                COMPRESS_FRACTION: state<=COMPRESS_HEIGHT;
                COMPRESS_HEIGHT: state<=COMPRESS_CLIP;
                COMPRESS_CLIP: state<=COMPRESS_WRITE;
                COMPRESS_WRITE: begin
                    if(compress_index==15) state<=COMMIT;
                    else begin compress_index<=compress_index+4'd1;state<=COMPRESS_READ;end
                end
                COMMIT: state<=WAIT_SAMPLE;
                default: state<=WAIT_SAMPLE;
            endcase
        end
    end

    wire dft_multiply=state==REAL_MUL || state==IMAG_MUL;
    wire signed [15:0] multiplier_a=dft_multiply?sample_q:mul_a;
    wire signed [15:0] multiplier_b=(state==WINDOW_MUL)?hann_q:(dft_multiply?sine_q:mul_b);
    wire signed [31:0] multiply=multiplier_a*multiplier_b;
    wire [32:0] summed_power={1'b0,real_power}+{1'b0,product[31:0]};
    always @(posedge clk) begin
        if(capture_event) mul_a<=pcm_sample[23:8];
        else if(state==POWER_SETUP) begin mul_a<=real_sum>>>24;mul_b<=real_sum>>>24;end
        else if(state==POWER_IMAG_SETUP) begin mul_a<=imag_sum>>>24;mul_b<=imag_sum>>>24;end
        if(state==WINDOW_MUL || state==REAL_MUL || state==IMAG_MUL || state==POWER_REAL || state==POWER_IMAG)
            product<=multiply;
    end
    always @(posedge clk) begin
        if(state==BAND_SETUP) begin
            current_band<=band_for_bin(bin_index);real_sum<=0;imag_sum<=0;
        end else begin
            if(state==REAL_ACC) real_sum<=real_sum+{{8{product[31]}},product};
            if(state==IMAG_ACC) imag_sum<=imag_sum-{{8{product[31]}},product};
        end
        if(state==POWER_IMAG_SETUP) real_power<=product;
        if(state==POWER_SUM) candidate_power<=summed_power[32]?32'hffffffff:summed_power[31:0];
        if(state==BAND_COMPARE) band_update<=candidate_power>band_q;
    end

    // Compressor: RAM read, power latch, exponent, mantissa, height, saturation
    // and byte write are separated. No DFT compare signal enables these flops.
    reg [31:0] compression_power;
    reg [4:0] compression_exponent;
    reg [2:0] compression_fraction;
    reg [8:0] compression_value;
    reg [7:0] compression_height;
    wire [4:0] fraction_shift=compression_exponent>=3?compression_exponent-5'd3:5'd0;
    wire [31:0] fraction_shifted=compression_power>>fraction_shift;
    wire [8:0] exponent_delta={4'd0,compression_exponent}-9'd6;
    wire [4:0] fraction_times_three={2'd0,compression_fraction}+{1'd0,compression_fraction,1'b0};
    always @(posedge clk) begin
        if(state==COMPRESS_LATCH) compression_power<=band_q;
        if(state==COMPRESS_EXP) compression_exponent<=highest_bit(compression_power);
        if(state==COMPRESS_FRACTION) compression_fraction<=fraction_shifted[2:0];
        if(state==COMPRESS_HEIGHT) begin
            if(compression_power<64) compression_value<=0;
            else compression_value<=(exponent_delta<<3)+(exponent_delta<<2)+{5'd0,fraction_times_three[4:1]};
        end
        if(state==COMPRESS_CLIP) compression_height<=compression_value>255?8'd255:compression_value[7:0];
    end
    reg [127:0] compressed_levels;
    reg [511:0] powers_work;
    genvar b;
    generate for(b=0;b<16;b=b+1) begin: local_band_output
        always @(posedge clk) begin
            if(state==COMPRESS_WRITE && compress_index==b) begin
                compressed_levels[b*8+:8]<=compression_height;
                powers_work[b*32+:32]<=compression_power;
            end
        end
    end endgenerate
    always @(posedge clk or posedge reset) begin
        if(reset) begin snapshot_valid<=0;snapshot_levels<=0;snapshot_power<=0;end
        else begin
            snapshot_valid<=state==COMMIT;
            if(state==COMMIT) begin snapshot_levels<=compressed_levels;snapshot_power<=powers_work;end
        end
    end
endmodule
`endif
