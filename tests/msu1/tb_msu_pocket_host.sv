// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module tb_msu_pocket_host;
    reg clk=0; always #5 clk=~clk;
    reg reset=1, init_req=0;
    wire init_done,msu_present;
    wire [31:0] data_size;
    reg data_req=0; reg [31:0] data_offset=0; reg [15:0] data_length=0;
    wire data_ack,data_done; wire [2:0] data_error; wire [15:0] data_actual;
    reg pcm_open_req=0; reg [15:0] pcm_track=0;
    wire pcm_open_ack,pcm_open_done; wire [2:0] pcm_open_error; wire [31:0] pcm_size;
    reg pcm_read_req=0; reg [31:0] pcm_offset=0; reg [15:0] pcm_length=0;
    wire pcm_read_ack,pcm_read_done; wire [2:0] pcm_read_error; wire [15:0] pcm_actual;
    reg [31:0] bridge_addr=0,bridge_wr_data=0;
    reg bridge_wr=0,bridge_rd=0,bridge_endian_little=0;
    wire [31:0] bridge_rd_data;
    wire data_we,pcm_we; wire [15:0] data_waddr,pcm_waddr;
    wire [31:0] data_wdata,pcm_wdata; wire [3:0] data_wmask,pcm_wmask;
    wire target_dataslot_read,target_dataslot_write,target_dataslot_getfile,target_dataslot_openfile;
    reg target_dataslot_ack=0,target_dataslot_done=1; reg [2:0] target_dataslot_err=0;
    wire [15:0] target_dataslot_id;
    wire [31:0] target_dataslot_slotoffset,target_dataslot_bridgeaddr,target_dataslot_length;
    wire [31:0] target_buffer_param_struct,target_buffer_resp_struct;
    msu_pocket_host #(.COMMAND_TIMEOUT(1000)) dut(.*);
    string rom_name="/Assets/snes/common/sub.dir/Chrono.Test.sfc";
    string expected_name;
    reg [2:0] get_error=0,open_error=0,read_error=0;
    reg stall=0;
    integer command_count=0, data_byte_count=0,pcm_byte_count=0;
    reg [7:0] data_bytes[0:65535],pcm_bytes[0:65535];
    integer lane;
    always @(posedge clk) begin
        for (integer k=0;k<4;k=k+1) begin
            if(data_we && data_wmask[k]) begin
                data_bytes[data_waddr+k]=data_wdata[k*8 +: 8];
                data_byte_count=data_byte_count+1;
            end
            if(pcm_we && pcm_wmask[k]) begin
                pcm_bytes[pcm_waddr+k]=pcm_wdata[k*8 +: 8];
                pcm_byte_count=pcm_byte_count+1;
            end
        end
    end
    function automatic [31:0] swap32(input[31:0] value);
        swap32={value[7:0],value[15:8],value[23:16],value[31:24]};
    endfunction
    task automatic write_word(input[31:0] address,input[31:0] value);
        begin
            @(negedge clk);bridge_addr=address;bridge_wr_data=value;bridge_wr=1;
            @(negedge clk);bridge_wr=0;
        end
    endtask
    task automatic write_numeric(input[31:0] address,input[31:0] value);
        write_word(address,bridge_endian_little?swap32(value):value);
    endtask
    task automatic write_file(input[31:0] address,input[31:0] value);
        write_word(address,bridge_endian_little?value:swap32(value));
    endtask
    task automatic write_size(input integer entry,input[15:0] id,input[31:0] size);
        begin
            write_numeric(32'hF8002000+entry*8,{16'd0,id});
            write_numeric(32'hF8002004+entry*8,size);
        end
    endtask
    // Exercise the RAM port contract independently of the command model:
    // back-to-back reads, old data on a simultaneous write, result retention
    // when the address/endian change without a read, and the zero tail words.
    task automatic check_path_ram;
        reg [31:0] want, held;
        begin
            for (integer endian=0; endian<2; endian=endian+1) begin
                bridge_endian_little=endian[0];
                for (integer j=0; j<64; j=j+1)
                    write_file(target_buffer_resp_struct+j*4,32'h10203040+j);
                @(negedge clk);
                bridge_rd=1;
                for (integer j=0; j<64; j=j+1) begin
                    bridge_addr=target_buffer_param_struct+j*4;
                    @(negedge clk);
                    want=32'h10203040+j;
                    if (bridge_rd_data !== (endian[0]?want:swap32(want)))
                        $fatal(1,"Path RAM read latency/data at word %0d",j);
                end
                bridge_addr=target_buffer_param_struct;
                bridge_wr=1;
                bridge_wr_data=endian[0]?32'hA1B2C3D4:swap32(32'hA1B2C3D4);
                @(negedge clk);
                want=32'h10203040;
                if (bridge_rd_data !== (endian[0]?want:swap32(want)))
                    $fatal(1,"Path RAM read-during-write must return old data");
                bridge_wr=0;
                @(negedge clk);
                want=32'hA1B2C3D4;
                if (bridge_rd_data !== (endian[0]?want:swap32(want)))
                    $fatal(1,"Path RAM write visibility");
                bridge_rd=0;
                held=bridge_rd_data;
                bridge_addr=32'hF8002000;
                bridge_endian_little=!endian[0];
                repeat(3)@(negedge clk);
                if (bridge_rd_data !== held)
                    $fatal(1,"Path RAM response did not retain address/endian");
                bridge_rd=1; // An unrelated read must also retain the response.
                @(negedge clk);
                if (bridge_rd_data !== held)$fatal(1,"Unrelated read changed path response");
                bridge_addr=target_buffer_param_struct+256;
                @(negedge clk);
                if (bridge_rd_data !== 0)$fatal(1,"Path flags must be zero");
                bridge_addr=target_buffer_param_struct+260;
                @(negedge clk);
                if (bridge_rd_data !== 0)$fatal(1,"Path size must be zero");
                bridge_rd=0;
            end
            bridge_endian_little=0;
        end
    endtask
    task automatic get_path(output string value);
        reg[31:0] w; reg[7:0] c;
        begin
            value="";
            for(integer j=0;j<64;j=j+1) begin
                @(negedge clk);bridge_addr=target_buffer_param_struct+j*4;bridge_rd=1;
                @(negedge clk);bridge_rd=0;
                w=bridge_endian_little?bridge_rd_data:swap32(bridge_rd_data);
                for(integer k=0;k<4;k=k+1) begin
                    c=w[k*8 +:8];
                    if(c!=0) value={value,c};
                    else begin j=64; k=4; end
                end
            end
            // Flags and requested size must always be zero: no file writes.
            for(integer j=256;j<=260;j=j+4) begin
                @(negedge clk);bridge_addr=target_buffer_param_struct+j;bridge_rd=1;
                @(negedge clk);bridge_rd=0;
                if(bridge_rd_data!==0)$fatal(1,"Nonzero open flags/size");
            end
        end
    endtask
    // Model command latency, including stale sticky done during local enqueue.
    initial begin : apf
        reg [2:0] result;
        reg [31:0] word_data,off,len,dest;
        reg [15:0] id;
        reg is_get,is_open;
        string opened_path;
        forever begin
            @(posedge clk);
            if(target_dataslot_read || target_dataslot_getfile || target_dataslot_openfile) begin
                command_count=command_count+1;
                if(stall) begin
                    repeat(1200) @(posedge clk);
                end else begin
                    is_get=target_dataslot_getfile;
                    is_open=target_dataslot_openfile;
                    id=target_dataslot_id;off=target_dataslot_slotoffset;
                    len=target_dataslot_length;dest=target_dataslot_bridgeaddr;
                    repeat(3) @(negedge clk);
                    target_dataslot_done=0;target_dataslot_ack=0;
                    repeat(3) @(negedge clk);
                    target_dataslot_ack=1;
                    if(is_get) begin
                        if(id!==0)$fatal(1,"Wrong ROM slot");
                        result=get_error;
                        if(!get_error) begin
                            for(integer j=0;j<256;j=j+4) begin
                                word_data=0;
                                for(integer k=0;k<4;k=k+1)
                                    if(j+k<rom_name.len())word_data[k*8 +:8]=rom_name[j+k];
                                write_file(target_buffer_resp_struct+j,word_data);
                            end
                        end
                    end else if(is_open) begin
                        get_path(opened_path);
                        if(opened_path != expected_name)
                            $fatal(1,"Path mismatch: expected %s got %s",expected_name,opened_path);
                        result=open_error;
                        if(open_error==0) begin
                            if(id==100)write_size(2,id,32'd8193);
                            else if(id==101)write_size(3,id,32'd1033);
                            else $fatal(1,"Wrong dynamic slot");
                        end
                    end else begin
                        result=read_error;
                        if(!read_error) begin
                            for(integer j=0;j<len;j=j+4) begin
                                word_data=0;
                                for(integer k=0;k<4;k=k+1)word_data[k*8 +:8]=(off+j+k)&255;
                                write_file(dest+j,word_data);
                            end
                        end
                    end
                    repeat(3)@(negedge clk);
                    target_dataslot_ack=0;target_dataslot_err=result;target_dataslot_done=1;
                end
            end
        end
    end
    task automatic initialize;
        begin
            @(negedge clk);init_req=1;
            @(negedge clk);init_req=0;
            wait(init_done);@(negedge clk);
        end
    endtask
    task automatic open_track(input[15:0] track,input string name);
        begin
            expected_name=name;pcm_track=track;
            @(negedge clk);pcm_open_req=1;
            wait(pcm_open_ack);@(negedge clk);pcm_open_req=0;
            wait(pcm_open_done);@(negedge clk);
        end
    endtask
    task automatic data_read(input[31:0] off,input[15:0] len);
        begin
            data_byte_count=0;data_offset=off;data_length=len;
            @(negedge clk);data_req=1;
            wait(data_ack);@(negedge clk);data_req=0;
            wait(data_done);@(negedge clk);
        end
    endtask
    task automatic pcm_read(input[31:0] off,input[15:0] len);
        begin
            pcm_byte_count=0;pcm_offset=off;pcm_length=len;
            @(negedge clk);pcm_read_req=1;
            wait(pcm_read_ack);@(negedge clk);pcm_read_req=0;
            wait(pcm_read_done);@(negedge clk);
        end
    endtask
    integer old_count;
    string long_base;
    reg saw_data_done,saw_pcm_done;
    always @(posedge clk) begin
        if(data_done)saw_data_done<=1;
        if(pcm_read_done)saw_pcm_done<=1;
    end
    initial begin
        repeat(5)@(negedge clk);reset=0;
        if(bridge_rd_data!==0)$fatal(1,"Reset path response must be zero");
        check_path_ram();
        expected_name="/Assets/snes/common/sub.dir/Chrono.Test.msu";
        fork
            initialize();
            begin
                // A late APF word cannot steal a local suffix byte or get lost.
                // Word 63 is beyond this short filename's terminator.
                wait(dut.state == 5); // BUILD_MSU
                write_file(target_buffer_resp_struct+252,32'h5A3CC3A5);
            end
        join
        if(!msu_present || data_size!=8193)$fatal(1,"MSU init failed");
        @(negedge clk);bridge_addr=target_buffer_param_struct+252;bridge_rd=1;
        @(negedge clk);bridge_rd=0;
        if(bridge_rd_data!==swap32(32'h5A3CC3A5))$fatal(1,"Concurrent APF path write lost");
        data_read(32'd8188,16'd16);
        if(data_error || data_actual!=5 || data_byte_count!=5)$fatal(1,"Final partial data transfer");
        for(integer j=0;j<5;j=j+1)if(data_bytes[j]!==((8188+j)&255))$fatal(1,"Data byte endian");
        old_count=command_count;data_read(8193,10);
        if(data_error || data_actual || command_count!=old_count)$fatal(1,"EOF should not launch read");
        data_read(32'hFFFFFFFF,16'hFFFF);
        if(data_error || data_actual || command_count!=old_count)$fatal(1,"Overflow-safe EOF");
        open_track(16'd65535,"/Assets/snes/common/sub.dir/Chrono.Test-65535.pcm");
        if(pcm_open_error || pcm_size!=1033)$fatal(1,"PCM open failed");
        pcm_read(8,1024);
        if(pcm_read_error || pcm_actual!=1024 || pcm_byte_count!=1024)$fatal(1,"PCM transfer length");
        for(integer j=0;j<1024;j=j+1)if(pcm_bytes[j]!==((j+8)&255))$fatal(1,"PCM byte endian");
        open_track(16'd0,"/Assets/snes/common/sub.dir/Chrono.Test-0.pcm");
        if(pcm_open_error)$fatal(1,"Track zero decimal");
        open_error=3;
        open_track(16'd42,"/Assets/snes/common/sub.dir/Chrono.Test-42.pcm");
        if(pcm_open_error!=3)$fatal(1,"Missing PCM error");
        old_count=command_count;pcm_read(0,8);
        if(pcm_read_error!=3 || pcm_actual!=0 || command_count!=old_count)$fatal(1,"Failed open retained old PCM");
        open_error=0;
        open_track(16'd9,"/Assets/snes/common/sub.dir/Chrono.Test-9.pcm");
        read_error=2;data_read(0,4);
        if(data_error!=2 || data_actual!=0)$fatal(1,"Read error must invalidate transfer");
        read_error=0;
        // A soft game init must derive the basename afresh and handle dotless
        // filenames below a directory containing a dot.
        bridge_endian_little=1;
        rom_name="/Assets/snes/common/a.dir/NoExtension";
        expected_name="/Assets/snes/common/a.dir/NoExtension.msu";
        initialize();
        if(!msu_present)$fatal(1,"Little-endian bootstrap");
        data_read(0,4);
        if(data_error || data_bytes[0]!=0 || data_bytes[1]!=1 || data_bytes[2]!=2 || data_bytes[3]!=3)
            $fatal(1,"Little-endian data transfer");
        open_track(16'd100,"/Assets/snes/common/a.dir/NoExtension-100.pcm");
        if(pcm_open_error)$fatal(1,"Decimal embedded zero");
        // Both clients may remain valid while one owns the APF channel.
        saw_data_done=0;saw_pcm_done=0;
        @(negedge clk);data_offset=0;data_length=8;data_req=1;
        pcm_offset=8;pcm_length=8;pcm_read_req=1;
        fork
            begin wait(data_ack);@(negedge clk);data_req=0; end
            begin wait(pcm_read_ack);@(negedge clk);pcm_read_req=0; end
        join
        wait(saw_data_done && saw_pcm_done);@(negedge clk);
        if(data_error || pcm_read_error)$fatal(1,"Concurrent request arbitration");
        // Filename boundary: maximum valid MSU path occupies 255 bytes plus NUL.
        long_base="/Assets/snes/common/";
        while(long_base.len()<251)long_base={long_base,"x"};
        rom_name={long_base,".sfc"};expected_name={long_base,".msu"};
        initialize();if(!msu_present)$fatal(1,"255-byte path rejected");
        old_count=command_count;
        open_track(0,"");
        if(pcm_open_error!=4 || command_count!=old_count)$fatal(1,"Overlong PCM path was not rejected before open");
        // A one-digit track can fit a longer basename than a five-digit track.
        long_base="/Assets/snes/common/";
        while(long_base.len()<249)long_base={long_base,"y"};
        rom_name={long_base,".sfc"};expected_name={long_base,".msu"};
        initialize();if(!msu_present)$fatal(1,"Long base init");
        open_track(9,{long_base,"-9.pcm"});
        if(pcm_open_error)$fatal(1,"Exact-fit one-digit PCM path");
        old_count=command_count;open_track(65535,"");
        if(pcm_open_error!=4 || command_count!=old_count)$fatal(1,"Long five-digit PCM path");
        // Non-terminated host input cannot walk beyond 256-byte RAM.
        rom_name="";repeat(256)rom_name={rom_name,"z"};
        old_count=command_count;initialize();
        if(msu_present || command_count!=old_count+1)$fatal(1,"Unterminated path not rejected");
        rom_name="/Assets/snes/common/a.dir/NoExtension";
        // Missing .msu is normal and must release core initialization.
        open_error=3;expected_name="/Assets/snes/common/a.dir/NoExtension.msu";
        initialize();if(msu_present)$fatal(1,"Missing MSU detection");
        open_error=0;
        // A missing ROM filename also terminates initialization.
        get_error=1;initialize();if(msu_present)$fatal(1,"Missing ROM detection");
        get_error=0;
        // Fatal timeout does not recycle the channel while APF may still own it.
        stall=1;initialize();if(msu_present)$fatal(1,"Timeout MSU detection");
        old_count=command_count;data_read(0,4);
        if(data_error!=7 || command_count!=old_count)$fatal(1,"Timeout quarantine");
        $display("PASS tb_msu_pocket_host: paths, decimal tracks, sticky done, endian, EOF, missing files, errors, timeout");
        $finish;
    end
    initial begin repeat(20000)@(posedge clk);$fatal(1,"Testbench timeout");end
endmodule
