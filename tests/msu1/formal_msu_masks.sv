// SPDX-License-Identifier: MIT
// Pure-expression miter for all 32-bit relative addresses, 16-bit lengths,
// activity states, and four byte lanes. This is not a sequential host proof.
module mask_equiv(input [31:0] relative_addr, input [15:0] transfer_length, input active, output equivalent);
wire [3:0] original_mask, short_mask;
genvar lane;
generate for(lane=0;lane<4;lane=lane+1)begin
 assign original_mask[lane] = active && relative_addr < {16'd0,transfer_length} && relative_addr + lane < {16'd0,transfer_length};
 assign short_mask[lane] = active && relative_addr < {16'd0,transfer_length} && {1'b0,relative_addr[15:0]} + 17'(lane) < {1'b0,transfer_length};
end endgenerate
assign equivalent = original_mask == short_mask;
endmodule
