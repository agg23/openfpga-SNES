`timescale 1ns/1ps
// Independent, deliberately restricted device/pin model for AS4C32M16MSA-6BIN.
// Source: Alliance Rev1.0 Dec2017, pp5-13,16-18,43-44. See README.md.
// This is not a vendor model. Supports BL1/CL3, explicit PRE, normal AR only.
// Nanosecond limits below are independent of the DUT's integer-cycle constants.
// R is SYNTHETIC aggregate roundtrip delay, not a measured board parameter.
module as4c32m16msa_model #(
    parameter realtime RETURN_DELAY_NS = 3.0
)(
    input logic clk_mem, epoch_ok,
    input logic cke, cs_n, ras_n, cas_n, we_n,
    input logic [12:0] addr,
    input logic [1:0] ba, dqm,
    input logic [15:0] dq_out,
    input logic dq_oe,
    output wire [15:0] dq_in,
    output logic dq_valid = 0,
    output logic dq_driving = 0,
    output logic initialized = 0
);
    localparam realtime T_RCD=18.0, T_RP=18.0, T_RAS=48.0,
                        T_RAS_MAX=100000.0, T_RC=60.0, T_RRD=12.0,
                        T_RFC=80.0, T_WR=15.0, T_REFI=7812.5,
                        T_INIT=200000.0, T_AC=5.5, T_OH=2.5, T_HZ=6.0;
    localparam realtime EPS=0.0005;
    logic [15:0] mem [int unsigned];
    logic [15:0] return_data=0;
    logic [1:0] dqm_delay0=3, dqm_delay1=3;
    logic active[4];
    logic [12:0] open_row[4];
    realtime last_act[4], last_pre[4], last_write[4];
    integer last_write_edge[4];
    realtime last_any_act, last_ar, last_mode, epoch_start;
    realtime previous_external=-1.0, previous_transition=-1.0;
    realtime command_changed=-1.0, data_changed=-1.0, last_sample=-1.0;
    realtime last_write_sample=-1.0;
    realtime max_refresh_gap=0.0, first_pre_time=-1.0;
    integer edge_number=0, mode_edge=-100, read_launch_edge=-1;
    integer read_clear_edge=-1, init_ar_count=0;
    integer epoch_count=0, total_ar=0, runtime_ar=0;
    integer total_act=0, total_read=0, total_write=0, total_pre=0;
    integer mr_count=0, emr_count=0;
    integer refresh_row=0;
    bit pre_seen=0, mr_seen=0, emr_seen=0, nop_seen=0;
    bit corrupt_read=0;
    logic [15:0] pending_word;
    bit [32767:0] rows_written=0, rows_read=0;
    bit [1023:0] columns_written=0, columns_read=0;
    assign dq_in = dq_valid ? return_data : 16'hxxxx;

    initial begin
        corrupt_read=$test$plusargs("corrupt_read");
        for(integer b=0;b<4;b++) begin
            active[b]=0; open_row[b]=0;
            last_act[b]=-1.0e12; last_pre[b]=-1.0e12;
            last_write[b]=-1.0e12; last_write_edge[b]=-100;
        end
        last_any_act=-1.0e12; last_ar=-1.0e12;
        last_mode=-1.0e12; epoch_start=0;
    end

    task automatic violation(input string tag, input string details);
        $fatal(1,"SDRAM_MODEL[%s] at %0.3f ns: %s",tag,$realtime,details);
    endtask

    // epoch_ok is a test abstraction: this chip has NO external reset pin.
    // Reset/relock tests validate the controller's full reinitialization, and
    // deliberately make no claim of preserving contents through that event.
    always @(negedge epoch_ok) begin
        initialized=0; pre_seen=0; mr_seen=0; emr_seen=0; nop_seen=0;
        init_ar_count=0; mode_edge=-100; read_launch_edge=-1;
        read_clear_edge=-1; dq_valid=0; dq_driving=0;
        last_ar=-1.0e12; last_mode=-1.0e12; last_any_act=-1.0e12;
        dqm_delay0=3; dqm_delay1=3;
        mem.delete();
        for(integer b=0;b<4;b++) begin
            active[b]=0; last_act[b]=-1.0e12; last_pre[b]=-1.0e12;
            last_write[b]=-1.0e12; last_write_edge[b]=-100;
        end
    end
    always @(posedge epoch_ok) begin
        epoch_start=$realtime;
        epoch_count++;
        previous_external=-1.0;
    end

    // Digital command setup/hold only. FPGA/PCB electrical paths, jitter and SI
    // are absent, so these assertions cannot establish fitted board timing.
    always @(cke or cs_n or ras_n or cas_n or we_n or addr or ba or dqm) begin
        if(epoch_ok && last_sample>=epoch_start && $realtime-last_sample<1.0-EPS)
            violation("INPUT_HOLD","command/address/DQM/CKE changed before 1 ns");
        command_changed=$realtime;
    end
    always @(dq_out or dq_oe) begin
        if(epoch_ok && last_write_sample>=epoch_start && $realtime-last_write_sample<1.0-EPS)
            violation("WRITE_HOLD","write DQ or OE changed before 1 ns");
        data_changed=$realtime;
    end
    always @(dq_oe or dq_driving) begin
        if(epoch_ok && dq_oe && dq_driving)
            violation("CONTENTION","controller and device output enables overlap");
    end
    always @(clk_mem) begin
        if(epoch_ok && previous_transition>=epoch_start &&
           $realtime-previous_transition<2.5-EPS)
            violation("CLOCK_PULSE","clock high or low width below 2.5 ns");
        previous_transition=$realtime;
    end

    task automatic require_idle;
        for(integer b=0;b<4;b++) begin
            if(active[b]) violation("BANKS_ACTIVE","command requires all banks idle");
            if($realtime-last_pre[b]<T_RP-EPS)
                violation("T_RP","all-bank command too soon after PRE");
        end
    endtask
    task automatic require_initialized;
        if(!pre_seen) violation("MISSING_PRE","operational command before PRE ALL");
        if(init_ar_count<2) violation("MISSING_AR","operational command before two initialization ARs");
        if(!mr_seen) violation("MISSING_MR","operational command before MR");
        if(!emr_seen) violation("MISSING_EMR","operational command before EMR");
        if(edge_number-mode_edge<2) violation("T_MRD","operation less than two clocks after mode load");
    endtask

    // External rising DRAM clock is the FPGA memory clock's FALLING edge.
    always @(negedge clk_mem) begin : device_edge
        logic [2:0] command;
        int unsigned key;
        logic [15:0] word_value;
        edge_number++;
        if(epoch_ok) begin
            if(previous_external>=epoch_start && $realtime-previous_external<6.0-EPS)
                violation("CLOCK_PERIOD","CL3 clock period below 6 ns");
            previous_external=$realtime;
            if($realtime-command_changed<2.0-EPS)
                violation("INPUT_SETUP","command/address/DQM/CKE setup below 2 ns");
            last_sample=$realtime;
            if(pre_seen && mr_seen && emr_seen && init_ar_count>=2 &&
               edge_number-mode_edge>=2 && $realtime-last_ar>=T_RFC-EPS)
                initialized=1;
            if(initialized && $realtime-last_ar>T_REFI+EPS)
                violation("REFRESH_LATE","distributed AR gap exceeds 7.8125 us");
            for(integer b=0;b<4;b++)
                if(active[b] && $realtime-last_act[b]>T_RAS_MAX+EPS)
                    violation("T_RAS_MAX","active row held beyond 100 us");

            if(edge_number==read_launch_edge) begin
                if(dqm_delay1!=0)
                    violation("READ_MASK","BL1 read output masked by DQM two clocks earlier");
                return_data <= #(T_AC+RETURN_DELAY_NS) (pending_word ^ (corrupt_read ? 16'h0001 : 16'h0000));
                dq_valid <= #(T_AC+RETURN_DELAY_NS) 1;
                dq_driving=1;
                read_clear_edge=edge_number+1;
                read_launch_edge=-1;
            end
            if(edge_number==read_clear_edge) begin
                // Destroy data at the EARLIEST permitted hold boundary; a
                // stable/floating bus cannot accidentally make a late read pass.
                dq_valid <= #(T_OH+RETURN_DELAY_NS) 0;
                dq_driving <= #(T_HZ+RETURN_DELAY_NS) 0;
                read_clear_edge=-1;
            end
            dqm_delay1=dqm_delay0;
            dqm_delay0=dqm;
            command={ras_n,cas_n,we_n};
            if(!cke || cs_n || command==3'b111) begin
                if(cke && (cs_n || command==3'b111)) nop_seen=1;
            end else begin
                if($realtime-epoch_start<T_INIT-EPS)
                    violation("INIT_WAIT","non-NOP before 200 us stable-clock epoch");
                if(!nop_seen) violation("INIT_NOP","no NOP/inhibit during 200 us wait");
                if($realtime-last_ar<T_RFC-EPS)
                    violation("T_RFC","executable command less than 80 ns after AR");
                if(edge_number-mode_edge<2)
                    violation("T_MRD","executable command less than two clocks after mode load");
                case(command)
                    3'b010: begin // PRECHARGE, explicit single bank or ALL
                        if(!pre_seen && !addr[10])
                            violation("INIT_PRE_ALL","initial PRE did not cover all banks");
                        for(integer b=0;b<4;b++) if(addr[10] || ba==2'(b)) begin
                            if(active[b] && $realtime-last_act[b]<T_RAS-EPS)
                                violation("T_RAS","PRE less than 48 ns after ACT");
                            if($realtime-last_write[b]<T_WR-EPS || edge_number-last_write_edge[b]<2)
                                violation("T_WR","PRE less than 15 ns/two clocks after write");
                            active[b]=0;
                            last_pre[b]=$realtime;
                        end
                        if(!pre_seen) first_pre_time=$realtime;
                        pre_seen=1; total_pre++;
                    end
                    3'b001: begin // AUTO REFRESH
                        if(!pre_seen) violation("MISSING_PRE","AR before PRE ALL");
                        require_idle();
                        if(!initialized && init_ar_count>0 && $realtime-last_ar<160.0-EPS)
                            violation("INIT_AR_SPACING","initial AR separation below conservative 160 ns");
                        if(initialized) begin
                            runtime_ar++;
                            if($realtime-last_ar>max_refresh_gap) max_refresh_gap=$realtime-last_ar;
                        end else init_ar_count++;
                        total_ar++; last_ar=$realtime;
                        refresh_row=(refresh_row+1)%8192;
                    end
                    3'b000: begin // LOAD MODE REGISTER / EXTENDED MODE REGISTER
                        if(!pre_seen) violation("MISSING_PRE","mode load before PRE ALL");
                        require_idle();
                        if(ba==0) begin
                            if(addr!=13'h030 && addr!=13'h230)
                                violation("BAD_MR","expected BL1 CL3, sequential, standard mode");
                            mr_seen=1; mr_count++;
                        end else if(ba==2) begin
                            if(addr!=0) violation("BAD_EMR","expected all banks, full drive EMR=0");
                            emr_seen=1; emr_count++;
                        end else violation("BAD_MODE_BANK","mode register bank select must be 00 or 10");
                        last_mode=$realtime; mode_edge=edge_number;
                    end
                    3'b011: begin // ACTIVE
                        require_initialized();
                        if(active[ba]) violation("BANK_ACTIVE","ACT on already open bank");
                        if($realtime-last_pre[ba]<T_RP-EPS)
                            violation("T_RP","ACT less than 18 ns after PRE");
                        if($realtime-last_act[ba]<T_RC-EPS)
                            violation("T_RC","same-bank ACT separation below 60 ns");
                        if($realtime-last_any_act<T_RRD-EPS)
                            violation("T_RRD","ACT separation below 12 ns");
                        active[ba]=1; open_row[ba]=addr;
                        last_act[ba]=$realtime; last_any_act=$realtime; total_act++;
                    end
                    3'b101,3'b100: begin // READ/WRITE
                        require_initialized();
                        if(!active[ba]) violation("BANK_CLOSED","READ/WRITE without ACT");
                        if($realtime-last_act[ba]<T_RCD-EPS)
                            violation("T_RCD","READ/WRITE less than 18 ns after ACT");
                        if(addr[12:10]!=0)
                            violation("COLUMN_BITS","A10 auto-precharge or reserved upper column bits set");
                        // Data is indexed from observed physical command pins,
                        // never from the DUT request/address or helper function.
                        key={7'b0,ba,open_row[ba],addr[9:0]};
                        if(command==3'b100) begin
                            if(!dq_oe) violation("WRITE_OE","write without controller DQ output enabled");
                            if($realtime-data_changed<2.0-EPS)
                                violation("WRITE_SETUP","write DQ/OE setup below 2 ns");
                            word_value=(mem.exists(key)!=0) ? mem[key] : 16'h0000;
                            if(!dqm[0]) word_value[7:0]=dq_out[7:0];
                            if(!dqm[1]) word_value[15:8]=dq_out[15:8];
                            mem[key]=word_value; last_write[ba]=$realtime;
                            last_write_edge[ba]=edge_number; last_write_sample=$realtime;
                            total_write++; rows_written[{ba,open_row[ba]}]=1;
                            columns_written[addr[9:0]]=1;
                        end else begin
                            if(dq_oe) violation("READ_OE","controller drives DQ during READ command");
                            if(mem.exists(key)==0) violation("UNWRITTEN_READ","test read an uninitialized physical location");
                            if(read_launch_edge>=0 || dq_driving)
                                violation("OVERLAP_READ","model restricted to one in-flight BL1 read");
                            pending_word=mem[key]; read_launch_edge=edge_number+2;
                            total_read++; rows_read[{ba,open_row[ba]}]=1;
                            columns_read[addr[9:0]]=1;
                        end
                    end
                    default: violation("UNSUPPORTED_COMMAND","unsupported burst/power command");
                endcase
            end
        end
    end
endmodule
