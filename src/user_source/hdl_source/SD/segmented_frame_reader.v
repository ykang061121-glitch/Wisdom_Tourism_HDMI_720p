// Independent experiment ONLY. One memory read port, aligned 256-word bursts.
// Every returned word is tagged by its burst position before the display FIFO.
// No line-internal FIFO reset, no second frame stream, no change to SiP IP.
module segmented_frame_reader #(
 parameter WIDTH=1280, HEIGHT=720, FIFO_DEPTH=1024
)(
 input wire reset,mem_clk,initialized,memory_busy,writer_busy,
 input wire read_req,
 input wire [10:0] shift_pixels,
 input wire old_bank,new_bank,reveal_mode,next_frame_complete,
 output reg read_ack,
 output reg fifo_clear,
 input wire [9:0] fifo_used,
 output wire app_read,
 output wire [20:0] app_address,
 input wire memory_valid,
 input wire [31:0] memory_data,
 output wire fifo_write,
 output wire [31:0] fifo_data,
 output wire reader_busy,
 output reg frame_done,protocol_error,
 output reg [20:0] accepted_pixels,
 output reg [15:0] bursts
);
 localparam WORDS=WIDTH*HEIGHT;
 localparam IDLE=0,ACK=1,ROW=2,DESC=3,CHECK=4,BURST=5,ADVANCE=6,DONE=7;
 reg[3:0]state;
 reg[2:0]req_sync;
 reg[14:0]meta0,meta1;
 reg[10:0]shift,cut,row;
 reg old_latched,new_latched,reveal_latched;
 reg segment;
 reg[20:0]row_base,burst_base;
 reg[10:0]left;
 reg[7:0]head;
 reg[8:0]keep_first,keep_end,take,issued,received;
 reg[20:0]address;
 wire[8:0]capacity=9'd256-{1'b0,head};
 wire[8:0]take_next=(left>=capacity)?capacity:left[8:0];
 wire[10:0]start_x=segment?(reveal_latched?cut:11'd0):(reveal_latched?11'd0:shift);
 wire selected_bank=segment?new_latched:old_latched;
 assign app_read=(state==BURST && issued<256);
 assign app_address=address;
 assign reader_busy=state==BURST;
 assign fifo_write=(state==BURST && memory_valid && received>=keep_first && received<keep_end);
 assign fifo_data=memory_data;
 always @(posedge mem_clk or posedge reset)begin
  if(reset)begin req_sync<=0;meta0<=0;meta1<=0;end
  else begin
   req_sync<={req_sync[1:0],read_req};
   // Bundle is held by the requester throughout request/ACK and the frame.
   meta0<={next_frame_complete,reveal_mode,new_bank,old_bank,shift_pixels};
   meta1<=meta0;
  end
 end
 always @(posedge mem_clk or posedge reset)begin
  if(reset)begin
   state<=IDLE;read_ack<=0;fifo_clear<=0;frame_done<=0;protocol_error<=0;
   shift<=0;cut<=WIDTH;row<=0;row_base<=0;burst_base<=0;address<=0;
   old_latched<=0;new_latched<=1;reveal_latched<=0;segment<=0;left<=0;head<=0;
   keep_first<=0;keep_end<=0;take<=0;issued<=0;received<=0;accepted_pixels<=0;bursts<=0;
  end else begin
   frame_done<=0;
   if(fifo_write)accepted_pixels<=accepted_pixels+1'b1;
   case(state)
    IDLE:if(req_sync[2]&&initialized)begin state<=ACK;fifo_clear<=1;read_ack<=1;end
    ACK:begin
     fifo_clear<=1;read_ack<=1;
     shift<=meta1[10:0];cut<=WIDTH-meta1[10:0];old_latched<=meta1[11];new_latched<=meta1[12];reveal_latched<=meta1[13];
     row<=0;row_base<=0;accepted_pixels<=0;bursts<=0;
     if(!req_sync[2])begin
      fifo_clear<=0;read_ack<=0;
      if(meta1[10:0]>WIDTH || (meta1[10:0]!=0 && (!meta1[14] || meta1[11]==meta1[12])))begin
       protocol_error<=1;state<=IDLE;
      end else state<=ROW;
     end
    end
    ROW:begin segment<=shift==WIDTH;left<=shift==WIDTH?shift:cut;state<=DESC;end
    DESC:begin
     head<=start_x[7:0];
     burst_base<=(selected_bank?WORDS:0)+row_base+{start_x[10:8],8'd0};
     state<=CHECK;
    end
    CHECK:if(req_sync[2])begin state<=ACK;fifo_clear<=1;read_ack<=1;end
     else if(!memory_busy&&!writer_busy&&fifo_used<FIFO_DEPTH-256)begin
      take<=take_next;keep_first<={1'b0,head};keep_end<={1'b0,head}+take_next;
      issued<=0;received<=0;address<=burst_base;bursts<=bursts+1'b1;state<=BURST;
     end
    BURST:begin
     if(app_read)begin issued<=issued+1'b1;address<=address+1'b1;end
     if(memory_valid)begin
      received<=received+1'b1;
      if(received==255)state<=ADVANCE;
     end
    end
    ADVANCE:if(left>take)begin
      left<=left-take;head<=0;burst_base<=burst_base+256;state<=CHECK;
     end else if(!segment && shift!=0)begin segment<=1;left<=shift;state<=DESC;end
     else if(row==HEIGHT-1)state<=DONE;
     else begin row<=row+1'b1;row_base<=row_base+WIDTH;state<=ROW;end
    DONE:begin frame_done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
