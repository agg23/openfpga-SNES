// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module tb_msu_host_masks;
    reg [31:0] bridge_addr=0;
    reg bridge_wr=1;
    wire [3:0] data_wmask, pcm_wmask;
    reg [15:0] forced_length;
    reg [2:0] forced_operation;
    msu_pocket_host dut (
        .clk(1'b0), .reset(1'b0), .bridge_addr(bridge_addr), .bridge_wr(bridge_wr),
        .bridge_rd(1'b0), .bridge_wr_data(32'd0), .bridge_endian_little(1'b0),
        .data_wmask(data_wmask), .pcm_wmask(pcm_wmask)
    );
    // Isolate the combinational packet mask at an already-accepted command.
    // The ordinary host/integration tests exercise entry to this command state.
    task check(input bit pcm, input [15:0] length, input [31:0] offset, input [3:0] expected);
        begin
            forced_length=length;
            forced_operation=pcm ? 4 : 3;
            force dut.state=3; // WAIT_DONE
            force dut.operation=forced_operation;
            force dut.transfer_length=forced_length;
            bridge_addr=(pcm ? 32'h90020000 : 32'h90010000)+offset;
            #1;
            if ((pcm ? pcm_wmask : data_wmask) !== expected ||
                (pcm ? data_wmask : pcm_wmask) !== 0)
                $fatal(1,"Mask boundary pcm=%0b length=%0d offset=%h",pcm,length,offset);
        end
    endtask
    initial begin
        for(integer pcm=0;pcm<2;pcm=pcm+1) begin
            check(pcm[0],0,0,0);
            check(pcm[0],1,0,1); check(pcm[0],1,1,0);
            check(pcm[0],3,0,7); check(pcm[0],3,1,3); check(pcm[0],3,2,1); check(pcm[0],3,3,0);
            check(pcm[0],4,0,15); check(pcm[0],4,3,1); check(pcm[0],4,4,0);
            check(pcm[0],65535,65531,15); check(pcm[0],65535,65532,7);
            check(pcm[0],65535,65533,3); check(pcm[0],65535,65534,1);
            check(pcm[0],65535,65535,0); check(pcm[0],65535,65536,0);
            check(pcm[0],65535,32'hfffffffd,0); check(pcm[0],65535,32'hffffffff,0);
        end
        bridge_wr=0; #1;
        if(data_wmask!==0 || pcm_wmask!==0)$fatal(1,"Inactive write mask");
        $display("PASS tb_msu_host_masks: both clients, partial lanes, 65535-byte limit and wrapped addresses");
        $finish;
    end
endmodule
