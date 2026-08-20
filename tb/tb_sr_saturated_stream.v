`timescale 1ns/1ps

module tb_sr_saturated_stream;
    localparam PATH_NUM = 4;
    localparam COLUMN_NUM = 4;
    localparam SUPERLANE_NUM = 2;
    localparam STREAM_NUM = 4;
    localparam LANE_NUM = 4;
    localparam DATA_BITS = 8;
    localparam LOCAL_PRODUCERS = 2;
    localparam LOCAL_CONSUMERS = 2;
    localparam CELL_NUM = STREAM_NUM * LANE_NUM;
    localparam BOUNDARY_CELLS = SUPERLANE_NUM * CELL_NUM;
    localparam DIRECTION_INJECT_WIDTH = COLUMN_NUM*SUPERLANE_NUM*
        LOCAL_PRODUCERS*CELL_NUM;
    localparam DIRECTION_CONSUME_WIDTH = COLUMN_NUM*SUPERLANE_NUM*
        LOCAL_CONSUMERS*CELL_NUM;
    localparam DIRECTION_STATE_CELLS = COLUMN_NUM*BOUNDARY_CELLS;
    localparam STREAM_CYCLES = 8;

    reg clk;
    reg rst;
    reg [PATH_NUM*BOUNDARY_CELLS*DATA_BITS-1:0] boundary_input_data;
    reg [PATH_NUM*BOUNDARY_CELLS-1:0] boundary_input_valid;
    wire [PATH_NUM*BOUNDARY_CELLS*DATA_BITS-1:0] boundary_output_data;
    wire [PATH_NUM*BOUNDARY_CELLS-1:0] boundary_output_valid;
    integer errors;
    integer input_cycle;
    integer drain_cycle;

    sr_fabric #(
        .P_HEMISPHERES(2), .SR_COLUMNS_PER_HEMI(COLUMN_NUM),
        .P_SUPERLANES_PER_COLUMN(SUPERLANE_NUM), .P_STREAMS_PER_DIR(STREAM_NUM),
        .P_LANES_PER_SUPERLANE(LANE_NUM), .P_SR_DATA_BITS(DATA_BITS),
        .P_LOCAL_PRODUCERS(LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS(LOCAL_CONSUMERS)
    ) dut (
        .clk_i(clk), .rst_ni(~rst),
        .boundary_input_data(boundary_input_data),
        .boundary_input_valid(boundary_input_valid),
        .boundary_output_data(boundary_output_data),
        .boundary_output_valid(boundary_output_valid),
        .inject_valid_i({PATH_NUM*DIRECTION_INJECT_WIDTH{1'b0}}),
        .inject_data_i({PATH_NUM*DIRECTION_INJECT_WIDTH*DATA_BITS{1'b0}}),
        .consume_i({PATH_NUM*DIRECTION_CONSUME_WIDTH{1'b0}}),
        .collision_o(), .invalid_consume_o(),
        .state_data_out(), .state_valid_out(),
        .fabric_collision(), .fabric_invalid_consume()
    );

    always #5 clk = ~clk;

    function integer boundary_index;
        input integer path;
        input integer superlane;
        input integer stream;
        input integer lane;
        begin
            boundary_index = path*BOUNDARY_CELLS +
                (superlane*STREAM_NUM + stream)*LANE_NUM + lane;
        end
    endfunction

    task clear_boundary;
        begin
            boundary_input_data = {PATH_NUM*BOUNDARY_CELLS*DATA_BITS{1'b0}};
            boundary_input_valid = {PATH_NUM*BOUNDARY_CELLS{1'b0}};
        end
    endtask

    task drive_two_streams;
        input [7:0] seq_value;
        integer first;
        integer second;
        begin
            clear_boundary;
            first = boundary_index(0, 0, 0, 0);
            second = boundary_index(0, 0, 1, 2);
            boundary_input_data[first*DATA_BITS +: DATA_BITS] = seq_value;
            boundary_input_valid[first] = 1'b1;
            boundary_input_data[second*DATA_BITS +: DATA_BITS] = 8'h80 + seq_value;
            boundary_input_valid[second] = 1'b1;
        end
    endtask

    task expect_two_streams;
        input expected_valid;
        input [7:0] seq_value;
        integer first;
        integer second;
        reg [BOUNDARY_CELLS-1:0] expected_mask;
        begin
            first = boundary_index(0, 0, 0, 0);
            second = boundary_index(0, 0, 1, 2);
            expected_mask = {BOUNDARY_CELLS{1'b0}};
            if (expected_valid) begin
                expected_mask[first] = 1'b1;
                expected_mask[second] = 1'b1;
            end
            if (boundary_output_valid[0 +: BOUNDARY_CELLS] !== expected_mask ||
                (|boundary_output_valid[PATH_NUM*BOUNDARY_CELLS-1:BOUNDARY_CELLS])) begin
                $display("CHECK_FAIL saturated_valid sequence=%0d", seq_value);
                errors = errors + 1;
            end
            if (expected_valid &&
                (boundary_output_data[first*DATA_BITS +: DATA_BITS] !== seq_value ||
                 boundary_output_data[second*DATA_BITS +: DATA_BITS] !==
                    (8'h80 + seq_value))) begin
                $display("CHECK_FAIL saturated_data sequence=%0d first=%h second=%h",
                         seq_value,
                         boundary_output_data[first*DATA_BITS +: DATA_BITS],
                         boundary_output_data[second*DATA_BITS +: DATA_BITS]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        errors = 0;
        clear_boundary;
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        $display("RUN_TEST saturated_continuous_stream");
        for (input_cycle = 0; input_cycle < STREAM_CYCLES;
             input_cycle = input_cycle + 1) begin
            if (input_cycle > 0) @(negedge clk);
            drive_two_streams(input_cycle[7:0]);
            @(posedge clk); #1;
            if (input_cycle < COLUMN_NUM-1)
                expect_two_streams(1'b0, 8'h00);
            else
                expect_two_streams(1'b1,
                    input_cycle[7:0] - (COLUMN_NUM-1));
        end

        for (drain_cycle = 0; drain_cycle < COLUMN_NUM-1;
             drain_cycle = drain_cycle + 1) begin
            @(negedge clk); clear_boundary;
            @(posedge clk); #1;
            expect_two_streams(1'b1,
                STREAM_CYCLES - COLUMN_NUM + 1 + drain_cycle);
        end

        @(negedge clk); clear_boundary;
        @(posedge clk); #1;
        expect_two_streams(1'b0, 8'h00);

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
