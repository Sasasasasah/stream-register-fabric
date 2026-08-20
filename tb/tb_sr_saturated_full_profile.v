`timescale 1ns/1ps

// AC4 default-profile saturation. A token is identified by the scoreboard
// tuple {path, cycle, superlane, stream, lane}; the 8-bit payload is a folded
// signature of that tuple because 8 bits cannot globally encode all tuples.
module tb_sr_saturated_full_profile;
    localparam HEMISPHERE_NUM   = 2;
    localparam DIRECTION_NUM    = 2;
    localparam PATH_NUM         = 4;
    localparam COLUMN_NUM       = 16;
    localparam SUPERLANE_NUM    = 4;
    localparam STREAM_NUM       = 32;
    localparam LANE_NUM         = 8;
    localparam DATA_BITS        = 8;
    localparam FLOW_CYCLES      = 64;
    localparam PATH_CELL_NUM    = SUPERLANE_NUM * STREAM_NUM * LANE_NUM;
    localparam PATH_DATA_WIDTH  = PATH_CELL_NUM * DATA_BITS;
    localparam TOTAL_CELL_WIDTH = PATH_NUM * PATH_CELL_NUM;
    localparam TOTAL_DATA_WIDTH = PATH_NUM * PATH_DATA_WIDTH;

    reg clk;
    reg rst_ni;
    reg  [TOTAL_DATA_WIDTH-1:0] boundary_input_data;
    reg  [TOTAL_CELL_WIDTH-1:0] boundary_input_valid;
    wire [TOTAL_DATA_WIDTH-1:0] boundary_output_data;
    wire [TOTAL_CELL_WIDTH-1:0] boundary_output_valid;
    integer errors;
    integer sent_count;
    integer received_count;
    integer path;
    integer cycle_index;
    integer expected_cycle;
    integer superlane;
    integer stream;
    integer lane;
    integer path_cell;
    integer global_cell;

    function [7:0] token_signature;
        input integer path_id;
        input integer source_cycle;
        input integer sl;
        input integer st;
        input integer ln;
        begin
            token_signature = (path_id*8'd59) ^ (source_cycle*8'd37) ^
                              (sl*8'd23) ^ (st*8'd11) ^ (ln*8'd3);
        end
    endfunction

    sr_fabric dut (
        .clk_i(clk), .rst_ni(rst_ni),
        .boundary_input_data(boundary_input_data),
        .boundary_input_valid(boundary_input_valid),
        .boundary_output_data(boundary_output_data),
        .boundary_output_valid(boundary_output_valid),
        .inject_valid_i({HEMISPHERE_NUM*DIRECTION_NUM*COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        .inject_data_i({HEMISPHERE_NUM*DIRECTION_NUM*COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM*DATA_BITS{1'b0}}),
        .consume_i({HEMISPHERE_NUM*DIRECTION_NUM*COLUMN_NUM*SUPERLANE_NUM*2*STREAM_NUM*LANE_NUM{1'b0}}),
        .collision_o(), .invalid_consume_o(),
        .state_data_out(), .state_valid_out(),
        .fabric_collision(), .fabric_invalid_consume()
    );

    always #5 clk = ~clk;

    task reset_fabric;
        begin
            rst_ni = 1'b0;
            boundary_input_data = {TOTAL_DATA_WIDTH{1'b0}};
            boundary_input_valid = {TOTAL_CELL_WIDTH{1'b0}};
            #1;
            @(negedge clk); rst_ni = 1'b1;
        end
    endtask

    task run_saturation;
        input integer active_mask;
        integer run_sent;
        integer run_received;
        integer run_errors;
        reg expected_valid;
        reg [7:0] expected_data;
        begin
            run_sent = 0;
            run_received = 0;
            run_errors = 0;
            reset_fabric;

            for (cycle_index = 0;
                 cycle_index < FLOW_CYCLES + COLUMN_NUM;
                 cycle_index = cycle_index + 1) begin
                @(negedge clk);
                boundary_input_data = {TOTAL_DATA_WIDTH{1'b0}};
                boundary_input_valid = {TOTAL_CELL_WIDTH{1'b0}};
                if (cycle_index < FLOW_CYCLES) begin
                    for (path = 0; path < PATH_NUM; path = path + 1) begin
                        if (active_mask[path]) begin
                            for (superlane = 0; superlane < SUPERLANE_NUM;
                                 superlane = superlane + 1) begin
                                for (stream = 0; stream < STREAM_NUM;
                                     stream = stream + 1) begin
                                    for (lane = 0; lane < LANE_NUM;
                                         lane = lane + 1) begin
                                        path_cell = superlane*STREAM_NUM*LANE_NUM +
                                                    stream*LANE_NUM + lane;
                                        global_cell = path*PATH_CELL_NUM + path_cell;
                                        boundary_input_valid[global_cell] = 1'b1;
                                        boundary_input_data[global_cell*DATA_BITS +: DATA_BITS] =
                                            token_signature(path, cycle_index,
                                                            superlane, stream, lane);
                                        run_sent = run_sent + 1;
                                    end
                                end
                            end
                        end
                    end
                end

                @(posedge clk); #1;
                expected_cycle = cycle_index - (COLUMN_NUM - 1);
                for (path = 0; path < PATH_NUM; path = path + 1) begin
                    expected_valid = active_mask[path] &&
                                     expected_cycle >= 0 &&
                                     expected_cycle < FLOW_CYCLES;
                    for (superlane = 0; superlane < SUPERLANE_NUM;
                         superlane = superlane + 1) begin
                        for (stream = 0; stream < STREAM_NUM;
                             stream = stream + 1) begin
                            for (lane = 0; lane < LANE_NUM; lane = lane + 1) begin
                                path_cell = superlane*STREAM_NUM*LANE_NUM +
                                            stream*LANE_NUM + lane;
                                global_cell = path*PATH_CELL_NUM + path_cell;
                                if (boundary_output_valid[global_cell] !== expected_valid)
                                    run_errors = run_errors + 1;
                                if (expected_valid) begin
                                    expected_data = token_signature(
                                        path, expected_cycle,
                                        superlane, stream, lane);
                                    if (boundary_output_data[global_cell*DATA_BITS +: DATA_BITS]
                                        !== expected_data)
                                        run_errors = run_errors + 1;
                                    if (boundary_output_valid[global_cell])
                                        run_received = run_received + 1;
                                end
                            end
                        end
                    end
                end
            end

            if (run_sent != run_received)
                run_errors = run_errors + 1;
            sent_count = sent_count + run_sent;
            received_count = received_count + run_received;
            errors = errors + run_errors;
            $display("SATURATION_RESULT mask=%0h sent=%0d received=%0d errors=%0d",
                     active_mask, run_sent, run_received, run_errors);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_ni = 1'b0;
        boundary_input_data = {TOTAL_DATA_WIDTH{1'b0}};
        boundary_input_valid = {TOTAL_CELL_WIDTH{1'b0}};
        errors = 0;
        sent_count = 0;
        received_count = 0;

        $display("RUN_TEST full_saturation_west_hemi_east");
        run_saturation(4'b0001);
        $display("RUN_TEST full_saturation_west_hemi_west");
        run_saturation(4'b0010);
        $display("RUN_TEST full_saturation_east_hemi_east");
        run_saturation(4'b0100);
        $display("RUN_TEST full_saturation_east_hemi_west");
        run_saturation(4'b1000);
        $display("RUN_TEST full_saturation_all_four_paths");
        run_saturation(4'b1111);

        $display("FULL_SATURATION_TOTAL sent=%0d received=%0d errors=%0d",
                 sent_count, received_count, errors);
        if (errors == 0 && sent_count == 524288 &&
            received_count == 524288)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL");
        $finish;
    end
endmodule
