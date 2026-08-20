`timescale 1ns/1ps

// One fixed-topology SRF direction. DIRECTION is an elaboration parameter:
// 0 selects Eastward column 0 -> N-1; 1 selects Westward column N-1 -> 0.
// Every column contains one registered leaf hop and this wrapper owns no state.
module sr_direction_fabric #(
    parameter SR_COLUMNS_PER_HEMI       = 16,
    parameter P_SUPERLANES_PER_COLUMN   = 4,
    parameter P_STREAMS_PER_DIR         = 32,
    parameter P_LANES_PER_SUPERLANE     = 8,
    parameter P_SR_DATA_BITS            = 8,
    parameter P_SR_HOP_CYCLES           = 1,
    parameter P_LOCAL_PRODUCERS         = 2,
    parameter P_LOCAL_CONSUMERS         = 2,
    parameter DIRECTION                 = 0
) (
    input  wire clk_i,
    input  wire rst_ni,
    input  wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] stream_data_in,
    input  wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                stream_valid_in,
    output wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] stream_data_out,
    output wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                stream_valid_out,

    // [column][superlane][producer/consumer][stream][lane][data bit]
    input  wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] inject_valid_i,
    input  wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] inject_data_i,
    input  wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] consume_i,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN-1:0] collision_o,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN-1:0] invalid_consume_o,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] state_data_out,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                state_valid_out
);

    localparam LEAF_CELL_NUM        = P_STREAMS_PER_DIR * P_LANES_PER_SUPERLANE;
    localparam COLUMN_DATA_WIDTH    = P_SUPERLANES_PER_COLUMN * LEAF_CELL_NUM * P_SR_DATA_BITS;
    localparam COLUMN_VALID_WIDTH   = P_SUPERLANES_PER_COLUMN * LEAF_CELL_NUM;
    localparam COLUMN_INJECT_WIDTH  = P_SUPERLANES_PER_COLUMN * P_LOCAL_PRODUCERS * LEAF_CELL_NUM;
    localparam COLUMN_CONSUME_WIDTH = P_SUPERLANES_PER_COLUMN * P_LOCAL_CONSUMERS * LEAF_CELL_NUM;

    wire [SR_COLUMNS_PER_HEMI*COLUMN_DATA_WIDTH-1:0]  column_data_in_bus;
    wire [SR_COLUMNS_PER_HEMI*COLUMN_DATA_WIDTH-1:0]  column_data_out_bus;
    wire [SR_COLUMNS_PER_HEMI*COLUMN_VALID_WIDTH-1:0] column_valid_in_bus;
    wire [SR_COLUMNS_PER_HEMI*COLUMN_VALID_WIDTH-1:0] column_valid_out_bus;

    genvar column;
    generate
        for (column = 0; column < SR_COLUMNS_PER_HEMI; column = column + 1) begin : g_column
            wire [COLUMN_DATA_WIDTH-1:0]  east_data_source;
            wire [COLUMN_DATA_WIDTH-1:0]  west_data_source;
            wire [COLUMN_VALID_WIDTH-1:0] east_valid_source;
            wire [COLUMN_VALID_WIDTH-1:0] west_valid_source;

            if (column == 0) begin : g_east_boundary
                assign east_data_source = stream_data_in;
                assign east_valid_source = stream_valid_in;
            end else begin : g_east_chain
                assign east_data_source =
                    column_data_out_bus[(column-1)*COLUMN_DATA_WIDTH +: COLUMN_DATA_WIDTH];
                assign east_valid_source =
                    column_valid_out_bus[(column-1)*COLUMN_VALID_WIDTH +: COLUMN_VALID_WIDTH];
            end

            if (column == SR_COLUMNS_PER_HEMI-1) begin : g_west_boundary
                assign west_data_source = stream_data_in;
                assign west_valid_source = stream_valid_in;
            end else begin : g_west_chain
                assign west_data_source =
                    column_data_out_bus[(column+1)*COLUMN_DATA_WIDTH +: COLUMN_DATA_WIDTH];
                assign west_valid_source =
                    column_valid_out_bus[(column+1)*COLUMN_VALID_WIDTH +: COLUMN_VALID_WIDTH];
            end

            assign column_data_in_bus[column*COLUMN_DATA_WIDTH +: COLUMN_DATA_WIDTH] =
                DIRECTION ? west_data_source : east_data_source;
            assign column_valid_in_bus[column*COLUMN_VALID_WIDTH +: COLUMN_VALID_WIDTH] =
                DIRECTION ? west_valid_source : east_valid_source;

            sr_column #(
                .P_SUPERLANES_PER_COLUMN (P_SUPERLANES_PER_COLUMN),
                .P_STREAMS_PER_DIR       (P_STREAMS_PER_DIR),
                .P_LANES_PER_SUPERLANE   (P_LANES_PER_SUPERLANE),
                .P_SR_DATA_BITS          (P_SR_DATA_BITS),
                .P_LOCAL_PRODUCERS       (P_LOCAL_PRODUCERS),
                .P_LOCAL_CONSUMERS       (P_LOCAL_CONSUMERS)
            ) u_sr_column (
                .clk_i                  (clk_i),
                .rst_ni                 (rst_ni),
                .column_data_in         (column_data_in_bus[column*COLUMN_DATA_WIDTH +: COLUMN_DATA_WIDTH]),
                .column_valid_in        (column_valid_in_bus[column*COLUMN_VALID_WIDTH +: COLUMN_VALID_WIDTH]),
                .column_data_out        (column_data_out_bus[column*COLUMN_DATA_WIDTH +: COLUMN_DATA_WIDTH]),
                .column_valid_out       (column_valid_out_bus[column*COLUMN_VALID_WIDTH +: COLUMN_VALID_WIDTH]),
                .column_state_data_out  (state_data_out[column*COLUMN_DATA_WIDTH +: COLUMN_DATA_WIDTH]),
                .column_state_valid_out (state_valid_out[column*COLUMN_VALID_WIDTH +: COLUMN_VALID_WIDTH]),
                .inject_valid_i         (inject_valid_i[column*COLUMN_INJECT_WIDTH +: COLUMN_INJECT_WIDTH]),
                .inject_data_i          (inject_data_i[column*COLUMN_INJECT_WIDTH*P_SR_DATA_BITS +: COLUMN_INJECT_WIDTH*P_SR_DATA_BITS]),
                .consume_i              (consume_i[column*COLUMN_CONSUME_WIDTH +: COLUMN_CONSUME_WIDTH]),
                .collision_o            (collision_o[column*P_SUPERLANES_PER_COLUMN +: P_SUPERLANES_PER_COLUMN]),
                .invalid_consume_o      (invalid_consume_o[column*P_SUPERLANES_PER_COLUMN +: P_SUPERLANES_PER_COLUMN])
            );
        end
    endgenerate

    // P_SR_HOP_CYCLES is the compiler-visible contract and is fixed to one by
    // the one-leaf-per-column architecture. No output register is added here.
    assign stream_data_out = DIRECTION ?
        column_data_out_bus[0 +: COLUMN_DATA_WIDTH] :
        column_data_out_bus[(SR_COLUMNS_PER_HEMI-1)*COLUMN_DATA_WIDTH +: COLUMN_DATA_WIDTH];
    assign stream_valid_out = DIRECTION ?
        column_valid_out_bus[0 +: COLUMN_VALID_WIDTH] :
        column_valid_out_bus[(SR_COLUMNS_PER_HEMI-1)*COLUMN_VALID_WIDTH +: COLUMN_VALID_WIDTH];

endmodule
