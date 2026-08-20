`timescale 1ns/1ps

// AC5 hop timing and RTL trace source. Injection is visible in its source leaf
// after the first sampling edge. Each physical column-to-column hop adds
// P_SR_HOP_CYCLES (=1) cycle.
module tb_sr_hop_trace;
    localparam COLUMN_NUM      = 16;
    localparam SUPERLANE_NUM   = 4;
    localparam STREAM_NUM      = 32;
    localparam LANE_NUM        = 8;
    localparam DATA_BITS       = 8;
    localparam LOCAL_PRODUCERS = 2;
    localparam LOCAL_CONSUMERS = 2;
    localparam P_SR_HOP_CYCLES = 1;
    localparam LEAF_CELL_NUM   = STREAM_NUM * LANE_NUM;
    localparam COLUMN_CELLS    = SUPERLANE_NUM * LEAF_CELL_NUM;
    localparam COLUMN_DATA     = COLUMN_CELLS * DATA_BITS;
    localparam STATE_CELLS     = COLUMN_NUM * COLUMN_CELLS;
    localparam INJECT_WIDTH    = COLUMN_NUM * SUPERLANE_NUM *
                                 LOCAL_PRODUCERS * LEAF_CELL_NUM;
    localparam CONSUME_WIDTH   = COLUMN_NUM * SUPERLANE_NUM *
                                 LOCAL_CONSUMERS * LEAF_CELL_NUM;

    reg clk;
    reg rst_ni;
    reg direction;
    reg [INJECT_WIDTH-1:0] inject_valid_i;
    reg [INJECT_WIDTH*DATA_BITS-1:0] inject_data_i;
    wire [STATE_CELLS*DATA_BITS-1:0] state_data_out;
    wire [STATE_CELLS-1:0] state_valid_out;
    wire [STATE_CELLS*DATA_BITS-1:0] east_state_data_out;
    wire [STATE_CELLS-1:0] east_state_valid_out;
    wire [STATE_CELLS*DATA_BITS-1:0] west_state_data_out;
    wire [STATE_CELLS-1:0] west_state_valid_out;
    integer errors;
    integer trace_file;
    integer column;
    integer state_index;
    integer inject_index;

    assign state_data_out = direction ? west_state_data_out : east_state_data_out;
    assign state_valid_out = direction ? west_state_valid_out : east_state_valid_out;

    sr_direction_fabric #(
        .P_SR_HOP_CYCLES(P_SR_HOP_CYCLES), .DIRECTION(0)
    ) dut_east (
        .clk_i(clk), .rst_ni(rst_ni),
        .stream_data_in({COLUMN_DATA{1'b0}}),
        .stream_valid_in({COLUMN_CELLS{1'b0}}),
        .stream_data_out(), .stream_valid_out(),
        .inject_valid_i(inject_valid_i), .inject_data_i(inject_data_i),
        .consume_i({CONSUME_WIDTH{1'b0}}),
        .collision_o(), .invalid_consume_o(),
        .state_data_out(east_state_data_out),
        .state_valid_out(east_state_valid_out)
    );

    sr_direction_fabric #(
        .P_SR_HOP_CYCLES(P_SR_HOP_CYCLES), .DIRECTION(1)
    ) dut_west (
        .clk_i(clk), .rst_ni(rst_ni),
        .stream_data_in({COLUMN_DATA{1'b0}}),
        .stream_valid_in({COLUMN_CELLS{1'b0}}),
        .stream_data_out(), .stream_valid_out(),
        .inject_valid_i(inject_valid_i), .inject_data_i(inject_data_i),
        .consume_i({CONSUME_WIDTH{1'b0}}),
        .collision_o(), .invalid_consume_o(),
        .state_data_out(west_state_data_out),
        .state_valid_out(west_state_valid_out)
    );

    always #5 clk = ~clk;

    task clear_and_release;
        begin
            rst_ni = 1'b0;
            inject_valid_i = {INJECT_WIDTH{1'b0}};
            inject_data_i = {INJECT_WIDTH*DATA_BITS{1'b0}};
            #1;
            @(negedge clk); rst_ni = 1'b1;
        end
    endtask

    task set_inject;
        input integer source_column;
        input [7:0] value;
        begin
            // producer 0, superlane 0, stream 0, lane 0
            inject_index = source_column*SUPERLANE_NUM*LOCAL_PRODUCERS*
                           LEAF_CELL_NUM;
            inject_valid_i[inject_index] = 1'b1;
            inject_data_i[inject_index*DATA_BITS +: DATA_BITS] = value;
        end
    endtask

    task check_cell;
        input integer check_column;
        input expected_valid;
        input [7:0] expected_data;
        begin
            state_index = check_column*COLUMN_CELLS;
            if (state_valid_out[state_index] !== expected_valid)
                errors = errors + 1;
            if (expected_valid &&
                state_data_out[state_index*DATA_BITS +: DATA_BITS] !== expected_data)
                errors = errors + 1;
        end
    endtask

    task run_hop_case;
        input integer direction_value;
        input integer source_column;
        input integer destination_column;
        input [7:0] value;
        integer distance;
        integer hop;
        begin
            direction = direction_value;
            clear_and_release;
            @(negedge clk);
            set_inject(source_column, value);
            @(posedge clk); #1;
            check_cell(source_column, 1'b1, value);
            if (destination_column != source_column)
                check_cell(destination_column, 1'b0, 8'h00);
            @(negedge clk);
            inject_valid_i = {INJECT_WIDTH{1'b0}};
            inject_data_i = {INJECT_WIDTH*DATA_BITS{1'b0}};
            if (destination_column >= source_column)
                distance = destination_column - source_column;
            else
                distance = source_column - destination_column;
            for (hop = 1; hop <= distance*P_SR_HOP_CYCLES; hop = hop + 1) begin
                @(posedge clk); #1;
                if (hop < distance*P_SR_HOP_CYCLES)
                    check_cell(destination_column, 1'b0, 8'h00);
                else
                    check_cell(destination_column, 1'b1, value);
            end
            $display("HOP_RESULT direction=%0d src=%0d dst=%0d predicted=%0d",
                     direction_value, source_column, destination_column,
                     distance*P_SR_HOP_CYCLES);
        end
    endtask

    task write_trace_cycle;
        input integer trace_cycle;
        reg [7:0] trace_data;
        reg trace_valid;
        begin
            for (column = 0; column < COLUMN_NUM; column = column + 1) begin
                state_index = column*COLUMN_CELLS;
                trace_valid = state_valid_out[state_index];
                if (trace_valid)
                    trace_data = state_data_out[state_index*DATA_BITS +: DATA_BITS];
                else
                    trace_data = 8'h00;
                $fdisplay(trace_file, "%0d,0,0,%0d,0,0,0,%0d,%0d",
                          trace_cycle, column, trace_valid, trace_data);
            end
        end
    endtask

    task generate_rtl_trace;
        integer trace_cycle;
        begin
            direction = 1'b0;
            clear_and_release;
            trace_file = $fopen("sim/trace/rtl_srf_trace.csv", "w");
            if (trace_file == 0) begin
                errors = errors + 1;
            end else begin
                $fdisplay(trace_file,
                    "cycle,hemisphere,direction,column,superlane,stream,lane,valid,data");
                write_trace_cycle(0);
                @(negedge clk); set_inject(0, 8'h5a);
                for (trace_cycle = 1; trace_cycle <= COLUMN_NUM;
                     trace_cycle = trace_cycle + 1) begin
                    @(posedge clk); #1;
                    write_trace_cycle(trace_cycle);
                    @(negedge clk);
                    inject_valid_i = {INJECT_WIDTH{1'b0}};
                    inject_data_i = {INJECT_WIDTH*DATA_BITS{1'b0}};
                end
                $fclose(trace_file);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_ni = 1'b0;
        direction = 1'b0;
        inject_valid_i = {INJECT_WIDTH{1'b0}};
        inject_data_i = {INJECT_WIDTH*DATA_BITS{1'b0}};
        errors = 0;

        $display("RUN_TEST hop_trace_csv");
        generate_rtl_trace;
        $display("RUN_TEST hop_east_0_1"); run_hop_case(0, 0, 1, 8'h01);
        $display("RUN_TEST hop_east_0_5"); run_hop_case(0, 0, 5, 8'h05);
        $display("RUN_TEST hop_east_0_15"); run_hop_case(0, 0, 15, 8'h0f);
        $display("RUN_TEST hop_east_3_10"); run_hop_case(0, 3, 10, 8'h3a);
        $display("RUN_TEST hop_west_15_14"); run_hop_case(1, 15, 14, 8'hfe);
        $display("RUN_TEST hop_west_15_8"); run_hop_case(1, 15, 8, 8'hf8);
        $display("RUN_TEST hop_west_15_0"); run_hop_case(1, 15, 0, 8'hf0);
        $display("RUN_TEST hop_west_12_4"); run_hop_case(1, 12, 4, 8'hc4);

        if (errors == 0)
            $display("TEST_PASS");
        else
            $display("TEST_FAIL errors=%0d", errors);
        $finish;
    end
endmodule
