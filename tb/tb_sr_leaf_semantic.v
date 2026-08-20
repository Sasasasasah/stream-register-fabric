`timescale 1ns/1ps

// Legacy v6 regression name retained as a one-cell smoke test. The complete
// per-cell coverage is in tb_sr_leaf_cell_semantic.v.
module tb_sr_leaf_semantic;
    reg clk;
    reg rst;
    reg [7:0] data_in;
    reg valid_in;
    reg inject_valid_i;
    reg [7:0] inject_data_i;
    reg consume_i;
    wire [7:0] data_out;
    wire valid_out;
    wire [7:0] state_data_out;
    wire state_valid_out;
    wire collision_o;
    wire invalid_consume_o;
    integer errors;

    sr_leaf #(
        .P_STREAMS_PER_DIR(1),
        .P_LANES_PER_SUPERLANE(1),
        .P_SR_DATA_BITS(8),
        .P_LOCAL_PRODUCERS(1),
        .P_LOCAL_CONSUMERS(1)
    ) dut (
        .clk_i(clk), .rst_ni(~rst),
        .upstream_data_i(data_in), .upstream_valid_i(valid_in),
        .downstream_data_o(data_out), .downstream_valid_o(valid_out),
        .state_data_o(state_data_out), .state_valid_o(state_valid_out),
        .inject_valid_i(inject_valid_i), .inject_data_i(inject_data_i),
        .consume_i(consume_i), .collision_o(collision_o),
        .invalid_consume_o(invalid_consume_o)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        data_in = 8'h00;
        valid_in = 1'b0;
        inject_valid_i = 1'b0;
        inject_data_i = 8'h00;
        consume_i = 1'b0;
        errors = 0;
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        $display("RUN_TEST leaf_normal_propagation");
        data_in = 8'ha1;
        valid_in = 1'b1;
        @(posedge clk); #1;
        if (!state_valid_out || state_data_out !== 8'ha1) errors = errors + 1;

        $display("RUN_TEST leaf_cell_inject");
        @(negedge clk);
        inject_valid_i = 1'b1;
        inject_data_i = 8'h55;
        @(posedge clk); #1;
        if (!state_valid_out || state_data_out !== 8'h55 || !collision_o)
            errors = errors + 1;

        $display("RUN_TEST leaf_consume_mask");
        @(negedge clk);
        data_in = 8'h00;
        valid_in = 1'b0;
        inject_valid_i = 1'b0;
        consume_i = 1'b1;
        #1;
        if (!state_valid_out || valid_out || invalid_consume_o)
            errors = errors + 1;

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
