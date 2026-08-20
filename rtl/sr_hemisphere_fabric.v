`timescale 1ns/1ps

// One hemisphere contains two physically independent, fixed-topology
// direction fabrics. This wrapper distributes parameters/clock/reset and
// lifts port dimensions; it owns no payload, valid, command, or access state.
module sr_hemisphere_fabric #(
    parameter SR_COLUMNS_PER_HEMI       = 16,
    parameter P_SUPERLANES_PER_COLUMN   = 4,
    parameter P_STREAMS_PER_DIR         = 32,
    parameter P_LANES_PER_SUPERLANE     = 8,
    parameter P_SR_DATA_BITS            = 8,
    parameter P_SR_HOP_CYCLES           = 1,
    parameter P_LOCAL_PRODUCERS         = 2,
    parameter P_LOCAL_CONSUMERS         = 2
) (
    input  wire clk_i,
    input  wire rst_ni,

    input  wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] east_input_data,
    input  wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                east_input_valid,
    output wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] east_output_data,
    output wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                east_output_valid,
    input  wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] east_inject_valid,
    input  wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] east_inject_data,
    input  wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] east_consume,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN-1:0] east_collision,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN-1:0] east_invalid_consume,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] east_state_data,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                east_state_valid,

    input  wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] west_input_data,
    input  wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                west_input_valid,
    output wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] west_output_data,
    output wire [P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                west_output_valid,
    input  wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] west_inject_valid,
    input  wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] west_inject_data,
    input  wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] west_consume,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN-1:0] west_collision,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN-1:0] west_invalid_consume,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] west_state_data,
    output wire [SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                west_state_valid,

    output wire hemisphere_collision,
    output wire hemisphere_invalid_consume
);

    sr_direction_fabric #(
        .SR_COLUMNS_PER_HEMI       (SR_COLUMNS_PER_HEMI),
        .P_SUPERLANES_PER_COLUMN   (P_SUPERLANES_PER_COLUMN),
        .P_STREAMS_PER_DIR         (P_STREAMS_PER_DIR),
        .P_LANES_PER_SUPERLANE     (P_LANES_PER_SUPERLANE),
        .P_SR_DATA_BITS            (P_SR_DATA_BITS),
        .P_SR_HOP_CYCLES           (P_SR_HOP_CYCLES),
        .P_LOCAL_PRODUCERS         (P_LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS         (P_LOCAL_CONSUMERS),
        .DIRECTION                 (0)
    ) u_east_direction_fabric (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .stream_data_in(east_input_data),
        .stream_valid_in(east_input_valid),
        .stream_data_out(east_output_data),
        .stream_valid_out(east_output_valid),
        .inject_valid_i(east_inject_valid),
        .inject_data_i(east_inject_data),
        .consume_i(east_consume),
        .collision_o(east_collision),
        .invalid_consume_o(east_invalid_consume),
        .state_data_out(east_state_data),
        .state_valid_out(east_state_valid)
    );

    sr_direction_fabric #(
        .SR_COLUMNS_PER_HEMI       (SR_COLUMNS_PER_HEMI),
        .P_SUPERLANES_PER_COLUMN   (P_SUPERLANES_PER_COLUMN),
        .P_STREAMS_PER_DIR         (P_STREAMS_PER_DIR),
        .P_LANES_PER_SUPERLANE     (P_LANES_PER_SUPERLANE),
        .P_SR_DATA_BITS            (P_SR_DATA_BITS),
        .P_SR_HOP_CYCLES           (P_SR_HOP_CYCLES),
        .P_LOCAL_PRODUCERS         (P_LOCAL_PRODUCERS),
        .P_LOCAL_CONSUMERS         (P_LOCAL_CONSUMERS),
        .DIRECTION                 (1)
    ) u_west_direction_fabric (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .stream_data_in(west_input_data),
        .stream_valid_in(west_input_valid),
        .stream_data_out(west_output_data),
        .stream_valid_out(west_output_valid),
        .inject_valid_i(west_inject_valid),
        .inject_data_i(west_inject_data),
        .consume_i(west_consume),
        .collision_o(west_collision),
        .invalid_consume_o(west_invalid_consume),
        .state_data_out(west_state_data),
        .state_valid_out(west_state_valid)
    );

    assign hemisphere_collision = (|east_collision) | (|west_collision);
    assign hemisphere_invalid_consume =
        (|east_invalid_consume) | (|west_invalid_consume);

endmodule
