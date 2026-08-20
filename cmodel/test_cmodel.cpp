#include "srf_model.h"

#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>

namespace {

std::uint64_t make_raw_command(std::uint8_t opcode,
                               std::uint8_t column,
                               std::uint8_t superlane,
                               std::uint8_t stream,
                               std::uint8_t lane,
                               std::uint8_t data) {
    return (static_cast<std::uint64_t>(opcode) << 56) |
           (static_cast<std::uint64_t>(column) << 48) |
           (static_cast<std::uint64_t>(superlane) << 40) |
           (static_cast<std::uint64_t>(stream) << 32) |
           (static_cast<std::uint64_t>(lane) << 24) |
           (static_cast<std::uint64_t>(data) << 16);
}

Command make_command(std::uint8_t opcode,
                     std::uint8_t column,
                     std::uint8_t superlane,
                     std::uint8_t stream,
                     std::uint8_t lane,
                     std::uint8_t data = 0) {
    return Command::decode(make_raw_command(opcode,
                                            column,
                                            superlane,
                                            stream,
                                            lane,
                                            data));
}

void check(bool condition, const char* name, bool& passed) {
    if (!condition) {
        std::cout << "CHECK_FAIL " << name << '\n';
        passed = false;
    }
}

bool cell_matches(const SRFModel& model,
                  std::uint8_t column,
                  std::uint8_t superlane,
                  std::uint8_t stream,
                  std::uint8_t lane,
                  bool expected_valid,
                  std::uint8_t expected_data) {
    const CommandResult result =
        model.read_cell(column, superlane, stream, lane);
    return result.success &&
           result.valid == expected_valid &&
           (!expected_valid || result.data == expected_data);
}

bool hemisphere_cell_matches(const HemisphereModel& model,
                             Direction direction,
                             std::uint8_t column,
                             std::uint8_t superlane,
                             std::uint8_t stream,
                             std::uint8_t lane,
                             bool expected_valid,
                             std::uint8_t expected_data) {
    const CommandResult result =
        model.read_cell(direction, column, superlane, stream, lane);
    return result.success &&
           result.valid == expected_valid &&
           (!expected_valid || result.data == expected_data);
}

bool full_chip_cell_matches(const FullChipModel& model,
                            Hemisphere hemisphere,
                            Direction direction,
                            std::uint8_t column,
                            std::uint8_t superlane,
                            std::uint8_t stream,
                            std::uint8_t lane,
                            bool expected_valid,
                            std::uint8_t expected_data) {
    const CommandResult result = model.read_cell(
        hemisphere, direction, column, superlane, stream, lane);
    return result.success && result.valid == expected_valid &&
           (!expected_valid || result.data == expected_data);
}

}  // namespace

int main() {
    bool passed = true;
    SRFModel model;

    std::cout << "RUN_TEST single_cell_latency\n";
    model.set_direction(Direction::EAST);
    check(model.inject_cell(0, 0, 0, 0, 0, 0x55),
          "latency_inject", passed);
    check(cell_matches(model, 0, 0, 0, 0, false, 0),
          "inject_committed_before_step", passed);
    for (std::size_t cycle = 0; cycle < SRFModel::COLUMN_NUM - 1; ++cycle) {
        model.step();
        check(cell_matches(model, 3, 0, 0, 0, false, 0),
              "early_output_before_full_latency", passed);
    }
    model.step();
    check(model.cycle() == SRFModel::COLUMN_NUM,
          "single_cell_cycle_count", passed);
    check(cell_matches(model, 3, 0, 0, 0, true, 0x55),
          "single_cell_final_position", passed);

    std::cout << "RUN_TEST east_propagation\n";
    model.reset();
    model.set_direction(Direction::EAST);
    check(model.inject_cell(0, 0, 1, 2, 3, 0xe1),
          "east_inject", passed);
    for (std::uint8_t column = 0;
         column < SRFModel::COLUMN_NUM;
         ++column) {
        model.step();
        check(cell_matches(model, column, 1, 2, 3, true, 0xe1),
              "east_stage_position", passed);
        if (column > 0) {
            check(cell_matches(model,
                               static_cast<std::uint8_t>(column - 1),
                               1, 2, 3, false, 0),
                  "east_no_duplicate_stage", passed);
        }
    }

    std::cout << "RUN_TEST west_propagation\n";
    model.reset();
    model.set_direction(Direction::WEST);
    check(model.inject_cell(1, 3, 0, 3, 1, 0xf2),
          "west_inject", passed);
    for (int column = static_cast<int>(SRFModel::COLUMN_NUM) - 1;
         column >= 0;
         --column) {
        model.step();
        check(cell_matches(model,
                           static_cast<std::uint8_t>(column),
                           0, 3, 1, true, 0xf2),
              "west_stage_position", passed);
        if (column + 1 < static_cast<int>(SRFModel::COLUMN_NUM)) {
            check(cell_matches(model,
                               static_cast<std::uint8_t>(column + 1),
                               0, 3, 1, false, 0),
                  "west_no_duplicate_stage", passed);
        }
    }

    std::cout << "RUN_TEST bubble_preservation\n";
    model.reset();
    model.set_direction(Direction::EAST);
    check(model.inject_cell(0, 0, 0, 1, 1, 0xa1),
          "bubble_first_inject", passed);
    model.step();                         // A enters column 0.
    model.step();                         // Bubble enters column 0.
    check(model.inject_cell(0, 0, 0, 1, 1, 0xa2),
          "bubble_second_inject", passed);
    model.step();                         // B enters column 0.
    model.step();                         // A reaches output.
    check(cell_matches(model, 3, 0, 1, 1, true, 0xa1),
          "bubble_output_a", passed);
    model.step();                         // Bubble reaches output.
    check(cell_matches(model, 3, 0, 1, 1, false, 0),
          "bubble_output_invalid", passed);
    model.step();                         // B reaches output.
    check(cell_matches(model, 3, 0, 1, 1, true, 0xa2),
          "bubble_output_b", passed);

    std::cout << "RUN_TEST inject_timing\n";
    model.reset();
    model.set_direction(Direction::EAST);
    check(model.inject_cell(0, 1, 1, 0, 2, 0x73),
          "timing_inject", passed);
    check(cell_matches(model, 1, 1, 0, 2, false, 0),
          "timing_no_early_commit", passed);
    model.step();
    check(cell_matches(model, 1, 1, 0, 2, true, 0x73),
          "timing_target_after_step", passed);
    check(cell_matches(model, 3, 1, 0, 2, false, 0),
          "timing_no_final_stage_jump", passed);

    std::cout << "RUN_TEST consume_blocking\n";
    model.reset();
    model.set_direction(Direction::EAST);
    check(model.inject_cell(0, 0, 0, 1, 2, 0x61),
          "consume_target_inject", passed);
    check(model.inject_cell(1, 0, 0, 2, 2, 0x62),
          "consume_other_inject", passed);
    model.step();
    check(model.consume_cell(0, 0, 0, 1, 2),
          "consume_schedule", passed);
    check(cell_matches(model, 0, 0, 1, 2, true, 0x61),
          "consume_preserves_current_state", passed);
    check(!model.invalid_consume_detected(),
          "valid_consume_not_invalid", passed);
    model.step();
    check(cell_matches(model, 1, 0, 1, 2, false, 0),
          "consume_blocks_downstream", passed);
    check(cell_matches(model, 1, 0, 2, 2, true, 0x62),
          "consume_does_not_block_other_cell", passed);

    model.reset();
    check(model.consume_cell(1, 0, 0, 3, 3),
          "invalid_consume_schedule", passed);
    check(model.invalid_consume_detected(),
          "invalid_consume_immediate_status", passed);
    model.step();
    check(model.invalid_consume_detected(),
          "invalid_consume_committed_status", passed);

    std::cout << "RUN_TEST direction_latency\n";
    model.reset();
    model.set_direction(Direction::EAST);
    check(model.inject_cell(0, 0, 0, 0, 3, 0x3e),
          "direction_east_inject", passed);
    while (!model.read_cell(3, 0, 0, 3).valid) {
        model.step();
    }
    const std::uint64_t east_latency = model.cycle();

    model.reset();
    model.set_direction(Direction::WEST);
    check(model.inject_cell(0, 3, 0, 0, 3, 0x3f),
          "direction_west_inject", passed);
    while (!model.read_cell(0, 0, 0, 3).valid) {
        model.step();
    }
    const std::uint64_t west_latency = model.cycle();
    check(east_latency == SRFModel::COLUMN_NUM,
          "east_latency_column_num", passed);
    check(west_latency == SRFModel::COLUMN_NUM,
          "west_latency_column_num", passed);
    check(east_latency == west_latency,
          "east_west_latency_equal", passed);

    std::cout << "RUN_TEST dump_state\n";
    model.reset();
    model.set_direction(Direction::EAST);
    check(model.inject_cell(0, 0, 0, 1, 3, 0x55),
          "dump_inject", passed);
    model.step();
    model.step();
    model.step();
    const std::string dump = model.dump_state();
    check(dump.find("cycle=3\n") != std::string::npos,
          "dump_cycle", passed);
    check(dump.find("column=2 superlane=0 stream=1 lane=3 data=0x55 valid=1") !=
              std::string::npos,
          "dump_cell", passed);

    std::cout << "RUN_TEST command_access_regression\n";
    model.reset();
    const Command write =
        make_command(SRFModel::OPCODE_WRITE, 0, 0, 0, 0, 0x44);
    check(model.execute(write).success, "command_write_schedule", passed);
    check(cell_matches(model, 0, 0, 0, 0, false, 0),
          "command_write_no_early_commit", passed);
    model.step();
    const CommandResult read = model.execute(
        make_command(SRFModel::OPCODE_READ, 0, 0, 0, 0));
    check(read.success && read.valid && read.data == 0x44,
          "command_write_read", passed);

    check(!model.inject_cell(2, 0, 0, 0, 0, 0xff),
          "invalid_producer", passed);
    check(!model.consume_cell(2, 0, 0, 0, 0),
          "invalid_consumer", passed);
    check(!model.inject_cell(0, 4, 0, 0, 0, 0xff),
          "invalid_address", passed);

    std::cout << "RUN_TEST collision_regression\n";
    model.reset();
    check(model.inject_cell(1, 0, 0, 2, 1, 0xaa),
          "collision_producer1", passed);
    check(model.inject_cell(0, 0, 0, 2, 1, 0x66),
          "collision_producer0", passed);
    check(model.collision_detected(),
          "collision_immediate", passed);
    model.step();
    check(model.collision_detected(),
          "collision_after_step", passed);
    check(cell_matches(model, 0, 0, 2, 1, true, 0x66),
          "collision_lowest_producer_wins", passed);

    // Upstream plus local inject is also a same-cell producer collision.
    model.reset();
    check(model.inject_cell(0, 0, 0, 2, 1, 0x80),
          "upstream_collision_seed", passed);
    model.step();
    check(model.inject_cell(0, 1, 0, 2, 1, 0x81),
          "upstream_collision_local", passed);
    model.step();
    check(model.collision_detected(),
          "upstream_inject_collision", passed);
    check(cell_matches(model, 1, 0, 2, 1, true, 0x81),
          "upstream_collision_inject_wins", passed);

    HemisphereModel hemisphere;

    std::cout << "RUN_TEST hemisphere_east_only\n";
    check(hemisphere.inject_cell(Direction::EAST,
                                 0, 0, 0, 0, 0, 0x51),
          "hemisphere_east_only_inject", passed);
    for (std::size_t cycle = 0; cycle < SRFModel::COLUMN_NUM; ++cycle) {
        hemisphere.step();
    }
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::EAST,
                                  3, 0, 0, 0, true, 0x51),
          "hemisphere_east_only_output", passed);
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::WEST,
                                  0, 0, 0, 0, false, 0),
          "hemisphere_east_only_west_idle", passed);

    std::cout << "RUN_TEST hemisphere_west_only\n";
    hemisphere.reset();
    check(hemisphere.inject_cell(Direction::WEST,
                                 1, 3, 1, 3, 3, 0xa5),
          "hemisphere_west_only_inject", passed);
    for (std::size_t cycle = 0; cycle < SRFModel::COLUMN_NUM; ++cycle) {
        hemisphere.step();
    }
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::WEST,
                                  0, 1, 3, 3, true, 0xa5),
          "hemisphere_west_only_output", passed);
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::EAST,
                                  3, 1, 3, 3, false, 0),
          "hemisphere_west_only_east_idle", passed);

    std::cout << "RUN_TEST hemisphere_simultaneous\n";
    hemisphere.reset();
    check(hemisphere.inject_cell(Direction::EAST,
                                 0, 0, 0, 1, 0, 0x55),
          "hemisphere_simultaneous_east", passed);
    check(hemisphere.inject_cell(Direction::WEST,
                                 0, 3, 1, 2, 3, 0xaa),
          "hemisphere_simultaneous_west", passed);
    for (std::size_t cycle = 0; cycle < SRFModel::COLUMN_NUM; ++cycle) {
        hemisphere.step();
    }
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::EAST,
                                  3, 0, 1, 0, true, 0x55),
          "hemisphere_simultaneous_east_output", passed);
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::WEST,
                                  0, 1, 2, 3, true, 0xaa),
          "hemisphere_simultaneous_west_output", passed);

    std::cout << "RUN_TEST hemisphere_same_stream_independence\n";
    hemisphere.reset();
    check(hemisphere.inject_cell(Direction::EAST,
                                 0, 0, 0, 1, 2, 0x12),
          "hemisphere_same_stream_east", passed);
    check(hemisphere.inject_cell(Direction::WEST,
                                 0, 3, 0, 1, 2, 0x34),
          "hemisphere_same_stream_west", passed);
    hemisphere.step();
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::EAST,
                                  0, 0, 1, 2, true, 0x12),
          "hemisphere_same_stream_east_state", passed);
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::WEST,
                                  3, 0, 1, 2, true, 0x34),
          "hemisphere_same_stream_west_state", passed);

    std::cout << "RUN_TEST hemisphere_independent_consume\n";
    check(hemisphere.consume_cell(Direction::EAST,
                                  0, 0, 0, 1, 2),
          "hemisphere_consume_east", passed);
    hemisphere.step();
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::EAST,
                                  1, 0, 1, 2, false, 0),
          "hemisphere_consume_blocks_east", passed);
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::WEST,
                                  2, 0, 1, 2, true, 0x34),
          "hemisphere_consume_preserves_west", passed);

    std::cout << "RUN_TEST hemisphere_independent_inject\n";
    hemisphere.reset();
    check(hemisphere.inject_cell(Direction::EAST,
                                 0, 1, 1, 2, 0, 0xe2),
          "hemisphere_independent_inject_east", passed);
    check(hemisphere.inject_cell(Direction::WEST,
                                 1, 2, 1, 2, 0, 0xf2),
          "hemisphere_independent_inject_west", passed);
    hemisphere.step();
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::EAST,
                                  1, 1, 2, 0, true, 0xe2),
          "hemisphere_independent_inject_east_state", passed);
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::WEST,
                                  2, 1, 2, 0, true, 0xf2),
          "hemisphere_independent_inject_west_state", passed);

    std::cout << "RUN_TEST hemisphere_independent_collision\n";
    hemisphere.reset();
    check(hemisphere.inject_cell(Direction::EAST,
                                 0, 0, 0, 3, 1, 0xc0),
          "hemisphere_collision_east_p0", passed);
    check(hemisphere.inject_cell(Direction::EAST,
                                 1, 0, 0, 3, 1, 0xc1),
          "hemisphere_collision_east_p1", passed);
    check(hemisphere.collision_detected(Direction::EAST),
          "hemisphere_collision_east_asserted", passed);
    check(!hemisphere.collision_detected(Direction::WEST),
          "hemisphere_collision_west_clear", passed);
    hemisphere.step();
    check(hemisphere.collision_detected(Direction::EAST) &&
              !hemisphere.collision_detected(Direction::WEST),
          "hemisphere_collision_east_after_step", passed);

    hemisphere.reset();
    check(hemisphere.inject_cell(Direction::WEST,
                                 0, 3, 0, 3, 1, 0xd0),
          "hemisphere_collision_west_p0", passed);
    check(hemisphere.inject_cell(Direction::WEST,
                                 1, 3, 0, 3, 1, 0xd1),
          "hemisphere_collision_west_p1", passed);
    hemisphere.step();
    check(!hemisphere.collision_detected(Direction::EAST) &&
              hemisphere.collision_detected(Direction::WEST),
          "hemisphere_collision_west_after_step", passed);

    std::cout << "RUN_TEST hemisphere_invalid_consume_independence\n";
    hemisphere.reset();
    check(hemisphere.consume_cell(Direction::EAST,
                                  0, 0, 0, 0, 1),
          "hemisphere_invalid_consume_east", passed);
    check(hemisphere.invalid_consume_detected(Direction::EAST),
          "hemisphere_invalid_consume_east_asserted", passed);
    check(!hemisphere.invalid_consume_detected(Direction::WEST),
          "hemisphere_invalid_consume_west_clear", passed);
    hemisphere.step();
    check(hemisphere.invalid_consume_detected(Direction::EAST) &&
              !hemisphere.invalid_consume_detected(Direction::WEST),
          "hemisphere_invalid_consume_east_after_step", passed);

    hemisphere.reset();
    check(hemisphere.consume_cell(Direction::WEST,
                                  1, 3, 0, 0, 1),
          "hemisphere_invalid_consume_west", passed);
    hemisphere.step();
    check(!hemisphere.invalid_consume_detected(Direction::EAST) &&
              hemisphere.invalid_consume_detected(Direction::WEST),
          "hemisphere_invalid_consume_west_after_step", passed);

    std::cout << "RUN_TEST hemisphere_equal_latency\n";
    hemisphere.reset();
    check(hemisphere.inject_cell(Direction::EAST,
                                 0, 0, 0, 0, 3, 0xe8),
          "hemisphere_latency_east", passed);
    check(hemisphere.inject_cell(Direction::WEST,
                                 0, 3, 0, 0, 3, 0xf8),
          "hemisphere_latency_west", passed);
    for (std::size_t cycle = 1; cycle < SRFModel::COLUMN_NUM; ++cycle) {
        hemisphere.step();
        check(hemisphere_cell_matches(hemisphere,
                                      Direction::EAST,
                                      3, 0, 0, 3, false, 0),
              "hemisphere_latency_east_not_early", passed);
        check(hemisphere_cell_matches(hemisphere,
                                      Direction::WEST,
                                      0, 0, 0, 3, false, 0),
              "hemisphere_latency_west_not_early", passed);
    }
    hemisphere.step();
    check(hemisphere.cycle() == SRFModel::COLUMN_NUM,
          "hemisphere_latency_cycle_count", passed);
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::EAST,
                                  3, 0, 0, 3, true, 0xe8),
          "hemisphere_latency_east_output", passed);
    check(hemisphere_cell_matches(hemisphere,
                                  Direction::WEST,
                                  0, 0, 0, 3, true, 0xf8),
          "hemisphere_latency_west_output", passed);

    std::cout << "RUN_TEST hemisphere_direction_dump\n";
    hemisphere.reset();
    check(hemisphere.inject_cell(Direction::EAST,
                                 0, 0, 0, 1, 3, 0x55),
          "hemisphere_dump_east", passed);
    check(hemisphere.inject_cell(Direction::WEST,
                                 0, 3, 0, 1, 3, 0xaa),
          "hemisphere_dump_west", passed);
    hemisphere.step();
    hemisphere.step();
    hemisphere.step();
    const std::string hemisphere_dump = hemisphere.dump_state();
    const std::size_t east_direction_pos =
        hemisphere_dump.find("direction=EAST\n");
    const std::size_t east_cell_pos = hemisphere_dump.find(
        "column=2 superlane=0 stream=1 lane=3 data=0x55 valid=1");
    const std::size_t west_direction_pos =
        hemisphere_dump.find("direction=WEST\n");
    const std::size_t west_cell_pos = hemisphere_dump.find(
        "column=1 superlane=0 stream=1 lane=3 data=0xaa valid=1");
    check(hemisphere_dump.find("cycle=3\n") == 0,
          "hemisphere_dump_cycle", passed);
    check(east_direction_pos < east_cell_pos &&
              east_cell_pos < west_direction_pos &&
              west_direction_pos < west_cell_pos,
          "hemisphere_dump_direction_order", passed);

    FullChipModel full_chip;

    std::cout << "RUN_TEST full_chip_four_path_propagation\n";
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::EAST,
                                0, 0, 0, 1, 2, 0xa1),
          "full_chip_west_hemi_east_inject", passed);
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::WEST,
                                0, 15, 1, 2, 3, 0xb2),
          "full_chip_west_hemi_west_inject", passed);
    check(full_chip.inject_cell(Hemisphere::EAST, Direction::EAST,
                                0, 0, 2, 3, 4, 0xc3),
          "full_chip_east_hemi_east_inject", passed);
    check(full_chip.inject_cell(Hemisphere::EAST, Direction::WEST,
                                0, 15, 3, 4, 5, 0xd4),
          "full_chip_east_hemi_west_inject", passed);
    for (std::size_t cycle = 0; cycle < FullChipModel::COLUMN_NUM; ++cycle) {
        full_chip.step();
    }
    check(full_chip_cell_matches(full_chip, Hemisphere::WEST, Direction::EAST,
                                 15, 0, 1, 2, true, 0xa1),
          "full_chip_west_hemi_east_output", passed);
    check(full_chip_cell_matches(full_chip, Hemisphere::WEST, Direction::WEST,
                                 0, 1, 2, 3, true, 0xb2),
          "full_chip_west_hemi_west_output", passed);
    check(full_chip_cell_matches(full_chip, Hemisphere::EAST, Direction::EAST,
                                 15, 2, 3, 4, true, 0xc3),
          "full_chip_east_hemi_east_output", passed);
    check(full_chip_cell_matches(full_chip, Hemisphere::EAST, Direction::WEST,
                                 0, 3, 4, 5, true, 0xd4),
          "full_chip_east_hemi_west_output", passed);

    std::cout << "RUN_TEST full_chip_hemisphere_independence\n";
    full_chip.reset();
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::EAST,
                                0, 0, 1, 7, 2, 0x51),
          "full_chip_hemisphere_west", passed);
    check(full_chip.inject_cell(Hemisphere::EAST, Direction::EAST,
                                0, 0, 1, 7, 2, 0x52),
          "full_chip_hemisphere_east", passed);
    full_chip.step();
    check(full_chip_cell_matches(full_chip, Hemisphere::WEST, Direction::EAST,
                                 0, 1, 7, 2, true, 0x51),
          "full_chip_hemisphere_west_state", passed);
    check(full_chip_cell_matches(full_chip, Hemisphere::EAST, Direction::EAST,
                                 0, 1, 7, 2, true, 0x52),
          "full_chip_hemisphere_east_state", passed);

    std::cout << "RUN_TEST full_chip_direction_independence\n";
    full_chip.reset();
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::EAST,
                                0, 6, 2, 8, 3, 0x61),
          "full_chip_direction_east", passed);
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::WEST,
                                0, 6, 2, 8, 3, 0x62),
          "full_chip_direction_west", passed);
    full_chip.step();
    check(full_chip_cell_matches(full_chip, Hemisphere::WEST, Direction::EAST,
                                 6, 2, 8, 3, true, 0x61),
          "full_chip_direction_east_state", passed);
    check(full_chip_cell_matches(full_chip, Hemisphere::WEST, Direction::WEST,
                                 6, 2, 8, 3, true, 0x62),
          "full_chip_direction_west_state", passed);

    std::cout << "RUN_TEST full_chip_same_coordinate_state\n";
    full_chip.reset();
    const Hemisphere full_chip_hemispheres[4] = {
        Hemisphere::WEST, Hemisphere::WEST,
        Hemisphere::EAST, Hemisphere::EAST};
    const Direction full_chip_directions[4] = {
        Direction::EAST, Direction::WEST,
        Direction::EAST, Direction::WEST};
    const std::uint8_t full_chip_values[4] = {0x11, 0x22, 0x33, 0x44};
    for (std::size_t path = 0; path < 4; ++path) {
        check(full_chip.inject_cell(full_chip_hemispheres[path],
                                    full_chip_directions[path],
                                    0, 5, 3, 9, 6,
                                    full_chip_values[path]),
              "full_chip_same_coordinate_inject", passed);
    }
    full_chip.step();
    for (std::size_t path = 0; path < 4; ++path) {
        check(full_chip_cell_matches(full_chip,
                                     full_chip_hemispheres[path],
                                     full_chip_directions[path],
                                     5, 3, 9, 6, true,
                                     full_chip_values[path]),
              "full_chip_same_coordinate_read", passed);
    }

    std::cout << "RUN_TEST full_chip_consume_independence\n";
    full_chip.reset();
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::EAST,
                                0, 0, 0, 10, 1, 0x71),
          "full_chip_consume_west_seed", passed);
    check(full_chip.inject_cell(Hemisphere::EAST, Direction::EAST,
                                0, 0, 0, 10, 1, 0x72),
          "full_chip_consume_east_seed", passed);
    full_chip.step();
    check(full_chip.consume_cell(Hemisphere::WEST, Direction::EAST,
                                 0, 0, 0, 10, 1),
          "full_chip_consume_west", passed);
    full_chip.step();
    check(full_chip_cell_matches(full_chip, Hemisphere::WEST, Direction::EAST,
                                 1, 0, 10, 1, false, 0),
          "full_chip_consume_blocks_west", passed);
    check(full_chip_cell_matches(full_chip, Hemisphere::EAST, Direction::EAST,
                                 1, 0, 10, 1, true, 0x72),
          "full_chip_consume_preserves_east", passed);

    std::cout << "RUN_TEST full_chip_inject_independence\n";
    full_chip.reset();
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::WEST,
                                0, 15, 2, 11, 4, 0x81),
          "full_chip_inject_west", passed);
    check(full_chip.inject_cell(Hemisphere::EAST, Direction::WEST,
                                1, 15, 2, 11, 4, 0x82),
          "full_chip_inject_east", passed);
    full_chip.step();
    check(full_chip_cell_matches(full_chip, Hemisphere::WEST, Direction::WEST,
                                 15, 2, 11, 4, true, 0x81),
          "full_chip_inject_west_state", passed);
    check(full_chip_cell_matches(full_chip, Hemisphere::EAST, Direction::WEST,
                                 15, 2, 11, 4, true, 0x82),
          "full_chip_inject_east_state", passed);

    std::cout << "RUN_TEST full_chip_error_independence\n";
    full_chip.reset();
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::EAST,
                                0, 0, 0, 12, 5, 0x90),
          "full_chip_error_collision_p0", passed);
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::EAST,
                                1, 0, 0, 12, 5, 0x91),
          "full_chip_error_collision_p1", passed);
    check(full_chip.collision_detected(Hemisphere::WEST, Direction::EAST),
          "full_chip_error_collision_asserted", passed);
    check(!full_chip.collision_detected(Hemisphere::EAST, Direction::EAST),
          "full_chip_error_collision_isolated", passed);
    full_chip.reset();
    check(full_chip.consume_cell(Hemisphere::EAST, Direction::WEST,
                                 0, 15, 0, 13, 6),
          "full_chip_error_invalid_consume", passed);
    check(full_chip.invalid_consume_detected(Hemisphere::EAST,
                                             Direction::WEST),
          "full_chip_error_invalid_asserted", passed);
    check(!full_chip.invalid_consume_detected(Hemisphere::WEST,
                                              Direction::WEST),
          "full_chip_error_invalid_isolated", passed);

    std::cout << "RUN_TEST full_chip_common_step\n";
    full_chip.reset();
    for (std::size_t path = 0; path < 4; ++path) {
        const std::uint8_t entry_column =
            full_chip_directions[path] == Direction::EAST ? 0 : 15;
        check(full_chip.inject_cell(full_chip_hemispheres[path],
                                    full_chip_directions[path],
                                    0, entry_column, 0, 14, 7,
                                    static_cast<std::uint8_t>(0xa0 + path)),
              "full_chip_common_step_inject", passed);
    }
    full_chip.step();
    check(full_chip.cycle() == 1, "full_chip_common_cycle", passed);
    for (std::size_t path = 0; path < 4; ++path) {
        const std::uint8_t entry_column =
            full_chip_directions[path] == Direction::EAST ? 0 : 15;
        check(full_chip_cell_matches(full_chip,
                                     full_chip_hemispheres[path],
                                     full_chip_directions[path],
                                     entry_column, 0, 14, 7, true,
                                     static_cast<std::uint8_t>(0xa0 + path)),
              "full_chip_common_step_state", passed);
    }

    std::cout << "RUN_TEST full_chip_dump_state\n";
    full_chip.reset();
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::EAST,
                                0, 3, 1, 7, 2, 0x55),
          "full_chip_dump_west", passed);
    check(full_chip.inject_cell(Hemisphere::EAST, Direction::WEST,
                                0, 3, 1, 7, 2, 0xaa),
          "full_chip_dump_east", passed);
    full_chip.step();
    const std::string full_chip_dump = full_chip.dump_state();
    const std::size_t dump_west_hemi =
        full_chip_dump.find("hemisphere=WEST\n");
    const std::size_t dump_west_direction =
        full_chip_dump.find("direction=EAST\n", dump_west_hemi);
    const std::size_t dump_west_cell = full_chip_dump.find(
        "column=3 superlane=1 stream=7 lane=2 data=0x55 valid=1",
        dump_west_direction);
    const std::size_t dump_east_hemi =
        full_chip_dump.find("hemisphere=EAST\n");
    const std::size_t dump_east_direction =
        full_chip_dump.find("direction=WEST\n", dump_east_hemi);
    const std::size_t dump_east_cell = full_chip_dump.find(
        "column=3 superlane=1 stream=7 lane=2 data=0xaa valid=1",
        dump_east_direction);
    check(full_chip_dump.find("cycle=1\n") == 0,
          "full_chip_dump_cycle", passed);
    check(dump_west_hemi < dump_west_direction &&
              dump_west_direction < dump_west_cell &&
              dump_west_cell < dump_east_hemi &&
              dump_east_hemi < dump_east_direction &&
              dump_east_direction < dump_east_cell,
          "full_chip_dump_coordinates", passed);

    std::cout << "RUN_TEST full_chip_default_16_column_latency\n";
    full_chip.reset();
    check(full_chip.inject_cell(Hemisphere::WEST, Direction::EAST,
                                0, 0, 0, 15, 0, 0xe1),
          "full_chip_default_latency_east", passed);
    check(full_chip.inject_cell(Hemisphere::EAST, Direction::WEST,
                                0, 15, 0, 15, 0, 0xf1),
          "full_chip_default_latency_west", passed);
    for (std::size_t cycle = 1; cycle < FullChipModel::COLUMN_NUM; ++cycle) {
        full_chip.step();
        check(full_chip_cell_matches(full_chip,
                                     Hemisphere::WEST, Direction::EAST,
                                     15, 0, 15, 0, false, 0),
              "full_chip_default_latency_east_not_early", passed);
        check(full_chip_cell_matches(full_chip,
                                     Hemisphere::EAST, Direction::WEST,
                                     0, 0, 15, 0, false, 0),
              "full_chip_default_latency_west_not_early", passed);
    }
    full_chip.step();
    check(full_chip.cycle() == FullChipModel::COLUMN_NUM,
          "full_chip_default_latency_cycle_count", passed);
    check(full_chip_cell_matches(full_chip,
                                 Hemisphere::WEST, Direction::EAST,
                                 15, 0, 15, 0, true, 0xe1),
          "full_chip_default_latency_east_output", passed);
    check(full_chip_cell_matches(full_chip,
                                 Hemisphere::EAST, Direction::WEST,
                                 0, 0, 15, 0, true, 0xf1),
          "full_chip_default_latency_west_output", passed);

    std::cout << "RUN_TEST cmodel_hop_formula\n";
    const std::size_t hop_sources[8] = {0, 0, 0, 3, 15, 15, 15, 12};
    const std::size_t hop_destinations[8] = {1, 5, 15, 10, 14, 8, 0, 4};
    const std::uint64_t hop_expected_cycles[8] = {2, 6, 16, 8, 2, 8, 16, 9};
    for (std::size_t hop_case = 0; hop_case < 8; ++hop_case) {
        check(FullChipModel::expected_arrival_cycle(
                  1, hop_sources[hop_case], hop_destinations[hop_case]) ==
                  hop_expected_cycles[hop_case],
              "cmodel_hop_formula_case", passed);
    }

    std::cout << "RUN_TEST cmodel_snapshot_and_trace\n";
    FullChipModel trace_model;
    std::ofstream trace_file("sim/trace/cmodel_srf_trace.csv");
    if (!trace_file.is_open()) {
        trace_file.clear();
        trace_file.open("../sim/trace/cmodel_srf_trace.csv");
    }
    check(trace_file.is_open(), "cmodel_trace_open", passed);
    if (trace_file.is_open()) {
        trace_file << "cycle,hemisphere,direction,column,superlane,stream,lane,valid,data\n";
        for (std::size_t trace_cycle = 0;
             trace_cycle <= FullChipModel::COLUMN_NUM; ++trace_cycle) {
            const std::vector<CellSnapshot> cells = trace_model.snapshot(
                Hemisphere::WEST, Direction::EAST);
            for (const CellSnapshot& cell : cells) {
                if (cell.superlane == 0 && cell.stream == 0 && cell.lane == 0) {
                    trace_file << cell.cycle << ",0,0," << cell.column
                               << ",0,0,0," << (cell.valid ? 1 : 0) << ','
                               << static_cast<unsigned>(cell.data) << '\n';
                }
            }
            if (trace_cycle == FullChipModel::COLUMN_NUM)
                break;
            if (trace_cycle == 0) {
                check(trace_model.inject_cell(
                          Hemisphere::WEST, Direction::EAST,
                          0, 0, 0, 0, 0, 0x5a),
                      "cmodel_trace_inject", passed);
            }
            trace_model.step();
        }
        trace_file.close();
    }
    check(full_chip_cell_matches(trace_model,
                                 Hemisphere::WEST, Direction::EAST,
                                 15, 0, 0, 0, true, 0x5a),
          "cmodel_trace_final_cell", passed);

    if (passed) {
        std::cout << "TEST_PASS\n";
        return 0;
    }

    std::cout << "TEST_FAIL\n";
    return 1;
}
