`timescale 1ns/1ps

module tb_sr_direction_fabric;

    localparam COLUMN_NUM    = 4;
    localparam SUPERLANE_NUM = 2;
    localparam STREAM_NUM    = 4;
    localparam LANE_NUM      = 4;
    localparam DATA_WIDTH    = SUPERLANE_NUM * STREAM_NUM * LANE_NUM * 8;
    localparam VALID_WIDTH   = SUPERLANE_NUM * STREAM_NUM * LANE_NUM;

    reg                    clk;
    reg                    rst;
    reg                    direction;
    reg  [DATA_WIDTH-1:0]  stream_data_in;
    reg  [VALID_WIDTH-1:0] stream_valid_in;
    wire [DATA_WIDTH-1:0]  stream_data_out;
    wire [VALID_WIDTH-1:0] stream_valid_out;
    wire [DATA_WIDTH-1:0]  east_data_out;
    wire [VALID_WIDTH-1:0] east_valid_out;
    wire [DATA_WIDTH-1:0]  west_data_out;
    wire [VALID_WIDTH-1:0] west_valid_out;
    integer errors;

    assign stream_data_out = direction ? west_data_out : east_data_out;
    assign stream_valid_out = direction ? west_valid_out : east_valid_out;

    sr_direction_fabric #(
        .SR_COLUMNS_PER_HEMI(COLUMN_NUM),
        .P_SUPERLANES_PER_COLUMN(SUPERLANE_NUM),
        .P_STREAMS_PER_DIR(STREAM_NUM),
        .P_LANES_PER_SUPERLANE(LANE_NUM),
        .DIRECTION(0)
    ) dut_east (
        .clk_i(clk),
        .rst_ni(~rst),
        .stream_data_in(stream_data_in),
        .stream_valid_in(stream_valid_in),
        .stream_data_out(east_data_out),
        .stream_valid_out(east_valid_out),
        .inject_valid_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        .inject_data_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM*8{1'b0}}),
        .consume_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        .collision_o(), .invalid_consume_o(),
        .state_data_out(), .state_valid_out()
    );

    sr_direction_fabric #(
        .SR_COLUMNS_PER_HEMI(COLUMN_NUM),
        .P_SUPERLANES_PER_COLUMN(SUPERLANE_NUM),
        .P_STREAMS_PER_DIR(STREAM_NUM),
        .P_LANES_PER_SUPERLANE(LANE_NUM),
        .DIRECTION(1)
    ) dut_west (
        .clk_i(clk),
        .rst_ni(~rst),
        .stream_data_in(stream_data_in),
        .stream_valid_in(stream_valid_in),
        .stream_data_out(west_data_out),
        .stream_valid_out(west_valid_out),
        .inject_valid_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        .inject_data_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM*8{1'b0}}),
        .consume_i({COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        .collision_o(), .invalid_consume_o(),
        .state_data_out(), .state_valid_out()
    );

    always #5 clk = ~clk;

    function integer cell_index;
        input integer superlane;
        input integer stream;
        input integer lane;
        begin
            cell_index = ((superlane * STREAM_NUM + stream) * LANE_NUM + lane);
        end
    endfunction

    task clear_input;
        begin
            stream_data_in  = {DATA_WIDTH{1'b0}};
            stream_valid_in = {VALID_WIDTH{1'b0}};
        end
    endtask

    task set_input_cell;
        input integer superlane;
        input integer stream;
        input integer lane;
        input [7:0] value;
        integer index;
        begin
            index = cell_index(superlane, stream, lane);
            stream_data_in[index*8 +: 8] = value;
            stream_valid_in[index] = 1'b1;
        end
    endtask

    task expect_output_cell;
        input integer superlane;
        input integer stream;
        input integer lane;
        input expected_valid;
        input [7:0] expected_data;
        integer index;
        begin
            index = cell_index(superlane, stream, lane);
            if (stream_valid_out[index] !== expected_valid ||
                (expected_valid && stream_data_out[index*8 +: 8] !== expected_data)) begin
                $display("CHECK_FAIL direction=%0d superlane=%0d stream=%0d lane=%0d expected_valid=%0d expected_data=%h actual_valid=%0d actual_data=%h",
                         direction, superlane, stream, lane,
                         expected_valid, expected_data,
                         stream_valid_out[index], stream_data_out[index*8 +: 8]);
                errors = errors + 1;
            end
        end
    endtask

    task reset_pipeline;
        begin
            @(negedge clk);
            rst = 1'b1;
            clear_input;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task run_single_cell_test;
        input test_direction;
        input integer superlane;
        input integer stream;
        input integer lane;
        input [7:0] value;
        begin
            direction = test_direction;
            clear_input;
            set_input_cell(superlane, stream, lane, value);

            // The first rising edge captures the cell in the entry column.
            @(negedge clk);
            clear_input;
            repeat (COLUMN_NUM-1) @(posedge clk);
            #1;
            expect_output_cell(superlane, stream, lane, 1'b1, value);
        end
    endtask

    task run_bubble_test;
        input test_direction;
        input integer superlane;
        input integer stream;
        input integer lane;
        input [7:0] first_value;
        input [7:0] second_value;
        begin
            direction = test_direction;
            clear_input;
            set_input_cell(superlane, stream, lane, first_value);

            // One invalid cycle is inserted between the two valid cells.
            @(negedge clk);
            clear_input;
            @(negedge clk);
            clear_input;
            set_input_cell(superlane, stream, lane, second_value);

            // At this point the first cell has reached the second column.
            repeat (COLUMN_NUM-2) @(posedge clk);
            #1;
            expect_output_cell(superlane, stream, lane, 1'b1, first_value);

            @(posedge clk);
            #1;
            expect_output_cell(superlane, stream, lane, 1'b0, 8'h00);

            @(posedge clk);
            #1;
            expect_output_cell(superlane, stream, lane, 1'b1, second_value);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        direction = 1'b0;
        errors = 0;
        clear_input;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        $display("RUN_TEST east");
        run_single_cell_test(1'b0, 0, 0, 0, 8'h55);

        reset_pipeline;
        $display("RUN_TEST west");
        run_single_cell_test(1'b1, 1, 2, 3, 8'haa);

        reset_pipeline;
        $display("RUN_TEST east_bubble");
        run_bubble_test(1'b0, 0, 1, 1, 8'ha1, 8'ha2);

        reset_pipeline;
        $display("RUN_TEST west_bubble");
        run_bubble_test(1'b1, 1, 3, 2, 8'hb1, 8'hb2);

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end

endmodule
