`timescale 1ns/1ps

module tb_sr_leaf_cell_semantic;
    localparam STREAM_NUM      = 4;
    localparam LANE_NUM        = 4;
    localparam DATA_BITS       = 8;
    localparam LOCAL_PRODUCERS = 2;
    localparam LOCAL_CONSUMERS = 2;
    localparam CELL_NUM        = STREAM_NUM * LANE_NUM;
    localparam COLUMN_NUM      = 4;
    localparam SUPERLANE_NUM   = 2;
    localparam FABRIC_CELLS    = SUPERLANE_NUM * CELL_NUM;

    reg clk;
    reg rst;
    integer errors;

    reg  [CELL_NUM*DATA_BITS-1:0] data_in;
    reg  [CELL_NUM-1:0]           valid_in;
    wire [CELL_NUM*DATA_BITS-1:0] data_out;
    wire [CELL_NUM-1:0]           valid_out;
    wire [CELL_NUM*DATA_BITS-1:0] state_data_out;
    wire [CELL_NUM-1:0]           state_valid_out;
    reg  [LOCAL_PRODUCERS*CELL_NUM-1:0] inject_valid_i;
    reg  [LOCAL_PRODUCERS*CELL_NUM*DATA_BITS-1:0] inject_data_i;
    reg  [LOCAL_CONSUMERS*CELL_NUM-1:0] consume_i;
    wire collision_o;
    wire invalid_consume_o;

    reg  fabric_direction;
    reg  [FABRIC_CELLS*DATA_BITS-1:0] fabric_data_in;
    reg  [FABRIC_CELLS-1:0]           fabric_valid_in;
    wire [FABRIC_CELLS*DATA_BITS-1:0] fabric_data_out;
    wire [FABRIC_CELLS-1:0]           fabric_valid_out;
    wire [FABRIC_CELLS*DATA_BITS-1:0] east_fabric_data_out;
    wire [FABRIC_CELLS-1:0]           east_fabric_valid_out;
    wire [FABRIC_CELLS*DATA_BITS-1:0] west_fabric_data_out;
    wire [FABRIC_CELLS-1:0]           west_fabric_valid_out;

    assign fabric_data_out = fabric_direction ?
        west_fabric_data_out : east_fabric_data_out;
    assign fabric_valid_out = fabric_direction ?
        west_fabric_valid_out : east_fabric_valid_out;

    sr_leaf #(
        .P_STREAMS_PER_DIR(STREAM_NUM),
        .P_LANES_PER_SUPERLANE(LANE_NUM),
        .P_SR_DATA_BITS(DATA_BITS),
        .P_LOCAL_PRODUCERS(LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS(LOCAL_CONSUMERS)
    ) u_leaf (
        .clk_i(clk),
        .rst_ni(~rst),
        .upstream_data_i(data_in),
        .upstream_valid_i(valid_in),
        .downstream_data_o(data_out),
        .downstream_valid_o(valid_out),
        .state_data_o(state_data_out),
        .state_valid_o(state_valid_out),
        .inject_valid_i(inject_valid_i),
        .inject_data_i(inject_data_i),
        .consume_i(consume_i),
        .collision_o(collision_o),
        .invalid_consume_o(invalid_consume_o)
    );

    sr_direction_fabric #(
        .SR_COLUMNS_PER_HEMI(COLUMN_NUM),
        .P_SUPERLANES_PER_COLUMN(SUPERLANE_NUM),
        .P_STREAMS_PER_DIR(STREAM_NUM),
        .P_LANES_PER_SUPERLANE(LANE_NUM),
        .P_SR_DATA_BITS(DATA_BITS),
        .P_LOCAL_PRODUCERS(LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS(LOCAL_CONSUMERS),
        .DIRECTION(0)
    ) u_east_fabric (
        .clk_i(clk),
        .rst_ni(~rst),
        .stream_data_in(fabric_data_in),
        .stream_valid_in(fabric_valid_in),
        .stream_data_out(east_fabric_data_out),
        .stream_valid_out(east_fabric_valid_out),
        .inject_valid_i({COLUMN_NUM*SUPERLANE_NUM*LOCAL_PRODUCERS*CELL_NUM{1'b0}}),
        .inject_data_i({COLUMN_NUM*SUPERLANE_NUM*LOCAL_PRODUCERS*CELL_NUM*DATA_BITS{1'b0}}),
        .consume_i({COLUMN_NUM*SUPERLANE_NUM*LOCAL_CONSUMERS*CELL_NUM{1'b0}}),
        .collision_o(),
        .invalid_consume_o(),
        .state_data_out(),
        .state_valid_out()
    );

    sr_direction_fabric #(
        .SR_COLUMNS_PER_HEMI(COLUMN_NUM),
        .P_SUPERLANES_PER_COLUMN(SUPERLANE_NUM),
        .P_STREAMS_PER_DIR(STREAM_NUM),
        .P_LANES_PER_SUPERLANE(LANE_NUM),
        .P_SR_DATA_BITS(DATA_BITS),
        .P_LOCAL_PRODUCERS(LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS(LOCAL_CONSUMERS),
        .DIRECTION(1)
    ) u_west_fabric (
        .clk_i(clk),
        .rst_ni(~rst),
        .stream_data_in(fabric_data_in),
        .stream_valid_in(fabric_valid_in),
        .stream_data_out(west_fabric_data_out),
        .stream_valid_out(west_fabric_valid_out),
        .inject_valid_i({COLUMN_NUM*SUPERLANE_NUM*LOCAL_PRODUCERS*CELL_NUM{1'b0}}),
        .inject_data_i({COLUMN_NUM*SUPERLANE_NUM*LOCAL_PRODUCERS*CELL_NUM*DATA_BITS{1'b0}}),
        .consume_i({COLUMN_NUM*SUPERLANE_NUM*LOCAL_CONSUMERS*CELL_NUM{1'b0}}),
        .collision_o(), .invalid_consume_o(),
        .state_data_out(), .state_valid_out()
    );

    always #5 clk = ~clk;

    function integer cell_index;
        input integer stream;
        input integer lane;
        begin
            cell_index = stream * LANE_NUM + lane;
        end
    endfunction

    function integer fabric_cell_index;
        input integer superlane;
        input integer stream;
        input integer lane;
        begin
            fabric_cell_index = (superlane * STREAM_NUM + stream) * LANE_NUM + lane;
        end
    endfunction

    task clear_leaf_inputs;
        begin
            data_in = {CELL_NUM*DATA_BITS{1'b0}};
            valid_in = {CELL_NUM{1'b0}};
            inject_valid_i = {LOCAL_PRODUCERS*CELL_NUM{1'b0}};
            inject_data_i = {LOCAL_PRODUCERS*CELL_NUM*DATA_BITS{1'b0}};
            consume_i = {LOCAL_CONSUMERS*CELL_NUM{1'b0}};
        end
    endtask

    task clear_fabric_input;
        begin
            fabric_data_in = {FABRIC_CELLS*DATA_BITS{1'b0}};
            fabric_valid_in = {FABRIC_CELLS{1'b0}};
        end
    endtask

    task reset_all;
        begin
            @(negedge clk);
            rst = 1'b1;
            clear_leaf_inputs;
            clear_fabric_input;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task set_upstream_cell;
        input integer stream;
        input integer lane;
        input [7:0] value;
        integer index;
        begin
            index = cell_index(stream, lane);
            data_in[index*DATA_BITS +: DATA_BITS] = value;
            valid_in[index] = 1'b1;
        end
    endtask

    task set_inject_cell;
        input integer producer;
        input integer stream;
        input integer lane;
        input [7:0] value;
        integer index;
        begin
            index = producer*CELL_NUM + cell_index(stream, lane);
            inject_valid_i[index] = 1'b1;
            inject_data_i[index*DATA_BITS +: DATA_BITS] = value;
        end
    endtask

    task set_consume_cell;
        input integer consumer;
        input integer stream;
        input integer lane;
        begin
            consume_i[consumer*CELL_NUM + cell_index(stream, lane)] = 1'b1;
        end
    endtask

    task expect_leaf_cell;
        input integer stream;
        input integer lane;
        input expected_state_valid;
        input expected_downstream_valid;
        input [7:0] expected_data;
        integer index;
        begin
            index = cell_index(stream, lane);
            if (state_valid_out[index] !== expected_state_valid ||
                valid_out[index] !== expected_downstream_valid ||
                (expected_state_valid &&
                 state_data_out[index*DATA_BITS +: DATA_BITS] !== expected_data)) begin
                $display("CHECK_FAIL leaf stream=%0d lane=%0d state_valid=%0d downstream_valid=%0d data=%h",
                         stream, lane, state_valid_out[index], valid_out[index],
                         state_data_out[index*DATA_BITS +: DATA_BITS]);
                errors = errors + 1;
            end
        end
    endtask

    task set_fabric_cell;
        input integer superlane;
        input integer stream;
        input integer lane;
        input [7:0] value;
        integer index;
        begin
            index = fabric_cell_index(superlane, stream, lane);
            fabric_data_in[index*DATA_BITS +: DATA_BITS] = value;
            fabric_valid_in[index] = 1'b1;
        end
    endtask

    task expect_fabric_cell;
        input integer superlane;
        input integer stream;
        input integer lane;
        input expected_valid;
        input [7:0] expected_data;
        integer index;
        begin
            index = fabric_cell_index(superlane, stream, lane);
            if (fabric_valid_out[index] !== expected_valid ||
                (expected_valid &&
                 fabric_data_out[index*DATA_BITS +: DATA_BITS] !== expected_data)) begin
                $display("CHECK_FAIL fabric direction=%0d valid=%0d data=%h",
                         fabric_direction, fabric_valid_out[index],
                         fabric_data_out[index*DATA_BITS +: DATA_BITS]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        errors = 0;
        fabric_direction = 1'b0;
        clear_leaf_inputs;
        clear_fabric_input;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        $display("RUN_TEST single_cell_consume");
        set_upstream_cell(1, 2, 8'h12);
        set_upstream_cell(0, 0, 8'h34);
        @(posedge clk); #1;
        @(negedge clk);
        clear_leaf_inputs;
        set_consume_cell(0, 1, 2);
        #1;
        expect_leaf_cell(1, 2, 1'b1, 1'b0, 8'h12);
        expect_leaf_cell(0, 0, 1'b1, 1'b1, 8'h34);

        reset_all;
        $display("RUN_TEST independent_consume_masks");
        set_upstream_cell(0, 1, 8'ha1);
        set_upstream_cell(2, 2, 8'hb2);
        set_upstream_cell(3, 3, 8'hc3);
        @(posedge clk); #1;
        @(negedge clk);
        clear_leaf_inputs;
        set_consume_cell(0, 0, 1);
        set_consume_cell(1, 2, 2);
        #1;
        expect_leaf_cell(0, 1, 1'b1, 1'b0, 8'ha1);
        expect_leaf_cell(2, 2, 1'b1, 1'b0, 8'hb2);
        expect_leaf_cell(3, 3, 1'b1, 1'b1, 8'hc3);

        reset_all;
        $display("RUN_TEST single_cell_inject");
        set_inject_cell(0, 2, 3, 8'h55);
        if (collision_o !== 1'b0) errors = errors + 1;
        @(posedge clk); #1;
        clear_leaf_inputs;
        #1;
        expect_leaf_cell(2, 3, 1'b1, 1'b1, 8'h55);
        expect_leaf_cell(2, 2, 1'b0, 1'b0, 8'h00);

        reset_all;
        $display("RUN_TEST independent_injects");
        set_inject_cell(0, 0, 2, 8'h42);
        set_inject_cell(1, 3, 1, 8'h91);
        #1;
        if (collision_o !== 1'b0) begin
            $display("CHECK_FAIL false_collision_independent_injects");
            errors = errors + 1;
        end
        @(posedge clk); #1;
        clear_leaf_inputs;
        expect_leaf_cell(0, 2, 1'b1, 1'b1, 8'h42);
        expect_leaf_cell(3, 1, 1'b1, 1'b1, 8'h91);

        reset_all;
        $display("RUN_TEST same_cell_collision");
        set_inject_cell(0, 1, 1, 8'h60);
        set_inject_cell(1, 1, 1, 8'h71);
        #1;
        if (collision_o !== 1'b1) begin
            $display("CHECK_FAIL collision_not_asserted");
            errors = errors + 1;
        end
        @(posedge clk); #1;
        clear_leaf_inputs;
        expect_leaf_cell(1, 1, 1'b1, 1'b1, 8'h60);

        reset_all;
        $display("RUN_TEST no_false_collision");
        set_inject_cell(0, 1, 0, 8'h10);
        set_inject_cell(1, 1, 1, 8'h11);
        #1;
        if (collision_o !== 1'b0) begin
            $display("CHECK_FAIL false_collision_different_cells");
            errors = errors + 1;
        end

        reset_all;
        $display("RUN_TEST invalid_consume");
        set_consume_cell(0, 3, 0);
        #1;
        if (invalid_consume_o !== 1'b1) begin
            $display("CHECK_FAIL invalid_consume_not_asserted");
            errors = errors + 1;
        end

        reset_all;
        $display("RUN_TEST valid_consume");
        set_upstream_cell(3, 0, 8'h88);
        @(posedge clk); #1;
        @(negedge clk);
        clear_leaf_inputs;
        set_consume_cell(1, 3, 0);
        #1;
        if (invalid_consume_o !== 1'b0) begin
            $display("CHECK_FAIL valid_consume_flagged_invalid");
            errors = errors + 1;
        end

        reset_all;
        $display("RUN_TEST propagation_east");
        fabric_direction = 1'b0;
        set_fabric_cell(0, 0, 0, 8'he1);
        @(negedge clk);
        clear_fabric_input;
        repeat (COLUMN_NUM-1) @(posedge clk);
        #1;
        expect_fabric_cell(0, 0, 0, 1'b1, 8'he1);

        reset_all;
        $display("RUN_TEST propagation_west");
        fabric_direction = 1'b1;
        set_fabric_cell(1, 2, 3, 8'hf2);
        @(negedge clk);
        clear_fabric_input;
        repeat (COLUMN_NUM-1) @(posedge clk);
        #1;
        expect_fabric_cell(1, 2, 3, 1'b1, 8'hf2);

        reset_all;
        $display("RUN_TEST propagation_bubble");
        fabric_direction = 1'b0;
        set_fabric_cell(0, 1, 1, 8'ha1);
        @(negedge clk);
        clear_fabric_input;
        @(negedge clk);
        set_fabric_cell(0, 1, 1, 8'ha2);
        repeat (COLUMN_NUM-2) @(posedge clk);
        #1;
        expect_fabric_cell(0, 1, 1, 1'b1, 8'ha1);
        @(posedge clk); #1;
        expect_fabric_cell(0, 1, 1, 1'b0, 8'h00);
        @(posedge clk); #1;
        expect_fabric_cell(0, 1, 1, 1'b1, 8'ha2);

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
