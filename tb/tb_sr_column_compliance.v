`timescale 1ns/1ps

// AC3 compliance: a column raises only the superlane dimension. It adds one
// leaf register hop and must not change stream/lane order or cross superlanes.
module tb_sr_column_compliance;
    localparam SUPERLANE_NUM   = 4;
    localparam STREAM_NUM      = 32;
    localparam LANE_NUM        = 8;
    localparam DATA_BITS       = 8;
    localparam LOCAL_PRODUCERS = 2;
    localparam LOCAL_CONSUMERS = 2;
    localparam CELL_NUM        = STREAM_NUM * LANE_NUM;
    localparam DATA_WIDTH      = SUPERLANE_NUM * CELL_NUM * DATA_BITS;
    localparam VALID_WIDTH     = SUPERLANE_NUM * CELL_NUM;
    localparam INJECT_WIDTH    = SUPERLANE_NUM * LOCAL_PRODUCERS * CELL_NUM;
    localparam CONSUME_WIDTH   = SUPERLANE_NUM * LOCAL_CONSUMERS * CELL_NUM;

    reg clk;
    reg rst_ni;
    reg  [DATA_WIDTH-1:0]  column_data_in;
    reg  [VALID_WIDTH-1:0] column_valid_in;
    wire [DATA_WIDTH-1:0]  column_data_out;
    wire [VALID_WIDTH-1:0] column_valid_out;
    wire [DATA_WIDTH-1:0]  column_state_data_out;
    wire [VALID_WIDTH-1:0] column_state_valid_out;
    reg  [INJECT_WIDTH-1:0] inject_valid_i;
    reg  [INJECT_WIDTH*DATA_BITS-1:0] inject_data_i;
    reg  [CONSUME_WIDTH-1:0] consume_i;
    wire [SUPERLANE_NUM-1:0] collision_o;
    wire [SUPERLANE_NUM-1:0] invalid_consume_o;
    integer errors;
    integer superlane;
    integer stream;
    integer lane;
    integer cell_index;
    integer inject_cell;
    integer consume_cell;
    integer state_cell;

    function [7:0] cell_pattern;
        input integer sl;
        input integer st;
        input integer ln;
        input integer phase;
        begin
            cell_pattern = (phase*8'd71) ^ (sl*8'd53) ^
                           (st*8'd11) ^ (ln*8'd3);
        end
    endfunction

    sr_column dut (
        .clk_i(clk),
        .rst_ni(rst_ni),
        .column_data_in(column_data_in),
        .column_valid_in(column_valid_in),
        .column_data_out(column_data_out),
        .column_valid_out(column_valid_out),
        .column_state_data_out(column_state_data_out),
        .column_state_valid_out(column_state_valid_out),
        .inject_valid_i(inject_valid_i),
        .inject_data_i(inject_data_i),
        .consume_i(consume_i),
        .collision_o(collision_o),
        .invalid_consume_o(invalid_consume_o)
    );

    always #5 clk = ~clk;

    task check_all_cells;
        input integer phase;
        begin
            for (superlane = 0; superlane < SUPERLANE_NUM;
                 superlane = superlane + 1) begin
                for (stream = 0; stream < STREAM_NUM; stream = stream + 1) begin
                    for (lane = 0; lane < LANE_NUM; lane = lane + 1) begin
                        cell_index = superlane*CELL_NUM + stream*LANE_NUM + lane;
                        if (!column_valid_out[cell_index] ||
                            column_data_out[cell_index*DATA_BITS +: DATA_BITS] !==
                                cell_pattern(superlane, stream, lane, phase))
                            errors = errors + 1;
                    end
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_ni = 1'b0;
        column_data_in = {DATA_WIDTH{1'b0}};
        column_valid_in = {VALID_WIDTH{1'b0}};
        inject_valid_i = {INJECT_WIDTH{1'b0}};
        inject_data_i = {INJECT_WIDTH*DATA_BITS{1'b0}};
        consume_i = {CONSUME_WIDTH{1'b0}};
        errors = 0;

        repeat (2) @(posedge clk);
        @(negedge clk); rst_ni = 1'b1;

        $display("RUN_TEST column_one_cycle_and_order");
        for (superlane = 0; superlane < SUPERLANE_NUM;
             superlane = superlane + 1) begin
            for (stream = 0; stream < STREAM_NUM; stream = stream + 1) begin
                for (lane = 0; lane < LANE_NUM; lane = lane + 1) begin
                    cell_index = superlane*CELL_NUM + stream*LANE_NUM + lane;
                    column_data_in[cell_index*DATA_BITS +: DATA_BITS] =
                        cell_pattern(superlane, stream, lane, 1);
                    column_valid_in[cell_index] = 1'b1;
                end
            end
        end
        #1;
        if (|column_valid_out) errors = errors + 1;
        @(posedge clk); #1;
        check_all_cells(1);
        if (column_state_valid_out !== column_valid_out ||
            column_state_data_out !== column_data_out)
            errors = errors + 1;

        $display("RUN_TEST column_bubble_one_cycle");
        @(negedge clk);
        column_valid_in = {VALID_WIDTH{1'b0}};
        column_data_in = {DATA_WIDTH{1'b0}};
        if (!(&column_valid_out)) errors = errors + 1;
        @(posedge clk); #1;
        if (|column_valid_out) errors = errors + 1;

        $display("RUN_TEST column_superlane_isolation");
        @(negedge clk);
        for (superlane = 0; superlane < SUPERLANE_NUM;
             superlane = superlane + 1) begin
            cell_index = superlane*CELL_NUM + (superlane+1)*LANE_NUM + superlane;
            column_valid_in[cell_index] = 1'b1;
            column_data_in[cell_index*DATA_BITS +: DATA_BITS] = 8'h80 + superlane;
        end
        @(posedge clk); #1;
        if ($countones(column_valid_out) != SUPERLANE_NUM)
            errors = errors + 1;
        for (superlane = 0; superlane < SUPERLANE_NUM;
             superlane = superlane + 1) begin
            cell_index = superlane*CELL_NUM + (superlane+1)*LANE_NUM + superlane;
            if (!column_valid_out[cell_index] ||
                column_data_out[cell_index*DATA_BITS +: DATA_BITS] !== 8'h80 + superlane)
                errors = errors + 1;
        end

        $display("RUN_TEST column_inject_consume_passthrough");
        @(negedge clk);
        column_data_in = {DATA_WIDTH{1'b0}};
        column_valid_in = {VALID_WIDTH{1'b0}};
        state_cell = 2*CELL_NUM + 7*LANE_NUM + 5;
        inject_cell = 2*LOCAL_PRODUCERS*CELL_NUM + 7*LANE_NUM + 5;
        inject_valid_i[inject_cell] = 1'b1;
        inject_data_i[inject_cell*DATA_BITS +: DATA_BITS] = 8'hc3;
        @(posedge clk); #1;
        if (!column_state_valid_out[state_cell] ||
            column_state_data_out[state_cell*DATA_BITS +: DATA_BITS] !== 8'hc3)
            errors = errors + 1;
        @(negedge clk);
        inject_valid_i = {INJECT_WIDTH{1'b0}};
        consume_cell = 2*LOCAL_CONSUMERS*CELL_NUM + 7*LANE_NUM + 5;
        consume_i[consume_cell] = 1'b1;
        #1;
        if (column_valid_out[state_cell] ||
            !column_state_valid_out[state_cell] || |collision_o ||
            |invalid_consume_o)
            errors = errors + 1;

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
