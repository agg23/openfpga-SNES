module standard_sync_identification_unit(
    input wire clk_src, clk_dst, reset_n, data_in,
    output reg [4:0] consumer
);
    reg source;
    reg [1:0] forced_vector, fia_vector, forced_head;
    reg [2:0] reset_vector, reset_head;
    always @(posedge clk_src) source <= data_in;
    always @(posedge clk_dst or negedge reset_n) begin
        if (!reset_n) begin
            forced_vector <= 0; fia_vector <= 0; forced_head <= 0;
            reset_vector <= 0; reset_head <= 0;
        end else begin
            forced_vector <= {forced_vector[0],source};
            fia_vector <= {fia_vector[0],source};
            forced_head <= {forced_head[0],source};
            reset_vector <= {reset_vector[1:0],1'b1};
            reset_head <= {reset_head[1:0],1'b1};
        end
    end
    always @(posedge clk_dst) consumer <= {reset_head[2],reset_vector[2],forced_head[1],fia_vector[1],forced_vector[1]};
endmodule
