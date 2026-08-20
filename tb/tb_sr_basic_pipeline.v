`timescale 1ns/1ps

// Version 1 regression: exercise the original fixed East pipeline behavior
// through the Version 2 direction-fabric interface.
module tb_sr_basic_pipeline;

    localparam COLUMN_NUM    = 4;
    localparam SUPERLANE_NUM = 2;
    localparam STREAM_NUM    = 4;
    localparam LANE_NUM      = 4;
    localparam DATA_WIDTH    = SUPERLANE_NUM * STREAM_NUM * LANE_NUM * 8;
    localparam VALID_WIDTH   = SUPERLANE_NUM * STREAM_NUM * LANE_NUM;

    reg                    clk;
    reg                    rst;
    reg  [DATA_WIDTH-1:0]  stream_data_in;
    reg  [VALID_WIDTH-1:0] stream_valid_in;
    wire [DATA_WIDTH-1:0]  stream_data_out;
    wire [VALID_WIDTH-1:0] stream_valid_out;
    integer errors;

    sr_direction_fabric #(
        .SR_COLUMNS_PER_HEMI(COLUMN_NUM),
        .P_SUPERLANES_PER_COLUMN(SUPERLANE_NUM),
        .P_STREAMS_PER_DIR(STREAM_NUM),
        .P_LANES_PER_SUPERLANE(LANE_NUM),
        .DIRECTION(0)
    ) dut (
        .clk_i(clk),
        .rst_ni(~rst),
        .stream_data_in(stream_data_in),
        .stream_valid_in(stream_valid_in),
        .stream_data_out(stream_data_out),
        .stream_valid_out(stream_valid_out),
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
                stream_data_out[index*8 +: 8] !== expected_data) begin
                $display("CHECK_FAIL superlane=%0d stream=%0d lane=%0d expected_valid=%0d expected_data=%h actual_valid=%0d actual_data=%h",
                         superlane, stream, lane,
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

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        errors = 0;
        clear_input;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Test 1: single cell advances through all registered columns.
        $display("RUN_TEST basic_single_cell");
        set_input_cell(0, 0, 0, 8'h55);
        @(negedge clk);
        clear_input;
        repeat (COLUMN_NUM-1) @(posedge clk);
        #1;
        expect_output_cell(0, 0, 0, 1'b1, 8'h55);

        reset_pipeline;

        // Test 2: valid, invalid, valid must emerge in the same sequence.
        $display("RUN_TEST basic_bubble");
        set_input_cell(0, 0, 0, 8'ha1);
        @(negedge clk);
        clear_input;
        @(negedge clk);
        set_input_cell(0, 0, 0, 8'ha2);

        repeat (COLUMN_NUM-2) @(posedge clk);
        #1;
        expect_output_cell(0, 0, 0, 1'b1, 8'ha1);

        @(posedge clk);
        #1;
        expect_output_cell(0, 0, 0, 1'b0, 8'h00);

        @(posedge clk);
        #1;
        expect_output_cell(0, 0, 0, 1'b1, 8'ha2);

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end

endmodule
