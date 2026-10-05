// SPDX-License-Identifier: GPL-3.0-or-later
// Two-block streaming cache. No .msu file is preloaded. A seek may supersede
// an in-flight read; the old response is safely drained and tagged by address.
module msu_data_cache #(
 parameter integer BLOCK_BYTES=4096,
 parameter integer BW=$clog2(BLOCK_BYTES)
)(
 input wire clk, reset, enable,
 input wire [31:0] file_size, data_addr,
 input wire data_seek, data_next,
 output reg data_ack, output wire [7:0] data,
 output wire busy, output reg underrun,
 output reg req_valid, input wire req_ready,
 output reg [31:0] req_offset, output reg [15:0] req_length,
 input wire resp_valid, output wire resp_ready,
 input wire [31:0] resp_data, input wire resp_done, resp_error
);
 (* ramstyle = "M10K, no_rw_check" *) reg [31:0] ram[0:2*(BLOCK_BYTES/4)-1];
 reg [31:BW] tag0,tag1,fill_tag;
 reg [1:0] valid, failed;
 reg fill_bank,active;
 reg [BW-2:0] wr_word;

 reg [31:0] q;
 reg [1:0] lane;
 reg [31:0] output_addr;
 reg output_valid;
 wire outside_file = data_addr>=file_size;
 wire hit0=valid[0] && tag0==data_addr[31:BW];
 wire hit1=valid[1] && tag1==data_addr[31:BW];
 wire hit=hit0||hit1;
 wire [31:0] block_addr={data_addr[31:BW],{BW{1'b0}}};
 wire [31:0] next_addr=block_addr+BLOCK_BYTES;
 wire next_hit=(valid[0] && {tag0,{BW{1'b0}}}==next_addr)||(valid[1] && {tag1,{BW{1'b0}}}==next_addr);
 // A cache miss is visible as busy. Software must honor busy when streaming
 // exceeds host throughput; there is deliberately no global SNES clock stop.
 assign busy=enable && !outside_file && (!hit || !output_valid || output_addr!=data_addr);
 assign data=(!enable||outside_file||busy||(hit0&&failed[0])||(hit1&&failed[1]))?8'h00:q[lane*8+:8];
 assign resp_ready=1'b1;
 always @(posedge clk) begin
   q<=ram[{hit1,data_addr[BW-1:2]}];lane<=data_addr[1:0];
   output_addr<=data_addr;output_valid<=hit;
   data_ack<=0;
   if(reset) begin
     output_valid<=0;output_addr<=0;valid<=0;failed<=0;active<=0;req_valid<=0;wr_word<=0;
     tag0<=0;tag1<=0;fill_tag<=0;fill_bank<=0;
     req_offset<=0;req_length<=0;underrun<=0;data_ack<=0;
   end else begin
     // Re-pulse until the requester lowers seek. This also services a new
     // same-address seek written exactly on an older acknowledgement edge.
     if(data_seek && !data_ack && (!busy || !enable)) data_ack<=1;
     if(data_next && busy) underrun<=1;
     if(req_valid && req_ready) begin req_valid<=0;active<=1;wr_word<=0;end
     if(active && resp_valid) begin
       ram[{fill_bank,wr_word[BW-3:0]}]<=resp_data;
       wr_word<=wr_word+1'b1;
     end
     if(active && resp_done) begin
       active<=0;
       begin
         failed[fill_bank]<=resp_error;
         valid[fill_bank]<=1;
         if(fill_bank) tag1<=fill_tag;else tag0<=fill_tag;
       end
     end
     if(enable && !active && !req_valid && !outside_file) begin
       if(!hit || (!next_hit && next_addr<file_size)) begin
         req_offset<=!hit?block_addr:next_addr;
         req_length<=16'(file_size-(!hit?block_addr:next_addr)>=BLOCK_BYTES ? BLOCK_BYTES : file_size-(!hit?block_addr:next_addr));
         fill_tag<=!hit?data_addr[31:BW]:next_addr[31:BW];
         // Never evict the current block to prefetch its successor.
         fill_bank<=hit0?1'b1:hit1?1'b0:!valid[0]?1'b0:1'b1;
         valid[hit0?1:hit1?0:!valid[0]?0:1]<=0;
         req_valid<=1;
       end
     end
   end
 end
endmodule
