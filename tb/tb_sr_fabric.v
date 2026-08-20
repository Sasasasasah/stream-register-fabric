`timescale 1ns/1ps

module tb_sr_fabric;
    localparam HEMISPHERE_NUM = 2;
    localparam DIRECTION_NUM = 2;
    localparam PATH_NUM = HEMISPHERE_NUM * DIRECTION_NUM;
    localparam COLUMN_NUM = 4;
    localparam SUPERLANE_NUM = 2;
    localparam STREAM_NUM = 4;
    localparam LANE_NUM = 4;
    localparam DATA_BITS = 8;
    localparam LOCAL_PRODUCERS = 2;
    localparam LOCAL_CONSUMERS = 2;
    localparam CELL_NUM = STREAM_NUM * LANE_NUM;
    localparam BOUNDARY_CELLS = SUPERLANE_NUM * CELL_NUM;
    localparam DIRECTION_STATE_CELLS = COLUMN_NUM * BOUNDARY_CELLS;
    localparam DIRECTION_INJECT_WIDTH = COLUMN_NUM * SUPERLANE_NUM *
                                        LOCAL_PRODUCERS * CELL_NUM;
    localparam DIRECTION_CONSUME_WIDTH = COLUMN_NUM * SUPERLANE_NUM *
                                         LOCAL_CONSUMERS * CELL_NUM;
    localparam DIRECTION_ERROR_WIDTH = COLUMN_NUM * SUPERLANE_NUM;

    reg clk;
    reg rst;
    integer errors;
    integer path_loop;
    integer latency_index;

    reg  [PATH_NUM*BOUNDARY_CELLS*DATA_BITS-1:0] boundary_input_data;
    reg  [PATH_NUM*BOUNDARY_CELLS-1:0]           boundary_input_valid;
    wire [PATH_NUM*BOUNDARY_CELLS*DATA_BITS-1:0] boundary_output_data;
    wire [PATH_NUM*BOUNDARY_CELLS-1:0]           boundary_output_valid;
    reg  [PATH_NUM*DIRECTION_INJECT_WIDTH-1:0] inject_valid_i;
    reg  [PATH_NUM*DIRECTION_INJECT_WIDTH*DATA_BITS-1:0] inject_data_i;
    reg  [PATH_NUM*DIRECTION_CONSUME_WIDTH-1:0] consume_i;
    wire [PATH_NUM*DIRECTION_ERROR_WIDTH-1:0] collision_o;
    wire [PATH_NUM*DIRECTION_ERROR_WIDTH-1:0] invalid_consume_o;
    wire [PATH_NUM*DIRECTION_STATE_CELLS*DATA_BITS-1:0] state_data_out;
    wire [PATH_NUM*DIRECTION_STATE_CELLS-1:0] state_valid_out;

    sr_fabric #(
        .P_HEMISPHERES(HEMISPHERE_NUM),
        .SR_COLUMNS_PER_HEMI(COLUMN_NUM),
        .P_SUPERLANES_PER_COLUMN(SUPERLANE_NUM),
        .P_STREAMS_PER_DIR(STREAM_NUM),
        .P_LANES_PER_SUPERLANE(LANE_NUM),
        .P_SR_DATA_BITS(DATA_BITS),
        .P_LOCAL_PRODUCERS(LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS(LOCAL_CONSUMERS)
    ) dut (
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

    function integer state_index;
        input integer path;
        input integer column;
        input integer superlane;
        input integer stream;
        input integer lane;
        begin
            state_index = path*DIRECTION_STATE_CELLS +
                (column*SUPERLANE_NUM + superlane)*CELL_NUM +
                stream*LANE_NUM + lane;
        end
    endfunction

    function integer inject_index;
        input integer path;
        input integer column;
        input integer superlane;
        input integer producer;
        input integer stream;
        input integer lane;
        begin
            inject_index = path*DIRECTION_INJECT_WIDTH +
                ((column*SUPERLANE_NUM + superlane)*LOCAL_PRODUCERS +
                 producer)*CELL_NUM + stream*LANE_NUM + lane;
        end
    endfunction

    function integer consume_index;
        input integer path;
        input integer column;
        input integer superlane;
        input integer consumer;
        input integer stream;
        input integer lane;
        begin
            consume_index = path*DIRECTION_CONSUME_WIDTH +
                ((column*SUPERLANE_NUM + superlane)*LOCAL_CONSUMERS +
                 consumer)*CELL_NUM + stream*LANE_NUM + lane;
        end
    endfunction

    task clear_inputs;
        begin
            boundary_input_data = {PATH_NUM*BOUNDARY_CELLS*DATA_BITS{1'b0}};
            boundary_input_valid = {PATH_NUM*BOUNDARY_CELLS{1'b0}};
            inject_valid_i = {PATH_NUM*DIRECTION_INJECT_WIDTH{1'b0}};
            inject_data_i = {PATH_NUM*DIRECTION_INJECT_WIDTH*DATA_BITS{1'b0}};
            consume_i = {PATH_NUM*DIRECTION_CONSUME_WIDTH{1'b0}};
        end
    endtask

    task reset_fabric;
        begin
            @(negedge clk);
            rst = 1'b1;
            clear_inputs;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task set_boundary_cell;
        input integer path;
        input integer superlane;
        input integer stream;
        input integer lane;
        input [7:0] data;
        integer index;
        begin
            index = boundary_index(path, superlane, stream, lane);
            boundary_input_data[index*DATA_BITS +: DATA_BITS] = data;
            boundary_input_valid[index] = 1'b1;
        end
    endtask

    task set_inject_cell;
        input integer path;
        input integer column;
        input integer superlane;
        input integer producer;
        input integer stream;
        input integer lane;
        input [7:0] data;
        integer index;
        begin
            index = inject_index(path, column, superlane, producer, stream, lane);
            inject_valid_i[index] = 1'b1;
            inject_data_i[index*DATA_BITS +: DATA_BITS] = data;
        end
    endtask

    task expect_output;
        input integer path;
        input integer superlane;
        input integer stream;
        input integer lane;
        input expected_valid;
        input [7:0] expected_data;
        integer index;
        begin
            index = boundary_index(path, superlane, stream, lane);
            if (boundary_output_valid[index] !== expected_valid ||
                (expected_valid &&
                 boundary_output_data[index*DATA_BITS +: DATA_BITS] !==
                    expected_data)) begin
                $display("CHECK_FAIL output path=%0d valid=%0d data=%h",
                         path, boundary_output_valid[index],
                         boundary_output_data[index*DATA_BITS +: DATA_BITS]);
                errors = errors + 1;
            end
        end
    endtask

    task expect_state;
        input integer path;
        input integer column;
        input integer superlane;
        input integer stream;
        input integer lane;
        input expected_valid;
        input [7:0] expected_data;
        integer index;
        begin
            index = state_index(path, column, superlane, stream, lane);
            if (state_valid_out[index] !== expected_valid ||
                (expected_valid &&
                 state_data_out[index*DATA_BITS +: DATA_BITS] !== expected_data)) begin
                $display("CHECK_FAIL state path=%0d column=%0d valid=%0d data=%h",
                         path, column, state_valid_out[index],
                         state_data_out[index*DATA_BITS +: DATA_BITS]);
                errors = errors + 1;
            end
        end
    endtask

    task run_single_path;
        input integer active_path;
        input [7:0] data;
        begin
            set_boundary_cell(active_path, 0, 1, 2, data);
            @(negedge clk);
            boundary_input_data = {PATH_NUM*BOUNDARY_CELLS*DATA_BITS{1'b0}};
            boundary_input_valid = {PATH_NUM*BOUNDARY_CELLS{1'b0}};
            repeat (COLUMN_NUM-1) @(posedge clk); #1;
            for (path_loop = 0; path_loop < PATH_NUM; path_loop = path_loop + 1)
                expect_output(path_loop, 0, 1, 2,
                              path_loop == active_path, data);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        errors = 0;
        clear_inputs;
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        $display("RUN_TEST west_hemisphere_east_direction");
        run_single_path(0, 8'ha0);
        reset_fabric;
        $display("RUN_TEST west_hemisphere_west_direction");
        run_single_path(1, 8'hb1);
        reset_fabric;
        $display("RUN_TEST east_hemisphere_east_direction");
        run_single_path(2, 8'hc2);
        reset_fabric;
        $display("RUN_TEST east_hemisphere_west_direction");
        run_single_path(3, 8'hd3);

        reset_fabric;
        $display("RUN_TEST four_path_simultaneous");
        set_boundary_cell(0, 0, 0, 0, 8'ha1);
        set_boundary_cell(1, 0, 1, 1, 8'hb2);
        set_boundary_cell(2, 1, 2, 2, 8'hc3);
        set_boundary_cell(3, 1, 3, 3, 8'hd4);
        @(negedge clk); clear_inputs;
        repeat (COLUMN_NUM-1) @(posedge clk); #1;
        expect_output(0, 0, 0, 0, 1'b1, 8'ha1);
        expect_output(1, 0, 1, 1, 1'b1, 8'hb2);
        expect_output(2, 1, 2, 2, 1'b1, 8'hc3);
        expect_output(3, 1, 3, 3, 1'b1, 8'hd4);

        reset_fabric;
        $display("RUN_TEST same_coordinate_independence");
        set_inject_cell(0, 0, 1, 0, 2, 3, 8'h11);
        set_inject_cell(1, 3, 1, 0, 2, 3, 8'h22);
        set_inject_cell(2, 0, 1, 0, 2, 3, 8'h33);
        set_inject_cell(3, 3, 1, 0, 2, 3, 8'h44);
        @(posedge clk); #1;
        expect_state(0, 0, 1, 2, 3, 1'b1, 8'h11);
        expect_state(1, 3, 1, 2, 3, 1'b1, 8'h22);
        expect_state(2, 0, 1, 2, 3, 1'b1, 8'h33);
        expect_state(3, 3, 1, 2, 3, 1'b1, 8'h44);

        reset_fabric;
        $display("RUN_TEST hemisphere_consume_independence");
        set_inject_cell(0, 0, 0, 0, 1, 1, 8'h61);
        set_inject_cell(2, 0, 0, 0, 1, 1, 8'h62);
        @(posedge clk); #1;
        @(negedge clk); clear_inputs;
        consume_i[consume_index(0, 0, 0, 0, 1, 1)] = 1'b1;
        @(posedge clk); #1;
        expect_state(0, 1, 0, 1, 1, 1'b0, 8'h00);
        expect_state(2, 1, 0, 1, 1, 1'b1, 8'h62);

        reset_fabric;
        $display("RUN_TEST hemisphere_inject_independence");
        set_inject_cell(1, 3, 0, 0, 3, 0, 8'h71);
        set_inject_cell(3, 3, 0, 1, 3, 0, 8'h72);
        @(posedge clk); #1;
        expect_state(1, 3, 0, 3, 0, 1'b1, 8'h71);
        expect_state(3, 3, 0, 3, 0, 1'b1, 8'h72);

        reset_fabric;
        $display("RUN_TEST full_chip_error_independence");
        set_inject_cell(0, 0, 0, 0, 0, 1, 8'h80);
        set_inject_cell(0, 0, 0, 1, 0, 1, 8'h81);
        #1;
        if (collision_o[0] !== 1'b1 ||
            (|collision_o[PATH_NUM*DIRECTION_ERROR_WIDTH-1:DIRECTION_ERROR_WIDTH])) begin
            $display("CHECK_FAIL collision_hemisphere_isolation");
            errors = errors + 1;
        end
        reset_fabric;
        consume_i[consume_index(3, 3, 0, 0, 0, 0)] = 1'b1;
        #1;
        if (invalid_consume_o[3*DIRECTION_ERROR_WIDTH + 3*SUPERLANE_NUM]
                !== 1'b1 ||
            (|invalid_consume_o[3*DIRECTION_ERROR_WIDTH-1:0])) begin
            $display("CHECK_FAIL invalid_consume_hemisphere_isolation");
            errors = errors + 1;
        end

        reset_fabric;
        $display("RUN_TEST full_chip_latency");
        set_boundary_cell(0, 0, 3, 1, 8'he8);
        set_boundary_cell(1, 0, 3, 1, 8'hf8);
        @(negedge clk); clear_inputs;
        for (latency_index = 1; latency_index < COLUMN_NUM;
             latency_index = latency_index + 1) begin
            #1;
            expect_output(0, 0, 3, 1, 1'b0, 8'h00);
            expect_output(1, 0, 3, 1, 1'b0, 8'h00);
            @(posedge clk);
        end
        #1;
        expect_output(0, 0, 3, 1, 1'b1, 8'he8);
        expect_output(1, 0, 3, 1, 1'b1, 8'hf8);

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
