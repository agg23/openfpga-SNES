// Native clock-relation fixture only: no PCB or fitted route model.
module standard_io_window_unit(input wire clk,input wire [15:0] dq,
    input wire [15:0] launch_data,output wire forwarded_clk,
    output reg [15:0] read_data,output reg [15:0] write_data);
    (* preserve *) reg [15:0] dq_sample;
    always @(posedge clk) begin dq_sample<=dq;read_data<=dq_sample;write_data<=launch_data;end
    altddio_out #(.width(1),.intended_device_family("Cyclone V"),
        .lpm_type("altddio_out"),.oe_reg("UNREGISTERED"),.power_up_high("OFF")) forward(
        .datain_h(1'b0),.datain_l(1'b1),.outclock(clk),.dataout(forwarded_clk),
        .aclr(1'b0),.aset(1'b0),.oe(1'b1),.outclocken(1'b1),.sclr(1'b0),.sset(1'b0));
endmodule
