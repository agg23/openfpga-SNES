// SPDX-License-Identifier: GPL-3.0-or-later
// AS4C32M16MSA-6BIN, 64 MiB mobile SDRAM, single closed-page request.
// See docs/memory-ready-sdram-engine.md for protocol and physical-I/O boundary.
// clk_mem is the dedicated ~107/106 MHz 5x clock, NOT the PSRAM clock.
// Command pins launch on clk_mem rising; SDRAM clock rises on clk_mem falling.
// This module intentionally contains neither a clock primitive nor a tri-state.
module sdram_single_request #(
    parameter integer CLK_HZ = 107386350
) (
    input  wire        clk_mem,
    input  wire        reset_n,
    input  wire        pll_locked,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire        req_write,
    input  wire [31:0] req_addr,
    input  wire [15:0] req_wdata,
    input  wire [1:0]  req_wstrb,
    output reg         rsp_valid,
    input  wire        rsp_ready,
    output reg  [15:0] rsp_rdata,
    output reg         rsp_error,
    output reg         init_done,
    output reg         dram_cke,
    output reg         dram_cs_n,
    output reg         dram_ras_n,
    output reg         dram_cas_n,
    output reg         dram_we_n,
    output reg  [12:0] dram_addr,
    output reg  [1:0]  dram_ba,
    output reg  [1:0]  dram_dqm,
    input  wire [15:0] dq_in,
    output reg  [15:0] dq_out,
    output reg         dq_oe
);
    // 64-bit arithmetic avoids overflow of ns * Hz before the division.
    function automatic integer ns_cycles(input integer ns);
        reg [63:0] numerator;
        begin
            numerator = 64'(CLK_HZ) * 64'(ns) + 64'd999999999;
            ns_cycles = integer'(numerator / 64'd1000000000);
        end
    endfunction
    function automatic integer max2(input integer a, input integer b);
        max2 = (a > b) ? a : b;
    endfunction

    localparam integer T_RCD = ns_cycles(18);
    localparam integer T_RP = ns_cycles(18);
    localparam integer T_RAS = ns_cycles(48);
    localparam integer T_RC = ns_cycles(60);
    localparam integer T_RRD = ns_cycles(12);
    localparam integer T_WR = max2(2, ns_cycles(15));
    // All AR recoveries are deliberately 160 ns, also satisfying the vendor's
    // tRFC*2 minimum spacing for a burst. No runtime catch-up train is used.
    localparam integer T_AR = ns_cycles(160);
    localparam integer T_MRD = 2;
    localparam integer READ_CAPTURE = 4; // READ launch to input capture
    localparam integer PRE_CYCLE = max2(T_RAS,
                                      T_RCD + max2(READ_CAPTURE, T_WR));
    localparam integer ACCESS_CYCLES = max2(PRE_CYCLE + T_RP,
                                           max2(T_RC, T_RRD));
    localparam integer INIT_CYCLES = (CLK_HZ + 4999) / 5000; // >= 200 us
    // Use the slower supported clock with the same default engine parameters
    // in either statically selected PLL profile. A fixed NTSC interval of 838
    // would violate the PAL deadline. 831 cycles is safe in both profiles.
    localparam integer REF_INTERVAL = 106406850 / 128000; // <= 7.8125 us
    // Reserve the complete admitted operation, plus two scheduling clocks.
    // Refresh does not wait for rsp_ready: only physical banks must be idle.
    localparam integer REF_GUARD = REF_INTERVAL - ACCESS_CYCLES - 2;
    localparam integer INIT_PRE = INIT_CYCLES;
    localparam integer INIT_AR0 = INIT_PRE + T_RP;
    localparam integer INIT_AR1 = INIT_AR0 + T_AR;
    localparam integer INIT_MR = INIT_AR1 + T_AR;
    localparam integer INIT_EMR = INIT_MR + T_MRD;
    localparam integer INIT_READY = INIT_EMR + T_MRD;
    localparam integer INIT_W = $clog2(INIT_READY + 1);
    localparam integer REF_W = $clog2(REF_INTERVAL + 1);
    localparam integer STEP_W = $clog2(max2(ACCESS_CYCLES, T_AR) + 1);

    localparam [1:0] S_INIT = 2'd0, S_IDLE = 2'd1,
                     S_ACCESS = 2'd2, S_REFRESH = 2'd3;
    reg [1:0] state;
    reg [INIT_W-1:0] init_count;
    reg [REF_W-1:0] refresh_age;
    reg [STEP_W-1:0] step_count;
    reg refresh_started;
    reg pending_write;
    reg [1:0] pending_bank;
    reg [9:0] pending_col;
    reg [15:0] pending_wdata;
    reg [1:0] pending_wstrb;
    reg [15:0] read_data;
    // Unconditional, unreset input FFs give the board wrapper a clean I/O
    // register endpoint. Invalid samples are harmless: only the CL3-window
    // sample is copied into read_data on the following edge.
    reg [15:0] dq_sample;
    always @(posedge clk_mem) dq_sample <= dq_in;

    // Loss asynchronously inhibits the interface; release is synchronized and
    // restarts the whole stable-clock wait. The board must establish valid
    // SDRAM power before reset_n/pll_locked are released. PLL_LOCKED alone is
    // not an analog power-good signal. Clock loss invalidates all memory data.
    wire async_ok = reset_n && pll_locked;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *)
    reg [1:0] release_sync;
    always @(posedge clk_mem or negedge async_ok) begin
        if (!async_ok) release_sync <= 2'b00;
        else release_sync <= {release_sync[0], 1'b1};
    end
    wire run = release_sync[1];

    // A request exists only on this handshake, not merely while valid is high.
    // The response slot can be reused on the same edge that it is consumed.
    assign req_ready = async_ok && run && init_done && state == S_IDLE &&
                       (!rsp_valid || rsp_ready) && refresh_age < REF_W'(REF_GUARD);

    // Use the synchronized reset release for every controller register, not
    // just an enable on registers whose asynchronous reset releases raw.
    always @(posedge clk_mem or negedge run) begin
        if (!run) begin
            state <= S_INIT;
            init_count <= 0;
            refresh_age <= 0;
            refresh_started <= 1'b0;
            step_count <= 0;
            pending_write <= 0;
            pending_bank <= 0;
            pending_col <= 0;
            pending_wdata <= 0;
            pending_wstrb <= 0;
            read_data <= 0;
            init_done <= 0;
            rsp_valid <= 0;
            rsp_rdata <= 0;
            rsp_error <= 0;
            dram_cke <= 0;
            {dram_cs_n, dram_ras_n, dram_cas_n, dram_we_n} <= 4'b1111;
            dram_addr <= 0;
            dram_ba <= 0;
            dram_dqm <= 2'b11;
            dq_out <= 0;
            dq_oe <= 0;
        end else begin
            dram_cke <= 1;
            {dram_cs_n, dram_ras_n, dram_cas_n, dram_we_n} <= 4'b0111; // NOP
            dram_addr <= 0;
            dram_ba <= 0;
            dram_dqm <= init_done ? 2'b00 : 2'b11;
            dq_out <= 0;
            dq_oe <= 0;
            if (rsp_valid && rsp_ready) rsp_valid <= 0;
            if (refresh_started && refresh_age < REF_W'(REF_INTERVAL))
                refresh_age <= refresh_age + 1'b1;

            case (state)
                S_INIT: begin
                    init_count <= init_count + 1'b1;
                    if (init_count == INIT_W'(INIT_PRE)) begin
                        {dram_ras_n, dram_cas_n, dram_we_n} <= 3'b010;
                        dram_addr[10] <= 1; // PRECHARGE ALL
                    end else if (init_count == INIT_W'(INIT_AR0) || init_count == INIT_W'(INIT_AR1)) begin
                        {dram_ras_n, dram_cas_n, dram_we_n} <= 3'b001;
                        refresh_age <= 0;
                        refresh_started <= 1;
                    end else if (init_count == INIT_W'(INIT_MR)) begin
                        {dram_ras_n, dram_cas_n, dram_we_n} <= 3'b000;
                        dram_addr <= 13'h230; // BL1, sequential, CL3, single write
                        dram_ba <= 2'b00;
                    end else if (init_count == INIT_W'(INIT_EMR)) begin
                        {dram_ras_n, dram_cas_n, dram_we_n} <= 3'b000;
                        dram_addr <= 13'h000; // full array PASR, 100% drive
                        dram_ba <= 2'b10;
                    end else if (init_count == INIT_W'(INIT_READY)) begin
                        init_done <= 1;
                        dram_dqm <= 0;
                        state <= S_IDLE;
                    end
                end
                S_IDLE: begin
                    if (refresh_age >= REF_W'(REF_GUARD)) begin
                        {dram_ras_n, dram_cas_n, dram_we_n} <= 3'b001;
                        refresh_age <= 0;
                        step_count <= 1;
                        state <= S_REFRESH;
                    end else if (req_valid && req_ready) begin
                        if (req_addr[31:26] != 0 || req_addr[0]) begin
                            // Invalid requests complete exactly once without
                            // any command or side effect on the SDRAM device.
                            rsp_valid <= 1;
                            rsp_error <= 1;
                            rsp_rdata <= 0;
                        end else begin
                            pending_write <= req_write;
                            pending_bank <= req_addr[25:24];
                            pending_col <= req_addr[10:1];
                            pending_wdata <= req_wdata;
                            pending_wstrb <= req_wstrb;
                            read_data <= 0;
                            {dram_ras_n, dram_cas_n, dram_we_n} <= 3'b011; // ACT
                            dram_addr <= req_addr[23:11];
                            dram_ba <= req_addr[25:24];
                            step_count <= 1;
                            state <= S_ACCESS;
                        end
                    end
                end
                S_ACCESS: begin
                    step_count <= step_count + 1'b1;
                    if (step_count == STEP_W'(T_RCD)) begin
                        {dram_ras_n, dram_cas_n, dram_we_n} <=
                            pending_write ? 3'b100 : 3'b101;
                        dram_ba <= pending_bank;
                        dram_addr <= {3'b000, pending_col}; // explicit PRE later
                        if (pending_write) begin
                            dq_out <= pending_wdata;
                            dq_oe <= 1;
                            dram_dqm <= ~pending_wstrb;
                        end
                    end
                    if (!pending_write && step_count == STEP_W'(T_RCD + READ_CAPTURE + 1))
                        read_data <= dq_sample;
                    if (step_count == STEP_W'(PRE_CYCLE)) begin
                        {dram_ras_n, dram_cas_n, dram_we_n} <= 3'b010;
                        dram_ba <= pending_bank;
                        dram_addr <= 0; // PRECHARGE only the used bank
                    end
                    if (step_count == STEP_W'(ACCESS_CYCLES)) begin
                        // Data is captured earlier. Completion also guarantees
                        // write recovery. The bank meets tRP before the next
                        // possible external command edge, half a cycle later.
                        rsp_rdata <= pending_write ? 16'b0 : read_data;
                        rsp_error <= 0;
                        rsp_valid <= 1;
                        state <= S_IDLE;
                    end
                end
                S_REFRESH: begin
                    step_count <= step_count + 1'b1;
                    if (step_count == STEP_W'(T_AR)) state <= S_IDLE;
                end
                default: begin
                    // Illegal internal state does not launch ACT/WRITE.
                    init_done <= 0;
                    rsp_valid <= 0;
                    refresh_started <= 0;
                    refresh_age <= 0;
                    init_count <= 0;
                    state <= S_INIT;
                    dram_dqm <= 2'b11;
                end
            endcase
        end
    end

    // This first implementation is qualified only for the two dedicated 5x
    // Pocket frequencies. Reject accidental reuse with different capture/PLL
    // assumptions instead of silently changing a device timing contract.
    // synthesis translate_off
    initial begin
        if (CLK_HZ != 107386350 && CLK_HZ != 106406850)
            $fatal(1, "sdram_single_request: unsupported dedicated clock");
        if (REF_GUARD <= T_AR || INIT_READY >= (1 << INIT_W) ||
            ACCESS_CYCLES <= T_RCD + READ_CAPTURE + 1)
            $fatal(1, "sdram_single_request: invalid timing constants");
    end
    // synthesis translate_on
endmodule
