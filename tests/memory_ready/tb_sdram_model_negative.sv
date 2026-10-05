`timescale 1ns/1ps
// Direct-pin controls, independent of the DUT. Each named bad sequence must
// fail with its intended device-model diagnostic, not an unrelated timeout.
module tb_sdram_model_negative;
    localparam realtime T=9.312;
    logic clk_mem=0;
    always #(T/2) clk_mem=~clk_mem;
    logic epoch_ok=0,cke=0,cs_n=1,ras_n=1,cas_n=1,we_n=1;
    logic [12:0] addr=0;
    logic [1:0] ba=0,dqm=3;
    logic [15:0] dq_out=0;
    logic dq_oe=0;
    wire [15:0] dq_in;
    wire dq_valid,dq_driving,initialized;
    as4c32m16msa_model model(.*);
    string test_case;
    task automatic launch(input logic [2:0] c,input logic [1:0] b=0,
                          input logic [12:0] a=0,input bit drive=0);
        @(posedge clk_mem);#0.001;
        cke=1;cs_n=0;{ras_n,cas_n,we_n}=c;ba=b;addr=a;dq_oe=drive;
        dq_out=16'hc35a;
        @(negedge clk_mem);#0.001;
    endtask
    task automatic nops(input integer n);
        repeat(n) launch(3'b111);
    endtask
    task automatic power_wait;
        repeat(3) @(posedge clk_mem);
        #0.001;epoch_ok=1;cke=1;cs_n=0;
        nops(21480);
    endtask
    task automatic initialize(input bit load_mr=1,input bit load_emr=1,
                              input bit two_ar=1);
        power_wait();
        launch(3'b010,0,13'h400);nops(1);
        launch(3'b001);nops(17);
        if(two_ar) begin launch(3'b001);nops(17);end
        if(load_mr) begin launch(3'b000,0,13'h230);nops(1);end
        if(load_emr) begin launch(3'b000,2,0);nops(1);end
        nops(1);@(posedge clk_mem);#0.001;dqm=0;
        // DQM change after a sample is postponed to the next launch edge.
        // The testbench changes only on FPGA rising edges in subsequent tasks.
    endtask
    initial begin
        if(!$value$plusargs("case=%s",test_case)) test_case="valid";
        if(test_case=="init_wait") begin
            repeat(3) @(posedge clk_mem);#0.001;epoch_ok=1;cke=1;cs_n=0;
            nops(10);launch(3'b010,0,13'h400);
        end else if(test_case=="missing_mr") begin
            initialize(0,1,1);launch(3'b011);
        end else if(test_case=="missing_emr") begin
            initialize(1,0,1);launch(3'b011);
        end else if(test_case=="missing_ar") begin
            initialize(1,1,0);launch(3'b011);
        end else if(test_case=="init_ar_spacing") begin
            power_wait();launch(3'b010,0,13'h400);nops(1);
            launch(3'b001);nops(8);launch(3'b001);
        end else if(test_case=="bad_mr") begin
            power_wait();launch(3'b010,0,13'h400);nops(1);
            launch(3'b000,0,13'h220);
        end else if(test_case=="t_mrd") begin
            power_wait();launch(3'b010,0,13'h400);nops(1);
            launch(3'b000,0,13'h230);launch(3'b000,2,0);
        end else begin
            initialize();
            case(test_case)
                "t_rp_act": begin launch(3'b010,0,13'h400);launch(3'b011);end
                "t_rcd": begin launch(3'b011);launch(3'b101);end
                "t_ras": begin launch(3'b011);nops(1);launch(3'b010);end
                "t_wr": begin
                    launch(3'b011);nops(5);launch(3'b100,0,0,1);launch(3'b010);
                end
                "t_rp_ar": begin launch(3'b010,0,13'h400);launch(3'b001);end
                "t_rfc": begin launch(3'b001);nops(1);launch(3'b011);end
                "t_rrd": begin launch(3'b011,0);launch(3'b011,1);end
                "banks_active": begin launch(3'b011);nops(8);launch(3'b001);end
                "refresh_late": nops(850);
                "contention": begin
                    launch(3'b011);nops(1);launch(3'b100,0,0,1);nops(3);
                    launch(3'b010);nops(1);launch(3'b011);nops(1);
                    launch(3'b101);nops(1);launch(3'b111,0,0,1);
                end
                "valid": begin
                    launch(3'b011);nops(1);launch(3'b100,0,0,1);nops(3);
                    launch(3'b010);nops(1);launch(3'b011);nops(1);
                    launch(3'b101);nops(5);launch(3'b010);nops(1);
                    launch(3'b001);nops(17);
                    $display("PASS direct-pin positive control");$finish;
                end
                default: $fatal(1,"unknown negative-control case %s",test_case);
            endcase
        end
        nops(20);
        $fatal(1,"TB_NEGATIVE_NOT_DETECTED: %s",test_case);
    end
    initial begin #1000000;$fatal(1,"TB_NEGATIVE_WATCHDOG");end
endmodule
