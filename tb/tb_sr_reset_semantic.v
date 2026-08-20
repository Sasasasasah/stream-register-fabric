`timescale 1ns/1ps

// Reset compliance: active-low asynchronous assertion at every leaf and
// release only from a clock-aligned top-level reset source.
module tb_sr_reset_semantic;
    localparam PATH_NUM = 4;
    localparam COLUMN_NUM = 2;
    reg clk;
    reg rst_ni;
    reg [7:0] upstream_data_i;
    reg upstream_valid_i;
    wire [7:0] downstream_data_o;
    wire downstream_valid_o;
    wire state_valid_o;
    wire [7:0] state_data_o;

    reg  [PATH_NUM*8-1:0] boundary_input_data;
    reg  [PATH_NUM-1:0] boundary_input_valid;
    wire [PATH_NUM*COLUMN_NUM-1:0] fabric_state_valid;
    integer errors;

    sr_leaf #(
        .P_STREAMS_PER_DIR(1), .P_LANES_PER_SUPERLANE(1), .P_SR_DATA_BITS(8),
        .P_LOCAL_PRODUCERS(1), .P_LOCAL_CONSUMERS(1)
    ) u_leaf (
        .clk_i(clk), .rst_ni(rst_ni),
        .upstream_data_i(upstream_data_i),
        .upstream_valid_i(upstream_valid_i),
        .downstream_data_o(downstream_data_o),
        .downstream_valid_o(downstream_valid_o),
        .state_data_o(state_data_o), .state_valid_o(state_valid_o),
        .inject_valid_i(1'b0), .inject_data_i(8'h00), .consume_i(1'b0),
        .collision_o(), .invalid_consume_o()
    );

    sr_fabric #(
        .SR_COLUMNS_PER_HEMI(COLUMN_NUM), .P_SUPERLANES_PER_COLUMN(1),
        .P_STREAMS_PER_DIR(1), .P_LANES_PER_SUPERLANE(1),
        .P_LOCAL_PRODUCERS(1), .P_LOCAL_CONSUMERS(1)
    ) u_fabric (
        .clk_i(clk), .rst_ni(rst_ni),
        .boundary_input_data(boundary_input_data),
        .boundary_input_valid(boundary_input_valid),
        .boundary_output_data(), .boundary_output_valid(),
        .inject_valid_i({PATH_NUM*COLUMN_NUM{1'b0}}),
        .inject_data_i({PATH_NUM*COLUMN_NUM*8{1'b0}}),
        .consume_i({PATH_NUM*COLUMN_NUM{1'b0}}),
        .collision_o(), .invalid_consume_o(), .state_data_out(),
        .state_valid_out(fabric_state_valid),
        .fabric_collision(), .fabric_invalid_consume()
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_ni = 1'b0;
        upstream_data_i = 8'h5a;
        upstream_valid_i = 1'b1;
        boundary_input_data = {PATH_NUM{8'ha5}};
        boundary_input_valid = {PATH_NUM{1'b1}};
        errors = 0;

        $display("RUN_TEST reset_low_clears_valid");
        #2;
        if (state_valid_o || |fabric_state_valid) errors = errors + 1;

        $display("RUN_TEST reset_release_is_clock_aligned");
        // Model a top-level synchronizer output: deassert with a nonblocking
        // update on a rising edge, so leaf flops remain reset on that edge.
        @(posedge clk); rst_ni <= 1'b1;
        #1;
        if (state_valid_o || |fabric_state_valid) errors = errors + 1;
        @(posedge clk); #1;
        if (!state_valid_o || fabric_state_valid !== 8'b10011001)
            errors = errors + 1;

        $display("RUN_TEST reset_async_assert_between_edges");
        #2;
        rst_ni = 1'b0;
        #1;
        if (state_valid_o || |fabric_state_valid) errors = errors + 1;

        $display("RUN_TEST reset_payload_is_dont_care_when_invalid");
        if (downstream_valid_o || state_valid_o) errors = errors + 1;

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
