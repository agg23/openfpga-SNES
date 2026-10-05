`timescale 1ns/1ps
// Observe the unchanged real engine and independent pin model's first read.
// A is the request/ACT launch edge. R is synthetic, not a PCB measurement.
module tb_standard_read_edge_trace;
    parameter integer CLK_HZ = 107386350;
    parameter realtime RETURN_DELAY_NS = 3.0;
    tb_sdram_single_request #(.CLK_HZ(CLK_HZ), .RETURN_DELAY_NS(RETURN_DELAY_NS)) base();
    integer cycle = -1;
    realtime accepted_at;
    bit sampled_valid;
    logic [15:0] sampled_value;
    always @(posedge base.clk_mem) begin
        if (cycle < 0 && base.req_valid && base.req_ready && !base.req_write) begin
            cycle = 0;
            accepted_at = $realtime;
            $display("EDGE A accepted read t=%0.3f", $realtime);
        end else if (cycle >= 0) cycle++;
        if (cycle == 6) begin
            sampled_valid = base.dq_valid;
            sampled_value = base.dq_in;
            $display("EDGE A+6 physical DQ capture dt=%0.3f valid=%b dq=%h", $realtime-accepted_at, sampled_valid, sampled_value);
        end
        if (cycle >= 0) begin
            #0.001;
            if (cycle == 2) begin
                if ({base.ras_n,base.cas_n,base.we_n} !== 3'b101)
                    $fatal(1,"EDGE_WRONG_READ_LAUNCH");
                $display("EDGE A+2 READ registered dt=%0.3f", $realtime-accepted_at-0.001);
            end
            if (cycle == 6 && base.dut.dq_sample !== sampled_value)
                $fatal(1,"EDGE_WRONG_DQ_SAMPLE");
            if (cycle == 7) begin
                $display("EDGE A+7 copy old dq_sample dt=%0.3f read_data=%h current_dq=%h", $realtime-accepted_at-0.001,base.dut.read_data,base.dq_in);
                if (!sampled_valid) $fatal(1,"EDGE_BAD_CAPTURE_WINDOW");
                if (base.dut.read_data !== sampled_value) $fatal(1,"EDGE_WRONG_INTERNAL_COPY");
                $display("PASS EDGE TRACE: CL3 E2 launch, A+6 physical capture, A+7 internal copy; synthetic R=%0.3f",RETURN_DELAY_NS);
                $finish;
            end
        end
    end
    always @(negedge base.clk_mem) begin
        if (cycle == 2) $display("EDGE E0=A+2.5 READ sampled by SDRAM dt=%0.3f",$realtime-accepted_at);
        if (cycle == 4) $display("EDGE E2=A+4.5 vendor DQ launching edge dt=%0.3f",$realtime-accepted_at);
        if (cycle == 5) $display("EDGE E3=A+5.5 vendor hold-reference edge dt=%0.3f",$realtime-accepted_at);
    end
    always @(base.dq_valid) if (cycle >= 0)
        $display("EDGE model dq_valid=%b dt=%0.3f",base.dq_valid,$realtime-accepted_at);
endmodule
