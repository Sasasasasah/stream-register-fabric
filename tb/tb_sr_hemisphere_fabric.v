`timescale 1ns/1ps

module tb_sr_hemisphere_fabric;
    localparam COLUMN_NUM      = 4;
    localparam SUPERLANE_NUM   = 2;
    localparam STREAM_NUM      = 4;
    localparam LANE_NUM        = 4;
    localparam DATA_BITS       = 8;
    localparam LOCAL_PRODUCERS = 2;
    localparam LOCAL_CONSUMERS = 2;
    localparam CELL_NUM        = STREAM_NUM * LANE_NUM;
    localparam BOUNDARY_CELLS  = SUPERLANE_NUM * CELL_NUM;
    localparam STATE_CELLS     = COLUMN_NUM * BOUNDARY_CELLS;
    localparam INJECT_CELLS    = COLUMN_NUM * SUPERLANE_NUM *
                                 LOCAL_PRODUCERS * CELL_NUM;
    localparam CONSUME_CELLS   = COLUMN_NUM * SUPERLANE_NUM *
                                 LOCAL_CONSUMERS * CELL_NUM;

    reg clk;
    reg rst;
    integer errors;
    integer latency_index;

    reg  [BOUNDARY_CELLS*DATA_BITS-1:0] east_input_data;
    reg  [BOUNDARY_CELLS-1:0]           east_input_valid;
    wire [BOUNDARY_CELLS*DATA_BITS-1:0] east_output_data;
    wire [BOUNDARY_CELLS-1:0]           east_output_valid;
    reg  [INJECT_CELLS-1:0]             east_inject_valid;
    reg  [INJECT_CELLS*DATA_BITS-1:0]   east_inject_data;
    reg  [CONSUME_CELLS-1:0]            east_consume;
    wire [COLUMN_NUM*SUPERLANE_NUM-1:0] east_collision;
    wire [COLUMN_NUM*SUPERLANE_NUM-1:0] east_invalid_consume;
    wire [STATE_CELLS*DATA_BITS-1:0]    east_state_data;
    wire [STATE_CELLS-1:0]              east_state_valid;

    reg  [BOUNDARY_CELLS*DATA_BITS-1:0] west_input_data;
    reg  [BOUNDARY_CELLS-1:0]           west_input_valid;
    wire [BOUNDARY_CELLS*DATA_BITS-1:0] west_output_data;
    wire [BOUNDARY_CELLS-1:0]           west_output_valid;
    reg  [INJECT_CELLS-1:0]             west_inject_valid;
    reg  [INJECT_CELLS*DATA_BITS-1:0]   west_inject_data;
    reg  [CONSUME_CELLS-1:0]            west_consume;
    wire [COLUMN_NUM*SUPERLANE_NUM-1:0] west_collision;
    wire [COLUMN_NUM*SUPERLANE_NUM-1:0] west_invalid_consume;
    wire [STATE_CELLS*DATA_BITS-1:0]    west_state_data;
    wire [STATE_CELLS-1:0]              west_state_valid;

    sr_hemisphere_fabric #(
        .SR_COLUMNS_PER_HEMI(COLUMN_NUM),
        .P_SUPERLANES_PER_COLUMN(SUPERLANE_NUM),
        .P_STREAMS_PER_DIR(STREAM_NUM),
        .P_LANES_PER_SUPERLANE(LANE_NUM),
        .P_SR_DATA_BITS(DATA_BITS),
        .P_LOCAL_PRODUCERS(LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS(LOCAL_CONSUMERS)
    ) dut (
        .clk_i(clk),
        .rst_ni(~rst),
        .east_input_data(east_input_data),
        .east_input_valid(east_input_valid),
        .east_output_data(east_output_data),
        .east_output_valid(east_output_valid),
        .east_inject_valid(east_inject_valid),
        .east_inject_data(east_inject_data),
        .east_consume(east_consume),
        .east_collision(east_collision),
        .east_invalid_consume(east_invalid_consume),
        .east_state_data(east_state_data),
        .east_state_valid(east_state_valid),
        .west_input_data(west_input_data),
        .west_input_valid(west_input_valid),
        .west_output_data(west_output_data),
        .west_output_valid(west_output_valid),
        .west_inject_valid(west_inject_valid),
        .west_inject_data(west_inject_data),
        .west_consume(west_consume),
        .west_collision(west_collision),
        .west_invalid_consume(west_invalid_consume),
        .west_state_data(west_state_data),
        .west_state_valid(west_state_valid),
        .hemisphere_collision(), .hemisphere_invalid_consume()
    );

    always #5 clk = ~clk;

    function integer boundary_index;
        input integer superlane;
        input integer stream;
        input integer lane;
        begin
            boundary_index = (superlane * STREAM_NUM + stream) * LANE_NUM + lane;
        end
    endfunction

    function integer state_index;
        input integer column;
        input integer superlane;
        input integer stream;
        input integer lane;
        begin
            state_index = (column * SUPERLANE_NUM + superlane) * CELL_NUM +
                          stream * LANE_NUM + lane;
        end
    endfunction

    function integer inject_index;
        input integer column;
        input integer superlane;
        input integer producer;
        input integer stream;
        input integer lane;
        begin
            inject_index = ((column * SUPERLANE_NUM + superlane) *
                            LOCAL_PRODUCERS + producer) * CELL_NUM +
                           stream * LANE_NUM + lane;
        end
    endfunction

    function integer consume_index;
        input integer column;
        input integer superlane;
        input integer consumer;
        input integer stream;
        input integer lane;
        begin
            consume_index = ((column * SUPERLANE_NUM + superlane) *
                             LOCAL_CONSUMERS + consumer) * CELL_NUM +
                            stream * LANE_NUM + lane;
        end
    endfunction

    task clear_boundary_inputs;
        begin
            east_input_data = {BOUNDARY_CELLS*DATA_BITS{1'b0}};
            east_input_valid = {BOUNDARY_CELLS{1'b0}};
            west_input_data = {BOUNDARY_CELLS*DATA_BITS{1'b0}};
            west_input_valid = {BOUNDARY_CELLS{1'b0}};
        end
    endtask

    task clear_local_controls;
        begin
            east_inject_valid = {INJECT_CELLS{1'b0}};
            east_inject_data = {INJECT_CELLS*DATA_BITS{1'b0}};
            east_consume = {CONSUME_CELLS{1'b0}};
            west_inject_valid = {INJECT_CELLS{1'b0}};
            west_inject_data = {INJECT_CELLS*DATA_BITS{1'b0}};
            west_consume = {CONSUME_CELLS{1'b0}};
        end
    endtask

    task reset_hemisphere;
        begin
            @(negedge clk);
            rst = 1'b1;
            clear_boundary_inputs;
            clear_local_controls;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task set_east_boundary_cell;
        input integer superlane;
        input integer stream;
        input integer lane;
        input [7:0] data;
        integer index;
        begin
            index = boundary_index(superlane, stream, lane);
            east_input_data[index*DATA_BITS +: DATA_BITS] = data;
            east_input_valid[index] = 1'b1;
        end
    endtask

    task set_west_boundary_cell;
        input integer superlane;
        input integer stream;
        input integer lane;
        input [7:0] data;
        integer index;
        begin
            index = boundary_index(superlane, stream, lane);
            west_input_data[index*DATA_BITS +: DATA_BITS] = data;
            west_input_valid[index] = 1'b1;
        end
    endtask

    task set_east_inject;
        input integer column;
        input integer superlane;
        input integer producer;
        input integer stream;
        input integer lane;
        input [7:0] data;
        integer index;
        begin
            index = inject_index(column, superlane, producer, stream, lane);
            east_inject_valid[index] = 1'b1;
            east_inject_data[index*DATA_BITS +: DATA_BITS] = data;
        end
    endtask

    task set_west_inject;
        input integer column;
        input integer superlane;
        input integer producer;
        input integer stream;
        input integer lane;
        input [7:0] data;
        integer index;
        begin
            index = inject_index(column, superlane, producer, stream, lane);
            west_inject_valid[index] = 1'b1;
            west_inject_data[index*DATA_BITS +: DATA_BITS] = data;
        end
    endtask

    task expect_boundary_cell;
        input is_west;
        input integer superlane;
        input integer stream;
        input integer lane;
        input expected_valid;
        input [7:0] expected_data;
        integer index;
        reg actual_valid;
        reg [7:0] actual_data;
        begin
            index = boundary_index(superlane, stream, lane);
            actual_valid = is_west ? west_output_valid[index] :
                                     east_output_valid[index];
            actual_data = is_west ?
                west_output_data[index*DATA_BITS +: DATA_BITS] :
                east_output_data[index*DATA_BITS +: DATA_BITS];
            if (actual_valid !== expected_valid ||
                (expected_valid && actual_data !== expected_data)) begin
                $display("CHECK_FAIL boundary west=%0d valid=%0d data=%h",
                         is_west, actual_valid, actual_data);
                errors = errors + 1;
            end
        end
    endtask

    task expect_state_cell;
        input is_west;
        input integer column;
        input integer superlane;
        input integer stream;
        input integer lane;
        input expected_valid;
        input [7:0] expected_data;
        integer index;
        reg actual_valid;
        reg [7:0] actual_data;
        begin
            index = state_index(column, superlane, stream, lane);
            actual_valid = is_west ? west_state_valid[index] :
                                     east_state_valid[index];
            actual_data = is_west ?
                west_state_data[index*DATA_BITS +: DATA_BITS] :
                east_state_data[index*DATA_BITS +: DATA_BITS];
            if (actual_valid !== expected_valid ||
                (expected_valid && actual_data !== expected_data)) begin
                $display("CHECK_FAIL state west=%0d column=%0d valid=%0d data=%h",
                         is_west, column, actual_valid, actual_data);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        errors = 0;
        clear_boundary_inputs;
        clear_local_controls;
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        $display("RUN_TEST hemisphere_east_only");
        set_east_boundary_cell(0, 0, 0, 8'h55);
        @(negedge clk); clear_boundary_inputs;
        repeat (COLUMN_NUM-1) @(posedge clk); #1;
        expect_boundary_cell(1'b0, 0, 0, 0, 1'b1, 8'h55);
        if (west_output_valid !== {BOUNDARY_CELLS{1'b0}}) errors = errors + 1;

        reset_hemisphere;
        $display("RUN_TEST hemisphere_west_only");
        set_west_boundary_cell(1, 3, 3, 8'haa);
        @(negedge clk); clear_boundary_inputs;
        repeat (COLUMN_NUM-1) @(posedge clk); #1;
        expect_boundary_cell(1'b1, 1, 3, 3, 1'b1, 8'haa);
        if (east_output_valid !== {BOUNDARY_CELLS{1'b0}}) errors = errors + 1;

        reset_hemisphere;
        $display("RUN_TEST hemisphere_simultaneous");
        set_east_boundary_cell(0, 0, 1, 8'h55);
        set_west_boundary_cell(1, 2, 3, 8'haa);
        @(negedge clk); clear_boundary_inputs;
        repeat (COLUMN_NUM-1) @(posedge clk); #1;
        expect_boundary_cell(1'b0, 0, 0, 1, 1'b1, 8'h55);
        expect_boundary_cell(1'b1, 1, 2, 3, 1'b1, 8'haa);

        reset_hemisphere;
        $display("RUN_TEST same_stream_id_independence");
        set_east_boundary_cell(0, 1, 2, 8'h12);
        set_west_boundary_cell(0, 1, 2, 8'h34);
        @(negedge clk); clear_boundary_inputs;
        repeat (COLUMN_NUM-1) @(posedge clk); #1;
        expect_boundary_cell(1'b0, 0, 1, 2, 1'b1, 8'h12);
        expect_boundary_cell(1'b1, 0, 1, 2, 1'b1, 8'h34);

        reset_hemisphere;
        $display("RUN_TEST independent_consume");
        set_east_inject(0, 0, 0, 2, 1, 8'h61);
        set_west_inject(3, 0, 0, 2, 1, 8'h62);
        @(posedge clk); #1;
        @(negedge clk); clear_local_controls;
        east_consume[consume_index(0, 0, 0, 2, 1)] = 1'b1;
        @(posedge clk); #1;
        expect_state_cell(1'b0, 1, 0, 2, 1, 1'b0, 8'h00);
        expect_state_cell(1'b1, 2, 0, 2, 1, 1'b1, 8'h62);
        if (|west_invalid_consume) errors = errors + 1;

        reset_hemisphere;
        $display("RUN_TEST independent_inject");
        set_east_inject(0, 1, 0, 3, 0, 8'ha1);
        set_west_inject(3, 1, 1, 3, 0, 8'hb2);
        @(posedge clk); #1;
        expect_state_cell(1'b0, 0, 1, 3, 0, 1'b1, 8'ha1);
        expect_state_cell(1'b1, 3, 1, 3, 0, 1'b1, 8'hb2);

        reset_hemisphere;
        $display("RUN_TEST independent_collision");
        set_east_inject(0, 0, 0, 0, 3, 8'hc0);
        set_east_inject(0, 0, 1, 0, 3, 8'hc1);
        #1;
        if (east_collision[0] !== 1'b1 || (|west_collision)) begin
            $display("CHECK_FAIL east_collision_independence");
            errors = errors + 1;
        end
        reset_hemisphere;
        set_west_inject(3, 0, 0, 0, 3, 8'hd0);
        set_west_inject(3, 0, 1, 0, 3, 8'hd1);
        #1;
        if (west_collision[3*SUPERLANE_NUM] !== 1'b1 || (|east_collision)) begin
            $display("CHECK_FAIL west_collision_independence");
            errors = errors + 1;
        end

        reset_hemisphere;
        $display("RUN_TEST invalid_consume_independence");
        east_consume[consume_index(0, 0, 0, 0, 0)] = 1'b1;
        #1;
        if (east_invalid_consume[0] !== 1'b1 || (|west_invalid_consume)) begin
            $display("CHECK_FAIL east_invalid_consume_independence");
            errors = errors + 1;
        end
        reset_hemisphere;
        west_consume[consume_index(3, 0, 0, 0, 0)] = 1'b1;
        #1;
        if (west_invalid_consume[3*SUPERLANE_NUM] !== 1'b1 ||
            (|east_invalid_consume)) begin
            $display("CHECK_FAIL west_invalid_consume_independence");
            errors = errors + 1;
        end

        reset_hemisphere;
        $display("RUN_TEST hemisphere_latency");
        set_east_boundary_cell(0, 3, 1, 8'he8);
        set_west_boundary_cell(0, 3, 1, 8'hf8);
        @(negedge clk); clear_boundary_inputs;
        for (latency_index = 1; latency_index < COLUMN_NUM;
             latency_index = latency_index + 1) begin
            #1;
            expect_boundary_cell(1'b0, 0, 3, 1, 1'b0, 8'h00);
            expect_boundary_cell(1'b1, 0, 3, 1, 1'b0, 8'h00);
            @(posedge clk);
        end
        #1;
        expect_boundary_cell(1'b0, 0, 3, 1, 1'b1, 8'he8);
        expect_boundary_cell(1'b1, 0, 3, 1, 1'b1, 8'hf8);

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
