`timescale 1ns/1ps

// Repeatable elaboration audit for SR_DEFAULT_4T8L. No parameter override
// is applied to sr_fabric in this test.
module tb_sr_default_profile;
    localparam HEMISPHERE_NUM = 2;
    localparam DIRECTION_NUM = 2;
    localparam COLUMN_NUM = 16;
    localparam SUPERLANE_NUM = 4;
    localparam STREAM_NUM = 32;
    localparam LANE_NUM = 8;
    localparam DATA_BITS = 8;
    localparam LOCAL_PRODUCERS = 2;
    localparam LOCAL_CONSUMERS = 2;
    localparam BOUNDARY_VALID_WIDTH =
        HEMISPHERE_NUM*DIRECTION_NUM*SUPERLANE_NUM*STREAM_NUM*LANE_NUM;
    localparam BOUNDARY_DATA_WIDTH = BOUNDARY_VALID_WIDTH*DATA_BITS;
    localparam INJECT_WIDTH = HEMISPHERE_NUM*DIRECTION_NUM*COLUMN_NUM*
        SUPERLANE_NUM*LOCAL_PRODUCERS*STREAM_NUM*LANE_NUM;
    localparam CONSUME_WIDTH = HEMISPHERE_NUM*DIRECTION_NUM*COLUMN_NUM*
        SUPERLANE_NUM*LOCAL_CONSUMERS*STREAM_NUM*LANE_NUM;
    localparam STATE_VALID_WIDTH = HEMISPHERE_NUM*DIRECTION_NUM*COLUMN_NUM*
        SUPERLANE_NUM*STREAM_NUM*LANE_NUM;

    reg clk;
    reg rst;
    reg [BOUNDARY_DATA_WIDTH-1:0] boundary_input_data;
    reg [BOUNDARY_VALID_WIDTH-1:0] boundary_input_valid;
    reg [INJECT_WIDTH-1:0] inject_valid_i;
    reg [INJECT_WIDTH*DATA_BITS-1:0] inject_data_i;
    reg [CONSUME_WIDTH-1:0] consume_i;
    wire [BOUNDARY_DATA_WIDTH-1:0] boundary_output_data;
    wire [BOUNDARY_VALID_WIDTH-1:0] boundary_output_valid;
    wire [HEMISPHERE_NUM*DIRECTION_NUM*COLUMN_NUM*SUPERLANE_NUM-1:0] collision_o;
    wire [HEMISPHERE_NUM*DIRECTION_NUM*COLUMN_NUM*SUPERLANE_NUM-1:0] invalid_consume_o;
    wire [STATE_VALID_WIDTH*DATA_BITS-1:0] state_data_out;
    wire [STATE_VALID_WIDTH-1:0] state_valid_out;
    integer errors;

    sr_fabric dut (
        .clk_i(clk), .rst_ni(~rst),
        .boundary_input_data(boundary_input_data),
        .boundary_input_valid(boundary_input_valid),
        .boundary_output_data(boundary_output_data),
        .boundary_output_valid(boundary_output_valid),
        .inject_valid_i(inject_valid_i),
        .inject_data_i(inject_data_i),
        .consume_i(consume_i),
        .collision_o(collision_o),
        .invalid_consume_o(invalid_consume_o),
        .state_data_out(state_data_out),
        .state_valid_out(state_valid_out),
        .fabric_collision(),
        .fabric_invalid_consume()
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        errors = 0;
        boundary_input_data = {BOUNDARY_DATA_WIDTH{1'b0}};
        boundary_input_valid = {BOUNDARY_VALID_WIDTH{1'b0}};
        inject_valid_i = {INJECT_WIDTH{1'b0}};
        inject_data_i = {INJECT_WIDTH*DATA_BITS{1'b0}};
        consume_i = {CONSUME_WIDTH{1'b0}};

        $display("RUN_TEST default_profile_elaboration");
        if (dut.FULL_CHIP_INSTANCE_NUM != 1) errors = errors + 1;
        if (dut.HEMISPHERE_INSTANCE_NUM != 2) errors = errors + 1;
        if (dut.DIRECTION_INSTANCE_NUM != 4) errors = errors + 1;
        if (dut.COLUMN_INSTANCE_NUM != 64) errors = errors + 1;
        if (dut.LEAF_INSTANCE_NUM != 256) errors = errors + 1;

        // These references must elaborate at the product-profile edge indices.
        if ($bits(dut.u_west_hemisphere.u_east_direction_fabric.g_column[15]
                      .u_sr_column.g_superlane_leaf[3].u_sr_leaf.state_valid_o)
            != STREAM_NUM*LANE_NUM)
            errors = errors + 1;
        if ($bits(dut.u_east_hemisphere.u_west_direction_fabric.g_column[15]
                      .u_sr_column.g_superlane_leaf[3].u_sr_leaf.state_valid_o)
            != STREAM_NUM*LANE_NUM)
            errors = errors + 1;
        if ($bits(state_valid_out) != STATE_VALID_WIDTH)
            errors = errors + 1;

        repeat (2) @(posedge clk);
        #1;
        if (boundary_output_valid !== {BOUNDARY_VALID_WIDTH{1'b0}})
            errors = errors + 1;

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
