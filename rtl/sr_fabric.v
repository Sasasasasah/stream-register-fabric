`timescale 1ns/1ps

// Full-chip SRF hierarchy for the configurable two-hemisphere example profile.
// Packed path order is [hemisphere][direction], where hemisphere 0 is WEST,
// hemisphere 1 is EAST, direction 0 is Eastward, and direction 1 is Westward.
// The wrapper contains no payload/valid state and adds no pipeline cycle.
module sr_fabric #(
    parameter P_HEMISPHERES               = 2,
    parameter SR_COLUMNS_PER_HEMI          = 16,
    parameter P_SUPERLANES_PER_COLUMN      = 4,
    parameter P_STREAMS_PER_DIR            = 32,
    parameter P_LANES_PER_SUPERLANE        = 8,
    parameter P_SR_DATA_BITS               = 8,
    parameter P_SR_HOP_CYCLES              = 1,
    parameter P_LOCAL_PRODUCERS            = 2,
    parameter P_LOCAL_CONSUMERS            = 2
) (
    input  wire clk_i,
    input  wire rst_ni,

    // Four independent logical boundary paths. For each hemisphere, the
    // Eastward input and Westward output are its unconnected central boundary
    // ports for a future VXM bridge; no cross-hemisphere forwarding exists.
    input  wire [P_HEMISPHERES*2*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] boundary_input_data,
    input  wire [P_HEMISPHERES*2*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]           boundary_input_valid,
    output wire [P_HEMISPHERES*2*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] boundary_output_data,
    output wire [P_HEMISPHERES*2*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]           boundary_output_valid,

    // Packed dimensions:
    // [hemisphere][direction][column][superlane]
    // [producer/consumer][stream][lane][data bit].
    input  wire [P_HEMISPHERES*2*SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] inject_valid_i,
    input  wire [P_HEMISPHERES*2*SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] inject_data_i,
    input  wire [P_HEMISPHERES*2*SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] consume_i,
    output wire [P_HEMISPHERES*2*SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN-1:0] collision_o,
    output wire [P_HEMISPHERES*2*SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN-1:0] invalid_consume_o,

    output wire [P_HEMISPHERES*2*SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] state_data_out,
    output wire [P_HEMISPHERES*2*SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]           state_valid_out,

    output wire fabric_collision,
    output wire fabric_invalid_consume
);

    localparam integer DIRECTION_NUM = 2;
    localparam integer PATH_NUM = P_HEMISPHERES * DIRECTION_NUM;
    localparam integer BOUNDARY_DATA_WIDTH =
        P_SUPERLANES_PER_COLUMN * P_STREAMS_PER_DIR * P_LANES_PER_SUPERLANE * P_SR_DATA_BITS;
    localparam integer BOUNDARY_VALID_WIDTH =
        P_SUPERLANES_PER_COLUMN * P_STREAMS_PER_DIR * P_LANES_PER_SUPERLANE;
    localparam integer DIRECTION_INJECT_WIDTH =
        SR_COLUMNS_PER_HEMI * P_SUPERLANES_PER_COLUMN * P_LOCAL_PRODUCERS * P_STREAMS_PER_DIR * P_LANES_PER_SUPERLANE;
    localparam integer DIRECTION_CONSUME_WIDTH =
        SR_COLUMNS_PER_HEMI * P_SUPERLANES_PER_COLUMN * P_LOCAL_CONSUMERS * P_STREAMS_PER_DIR * P_LANES_PER_SUPERLANE;
    localparam integer DIRECTION_ERROR_WIDTH = SR_COLUMNS_PER_HEMI * P_SUPERLANES_PER_COLUMN;
    localparam integer DIRECTION_STATE_DATA_WIDTH =
        SR_COLUMNS_PER_HEMI * P_SUPERLANES_PER_COLUMN * P_STREAMS_PER_DIR * P_LANES_PER_SUPERLANE * P_SR_DATA_BITS;
    localparam integer DIRECTION_STATE_VALID_WIDTH =
        SR_COLUMNS_PER_HEMI * P_SUPERLANES_PER_COLUMN * P_STREAMS_PER_DIR * P_LANES_PER_SUPERLANE;

    // Public structural audit constants used by the default-profile test.
    localparam integer FULL_CHIP_INSTANCE_NUM = 1;
    localparam integer HEMISPHERE_INSTANCE_NUM = P_HEMISPHERES;
    localparam integer DIRECTION_INSTANCE_NUM = P_HEMISPHERES * DIRECTION_NUM;
    localparam integer COLUMN_INSTANCE_NUM =
        P_HEMISPHERES * DIRECTION_NUM * SR_COLUMNS_PER_HEMI;
    localparam integer LEAF_INSTANCE_NUM =
        P_HEMISPHERES * DIRECTION_NUM * SR_COLUMNS_PER_HEMI * P_SUPERLANES_PER_COLUMN;

    // Fixed full-chip path indices.
    localparam integer WEST_HEMI_EAST_PATH = 0;
    localparam integer WEST_HEMI_WEST_PATH = 1;
    localparam integer EAST_HEMI_EAST_PATH = 2;
    localparam integer EAST_HEMI_WEST_PATH = 3;

    sr_hemisphere_fabric #(
        .SR_COLUMNS_PER_HEMI         (SR_COLUMNS_PER_HEMI),
        .P_SUPERLANES_PER_COLUMN     (P_SUPERLANES_PER_COLUMN),
        .P_STREAMS_PER_DIR           (P_STREAMS_PER_DIR),
        .P_LANES_PER_SUPERLANE       (P_LANES_PER_SUPERLANE),
        .P_SR_DATA_BITS              (P_SR_DATA_BITS),
        .P_SR_HOP_CYCLES             (P_SR_HOP_CYCLES),
        .P_LOCAL_PRODUCERS           (P_LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS           (P_LOCAL_CONSUMERS)
    ) u_west_hemisphere (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .east_input_data(boundary_input_data[WEST_HEMI_EAST_PATH*BOUNDARY_DATA_WIDTH +: BOUNDARY_DATA_WIDTH]),
        .east_input_valid(boundary_input_valid[WEST_HEMI_EAST_PATH*BOUNDARY_VALID_WIDTH +: BOUNDARY_VALID_WIDTH]),
        .east_output_data(boundary_output_data[WEST_HEMI_EAST_PATH*BOUNDARY_DATA_WIDTH +: BOUNDARY_DATA_WIDTH]),
        .east_output_valid(boundary_output_valid[WEST_HEMI_EAST_PATH*BOUNDARY_VALID_WIDTH +: BOUNDARY_VALID_WIDTH]),
        .east_inject_valid(inject_valid_i[WEST_HEMI_EAST_PATH*DIRECTION_INJECT_WIDTH +: DIRECTION_INJECT_WIDTH]),
        .east_inject_data(inject_data_i[WEST_HEMI_EAST_PATH*DIRECTION_INJECT_WIDTH*P_SR_DATA_BITS +: DIRECTION_INJECT_WIDTH*P_SR_DATA_BITS]),
        .east_consume(consume_i[WEST_HEMI_EAST_PATH*DIRECTION_CONSUME_WIDTH +: DIRECTION_CONSUME_WIDTH]),
        .east_collision(collision_o[WEST_HEMI_EAST_PATH*DIRECTION_ERROR_WIDTH +: DIRECTION_ERROR_WIDTH]),
        .east_invalid_consume(invalid_consume_o[WEST_HEMI_EAST_PATH*DIRECTION_ERROR_WIDTH +: DIRECTION_ERROR_WIDTH]),
        .east_state_data(state_data_out[WEST_HEMI_EAST_PATH*DIRECTION_STATE_DATA_WIDTH +: DIRECTION_STATE_DATA_WIDTH]),
        .east_state_valid(state_valid_out[WEST_HEMI_EAST_PATH*DIRECTION_STATE_VALID_WIDTH +: DIRECTION_STATE_VALID_WIDTH]),
        .west_input_data(boundary_input_data[WEST_HEMI_WEST_PATH*BOUNDARY_DATA_WIDTH +: BOUNDARY_DATA_WIDTH]),
        .west_input_valid(boundary_input_valid[WEST_HEMI_WEST_PATH*BOUNDARY_VALID_WIDTH +: BOUNDARY_VALID_WIDTH]),
        .west_output_data(boundary_output_data[WEST_HEMI_WEST_PATH*BOUNDARY_DATA_WIDTH +: BOUNDARY_DATA_WIDTH]),
        .west_output_valid(boundary_output_valid[WEST_HEMI_WEST_PATH*BOUNDARY_VALID_WIDTH +: BOUNDARY_VALID_WIDTH]),
        .west_inject_valid(inject_valid_i[WEST_HEMI_WEST_PATH*DIRECTION_INJECT_WIDTH +: DIRECTION_INJECT_WIDTH]),
        .west_inject_data(inject_data_i[WEST_HEMI_WEST_PATH*DIRECTION_INJECT_WIDTH*P_SR_DATA_BITS +: DIRECTION_INJECT_WIDTH*P_SR_DATA_BITS]),
        .west_consume(consume_i[WEST_HEMI_WEST_PATH*DIRECTION_CONSUME_WIDTH +: DIRECTION_CONSUME_WIDTH]),
        .west_collision(collision_o[WEST_HEMI_WEST_PATH*DIRECTION_ERROR_WIDTH +: DIRECTION_ERROR_WIDTH]),
        .west_invalid_consume(invalid_consume_o[WEST_HEMI_WEST_PATH*DIRECTION_ERROR_WIDTH +: DIRECTION_ERROR_WIDTH]),
        .west_state_data(state_data_out[WEST_HEMI_WEST_PATH*DIRECTION_STATE_DATA_WIDTH +: DIRECTION_STATE_DATA_WIDTH]),
        .west_state_valid(state_valid_out[WEST_HEMI_WEST_PATH*DIRECTION_STATE_VALID_WIDTH +: DIRECTION_STATE_VALID_WIDTH]),
        .hemisphere_collision(), .hemisphere_invalid_consume()
    );

    sr_hemisphere_fabric #(
        .SR_COLUMNS_PER_HEMI         (SR_COLUMNS_PER_HEMI),
        .P_SUPERLANES_PER_COLUMN     (P_SUPERLANES_PER_COLUMN),
        .P_STREAMS_PER_DIR           (P_STREAMS_PER_DIR),
        .P_LANES_PER_SUPERLANE       (P_LANES_PER_SUPERLANE),
        .P_SR_DATA_BITS              (P_SR_DATA_BITS),
        .P_SR_HOP_CYCLES             (P_SR_HOP_CYCLES),
        .P_LOCAL_PRODUCERS           (P_LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS           (P_LOCAL_CONSUMERS)
    ) u_east_hemisphere (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .east_input_data(boundary_input_data[EAST_HEMI_EAST_PATH*BOUNDARY_DATA_WIDTH +: BOUNDARY_DATA_WIDTH]),
        .east_input_valid(boundary_input_valid[EAST_HEMI_EAST_PATH*BOUNDARY_VALID_WIDTH +: BOUNDARY_VALID_WIDTH]),
        .east_output_data(boundary_output_data[EAST_HEMI_EAST_PATH*BOUNDARY_DATA_WIDTH +: BOUNDARY_DATA_WIDTH]),
        .east_output_valid(boundary_output_valid[EAST_HEMI_EAST_PATH*BOUNDARY_VALID_WIDTH +: BOUNDARY_VALID_WIDTH]),
        .east_inject_valid(inject_valid_i[EAST_HEMI_EAST_PATH*DIRECTION_INJECT_WIDTH +: DIRECTION_INJECT_WIDTH]),
        .east_inject_data(inject_data_i[EAST_HEMI_EAST_PATH*DIRECTION_INJECT_WIDTH*P_SR_DATA_BITS +: DIRECTION_INJECT_WIDTH*P_SR_DATA_BITS]),
        .east_consume(consume_i[EAST_HEMI_EAST_PATH*DIRECTION_CONSUME_WIDTH +: DIRECTION_CONSUME_WIDTH]),
        .east_collision(collision_o[EAST_HEMI_EAST_PATH*DIRECTION_ERROR_WIDTH +: DIRECTION_ERROR_WIDTH]),
        .east_invalid_consume(invalid_consume_o[EAST_HEMI_EAST_PATH*DIRECTION_ERROR_WIDTH +: DIRECTION_ERROR_WIDTH]),
        .east_state_data(state_data_out[EAST_HEMI_EAST_PATH*DIRECTION_STATE_DATA_WIDTH +: DIRECTION_STATE_DATA_WIDTH]),
        .east_state_valid(state_valid_out[EAST_HEMI_EAST_PATH*DIRECTION_STATE_VALID_WIDTH +: DIRECTION_STATE_VALID_WIDTH]),
        .west_input_data(boundary_input_data[EAST_HEMI_WEST_PATH*BOUNDARY_DATA_WIDTH +: BOUNDARY_DATA_WIDTH]),
        .west_input_valid(boundary_input_valid[EAST_HEMI_WEST_PATH*BOUNDARY_VALID_WIDTH +: BOUNDARY_VALID_WIDTH]),
        .west_output_data(boundary_output_data[EAST_HEMI_WEST_PATH*BOUNDARY_DATA_WIDTH +: BOUNDARY_DATA_WIDTH]),
        .west_output_valid(boundary_output_valid[EAST_HEMI_WEST_PATH*BOUNDARY_VALID_WIDTH +: BOUNDARY_VALID_WIDTH]),
        .west_inject_valid(inject_valid_i[EAST_HEMI_WEST_PATH*DIRECTION_INJECT_WIDTH +: DIRECTION_INJECT_WIDTH]),
        .west_inject_data(inject_data_i[EAST_HEMI_WEST_PATH*DIRECTION_INJECT_WIDTH*P_SR_DATA_BITS +: DIRECTION_INJECT_WIDTH*P_SR_DATA_BITS]),
        .west_consume(consume_i[EAST_HEMI_WEST_PATH*DIRECTION_CONSUME_WIDTH +: DIRECTION_CONSUME_WIDTH]),
        .west_collision(collision_o[EAST_HEMI_WEST_PATH*DIRECTION_ERROR_WIDTH +: DIRECTION_ERROR_WIDTH]),
        .west_invalid_consume(invalid_consume_o[EAST_HEMI_WEST_PATH*DIRECTION_ERROR_WIDTH +: DIRECTION_ERROR_WIDTH]),
        .west_state_data(state_data_out[EAST_HEMI_WEST_PATH*DIRECTION_STATE_DATA_WIDTH +: DIRECTION_STATE_DATA_WIDTH]),
        .west_state_valid(state_valid_out[EAST_HEMI_WEST_PATH*DIRECTION_STATE_VALID_WIDTH +: DIRECTION_STATE_VALID_WIDTH]),
        .hemisphere_collision(), .hemisphere_invalid_consume()
    );

    assign fabric_collision = |collision_o;
    assign fabric_invalid_consume = |invalid_consume_o;

endmodule
