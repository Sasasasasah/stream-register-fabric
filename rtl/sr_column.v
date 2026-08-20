`timescale 1ns/1ps

// A column is a structural wrapper around independent superlane leaves.
// It deliberately contains no registers or cross-superlane behavior.
module sr_column #(
    parameter P_SUPERLANES_PER_COLUMN = 4,
    parameter P_STREAMS_PER_DIR       = 32,
    parameter P_LANES_PER_SUPERLANE   = 8,
    parameter P_SR_DATA_BITS          = 8,
    parameter P_LOCAL_PRODUCERS       = 2,
    parameter P_LOCAL_CONSUMERS       = 2
) (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] column_data_in,
    input  wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                column_valid_in,
    output wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] column_data_out,
    output wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                column_valid_out,
    output wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] column_state_data_out,
    output wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                column_state_valid_out,

    // Packed layout is [superlane][producer/consumer][stream][lane].
    input  wire [P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] inject_valid_i,
    input  wire [P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] inject_data_i,
    input  wire [P_SUPERLANES_PER_COLUMN*P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] consume_i,
    output wire [P_SUPERLANES_PER_COLUMN-1:0] collision_o,
    output wire [P_SUPERLANES_PER_COLUMN-1:0] invalid_consume_o
);

    localparam LEAF_CELL_NUM      = P_STREAMS_PER_DIR * P_LANES_PER_SUPERLANE;
    localparam LEAF_DATA_WIDTH    = LEAF_CELL_NUM * P_SR_DATA_BITS;
    localparam LEAF_INJECT_WIDTH  = P_LOCAL_PRODUCERS * LEAF_CELL_NUM;
    localparam LEAF_CONSUME_WIDTH = P_LOCAL_CONSUMERS * LEAF_CELL_NUM;

    genvar superlane;
    generate
        for (superlane = 0; superlane < P_SUPERLANES_PER_COLUMN; superlane = superlane + 1) begin : g_superlane_leaf
            sr_leaf #(
                .P_STREAMS_PER_DIR      (P_STREAMS_PER_DIR),
                .P_LANES_PER_SUPERLANE  (P_LANES_PER_SUPERLANE),
                .P_SR_DATA_BITS         (P_SR_DATA_BITS),
                .P_LOCAL_PRODUCERS      (P_LOCAL_PRODUCERS),
                .P_LOCAL_CONSUMERS      (P_LOCAL_CONSUMERS)
            ) u_sr_leaf (
                .clk_i              (clk_i),
                .rst_ni             (rst_ni),
                .upstream_data_i    (column_data_in[superlane*LEAF_DATA_WIDTH +: LEAF_DATA_WIDTH]),
                .upstream_valid_i   (column_valid_in[superlane*LEAF_CELL_NUM +: LEAF_CELL_NUM]),
                .downstream_data_o  (column_data_out[superlane*LEAF_DATA_WIDTH +: LEAF_DATA_WIDTH]),
                .downstream_valid_o (column_valid_out[superlane*LEAF_CELL_NUM +: LEAF_CELL_NUM]),
                .state_data_o       (column_state_data_out[superlane*LEAF_DATA_WIDTH +: LEAF_DATA_WIDTH]),
                .state_valid_o      (column_state_valid_out[superlane*LEAF_CELL_NUM +: LEAF_CELL_NUM]),
                .inject_valid_i     (inject_valid_i[superlane*LEAF_INJECT_WIDTH +: LEAF_INJECT_WIDTH]),
                .inject_data_i      (inject_data_i[superlane*LEAF_INJECT_WIDTH*P_SR_DATA_BITS +: LEAF_INJECT_WIDTH*P_SR_DATA_BITS]),
                .consume_i          (consume_i[superlane*LEAF_CONSUME_WIDTH +: LEAF_CONSUME_WIDTH]),
                .collision_o        (collision_o[superlane]),
                .invalid_consume_o  (invalid_consume_o[superlane])
            );
        end
    endgenerate
endmodule
