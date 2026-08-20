#include "srf_model.h"

#include <algorithm>
#include <iomanip>
#include <sstream>

Command Command::decode(std::uint64_t raw_command) {
    Command command{};
    command.opcode = static_cast<std::uint8_t>((raw_command >> 56) & 0xffU);
    command.column = static_cast<std::uint8_t>((raw_command >> 48) & 0xffU);
    command.superlane = static_cast<std::uint8_t>((raw_command >> 40) & 0xffU);
    command.stream = static_cast<std::uint8_t>((raw_command >> 32) & 0xffU);
    command.lane = static_cast<std::uint8_t>((raw_command >> 24) & 0xffU);
    command.data = static_cast<std::uint8_t>((raw_command >> 16) & 0xffU);
    return command;
}

SRFModel::SRFModel(std::size_t column_num,
                   std::size_t superlane_num,
                   std::size_t stream_num,
                   std::size_t lane_num,
                   std::size_t local_producers,
                   std::size_t local_consumers)
    : column_num_(column_num),
      superlane_num_(superlane_num),
      stream_num_(stream_num),
      lane_num_(lane_num),
      local_producers_(local_producers),
      local_consumers_(local_consumers),
      cell_count_(column_num * superlane_num * stream_num * lane_num),
      pipeline_data_(cell_count_, std::uint8_t{0}),
      pipeline_valid_(cell_count_, false),
      inject_pending_(cell_count_ * local_producers, false),
      inject_data_(cell_count_ * local_producers, std::uint8_t{0}),
      consume_pending_(cell_count_ * local_consumers, false),
      access_pending_(cell_count_, false),
      access_data_(cell_count_, std::uint8_t{0}),
      direction_(Direction::EAST),
      cycle_(0),
      pending_cycle_started_(false),
      collision_(false),
      invalid_consume_(false) {
    reset();
}

std::size_t SRFModel::cell_index(std::size_t column,
                                 std::size_t superlane,
                                 std::size_t stream,
                                 std::size_t lane) const {
    return ((column * superlane_num_ + superlane) * stream_num_ + stream) *
               lane_num_ +
           lane;
}

void SRFModel::clear_pending_events() {
    std::fill(inject_pending_.begin(), inject_pending_.end(), false);
    std::fill(inject_data_.begin(), inject_data_.end(), std::uint8_t{0});
    std::fill(consume_pending_.begin(), consume_pending_.end(), false);
    std::fill(access_pending_.begin(), access_pending_.end(), false);
    std::fill(access_data_.begin(), access_data_.end(), std::uint8_t{0});
    pending_cycle_started_ = false;
}

void SRFModel::begin_pending_cycle() {
    if (!pending_cycle_started_) {
        collision_ = false;
        invalid_consume_ = false;
        pending_cycle_started_ = true;
    }
}

void SRFModel::reset() {
    std::fill(pipeline_data_.begin(), pipeline_data_.end(), std::uint8_t{0});
    std::fill(pipeline_valid_.begin(), pipeline_valid_.end(), false);
    direction_ = Direction::EAST;
    cycle_ = 0;
    collision_ = false;
    invalid_consume_ = false;
    clear_pending_events();
}

void SRFModel::set_direction(Direction direction) {
    direction_ = direction;
}

bool SRFModel::consume_any(std::size_t cell) const {
    const std::size_t base = cell * local_consumers_;
    for (std::size_t consumer = 0; consumer < local_consumers_; ++consumer) {
        if (consume_pending_[base + consumer]) {
            return true;
        }
    }
    return false;
}

void SRFModel::step() {
    std::vector<std::uint8_t> next_data(cell_count_, std::uint8_t{0});
    std::vector<bool> next_valid(cell_count_, false);
    bool step_collision = false;
    bool step_invalid_consume = false;

    for (std::size_t column = 0; column < column_num_; ++column) {
        for (std::size_t superlane = 0; superlane < superlane_num_; ++superlane) {
            for (std::size_t stream = 0; stream < stream_num_; ++stream) {
                for (std::size_t lane = 0; lane < lane_num_; ++lane) {
                    const std::size_t target =
                        cell_index(column, superlane, stream, lane);
                    bool upstream_valid = false;
                    std::uint8_t upstream_data = 0;

                    if (direction_ == Direction::EAST && column > 0) {
                        const std::size_t source =
                            cell_index(column - 1, superlane, stream, lane);
                        upstream_data = pipeline_data_[source];
                        upstream_valid =
                            pipeline_valid_[source] && !consume_any(source);
                    } else if (direction_ == Direction::WEST &&
                               column + 1 < column_num_) {
                        const std::size_t source =
                            cell_index(column + 1, superlane, stream, lane);
                        upstream_data = pipeline_data_[source];
                        upstream_valid =
                            pipeline_valid_[source] && !consume_any(source);
                    }

                    next_data[target] = upstream_data;
                    next_valid[target] = upstream_valid;
                    std::size_t candidate_count = upstream_valid ? 1U : 0U;
                    bool inject_selected = false;
                    const std::size_t inject_base = target * local_producers_;

                    for (std::size_t producer = 0;
                         producer < local_producers_;
                         ++producer) {
                        if (inject_pending_[inject_base + producer]) {
                            ++candidate_count;
                            if (!inject_selected) {
                                next_data[target] =
                                    inject_data_[inject_base + producer];
                                next_valid[target] = true;
                                inject_selected = true;
                            }
                        }
                    }

                    if (access_pending_[target]) {
                        ++candidate_count;
                        if (!inject_selected) {
                            next_data[target] = access_data_[target];
                            next_valid[target] = true;
                        }
                    }
                    if (candidate_count >= 2U) {
                        step_collision = true;
                    }

                    const std::size_t consume_base = target * local_consumers_;
                    for (std::size_t consumer = 0;
                         consumer < local_consumers_;
                         ++consumer) {
                        if (consume_pending_[consume_base + consumer] &&
                            !pipeline_valid_[target]) {
                            step_invalid_consume = true;
                        }
                    }
                }
            }
        }
    }

    pipeline_data_.swap(next_data);
    pipeline_valid_.swap(next_valid);
    ++cycle_;
    collision_ = step_collision;
    invalid_consume_ = step_invalid_consume;
    clear_pending_events();
}

bool SRFModel::address_valid(std::uint8_t column,
                             std::uint8_t superlane,
                             std::uint8_t stream,
                             std::uint8_t lane) const {
    return column < column_num_ && superlane < superlane_num_ &&
           stream < stream_num_ && lane < lane_num_;
}

bool SRFModel::inject_cell(std::uint8_t producer,
                           std::uint8_t column,
                           std::uint8_t superlane,
                           std::uint8_t stream,
                           std::uint8_t lane,
                           std::uint8_t data) {
    if (producer >= local_producers_ ||
        !address_valid(column, superlane, stream, lane)) {
        return false;
    }
    begin_pending_cycle();
    const std::size_t cell = cell_index(column, superlane, stream, lane);
    const std::size_t base = cell * local_producers_;
    bool other_candidate = access_pending_[cell];
    for (std::size_t other = 0; other < local_producers_; ++other) {
        if (other != producer && inject_pending_[base + other]) {
            other_candidate = true;
        }
    }
    collision_ |= other_candidate;
    inject_pending_[base + producer] = true;
    inject_data_[base + producer] = data;
    return true;
}

bool SRFModel::consume_cell(std::uint8_t consumer,
                            std::uint8_t column,
                            std::uint8_t superlane,
                            std::uint8_t stream,
                            std::uint8_t lane) {
    if (consumer >= local_consumers_ ||
        !address_valid(column, superlane, stream, lane)) {
        return false;
    }
    begin_pending_cycle();
    const std::size_t cell = cell_index(column, superlane, stream, lane);
    consume_pending_[cell * local_consumers_ + consumer] = true;
    if (!pipeline_valid_[cell]) {
        invalid_consume_ = true;
    }
    return true;
}

bool SRFModel::write_cell(std::uint8_t column,
                          std::uint8_t superlane,
                          std::uint8_t stream,
                          std::uint8_t lane,
                          std::uint8_t data) {
    if (!address_valid(column, superlane, stream, lane)) {
        return false;
    }
    begin_pending_cycle();
    const std::size_t cell = cell_index(column, superlane, stream, lane);
    const std::size_t base = cell * local_producers_;
    bool inject_seen = false;
    for (std::size_t producer = 0; producer < local_producers_; ++producer) {
        inject_seen |= inject_pending_[base + producer];
    }
    collision_ |= inject_seen;
    access_pending_[cell] = true;
    access_data_[cell] = data;
    return true;
}

CommandResult SRFModel::read_cell(std::uint8_t column,
                                  std::uint8_t superlane,
                                  std::uint8_t stream,
                                  std::uint8_t lane) const {
    if (!address_valid(column, superlane, stream, lane)) {
        return {false, false, 0};
    }
    const std::size_t cell = cell_index(column, superlane, stream, lane);
    return {true, pipeline_valid_[cell], pipeline_data_[cell]};
}

CommandResult SRFModel::execute(Command command) {
    switch (command.opcode) {
    case OPCODE_WRITE:
        if (!write_cell(command.column, command.superlane, command.stream,
                        command.lane, command.data)) {
            return {false, false, 0};
        }
        return {true, true, command.data};
    case OPCODE_READ:
        return read_cell(command.column, command.superlane, command.stream,
                         command.lane);
    default:
        return {true, false, 0};
    }
}

bool SRFModel::collision_detected() const { return collision_; }
bool SRFModel::invalid_consume_detected() const { return invalid_consume_; }
std::uint64_t SRFModel::cycle() const { return cycle_; }
std::size_t SRFModel::column_num() const { return column_num_; }
std::size_t SRFModel::superlane_num() const { return superlane_num_; }
std::size_t SRFModel::stream_num() const { return stream_num_; }
std::size_t SRFModel::lane_num() const { return lane_num_; }

std::uint64_t SRFModel::expected_arrival_cycle(
    std::uint64_t source_visible_cycle,
    std::size_t source_column,
    std::size_t destination_column,
    std::size_t hop_cycles) {
    const std::size_t distance = source_column > destination_column
        ? source_column - destination_column
        : destination_column - source_column;
    return source_visible_cycle + distance * hop_cycles;
}

std::vector<CellSnapshot> SRFModel::snapshot() const {
    std::vector<CellSnapshot> result;
    result.reserve(cell_count_);
    for (std::size_t column = 0; column < column_num_; ++column) {
        for (std::size_t superlane = 0; superlane < superlane_num_; ++superlane) {
            for (std::size_t stream = 0; stream < stream_num_; ++stream) {
                for (std::size_t lane = 0; lane < lane_num_; ++lane) {
                    const std::size_t index =
                        cell_index(column, superlane, stream, lane);
                    result.push_back({cycle_, column, superlane, stream, lane,
                                      pipeline_valid_[index],
                                      pipeline_valid_[index]
                                          ? pipeline_data_[index]
                                          : static_cast<std::uint8_t>(0)});
                }
            }
        }
    }
    return result;
}

std::string SRFModel::dump_state() const {
    std::ostringstream output;
    output << "cycle=" << cycle_ << '\n';
    for (std::size_t column = 0; column < column_num_; ++column) {
        for (std::size_t superlane = 0; superlane < superlane_num_; ++superlane) {
            for (std::size_t stream = 0; stream < stream_num_; ++stream) {
                for (std::size_t lane = 0; lane < lane_num_; ++lane) {
                    const std::size_t cell =
                        cell_index(column, superlane, stream, lane);
                    output << "column=" << column
                           << " superlane=" << superlane
                           << " stream=" << stream
                           << " lane=" << lane
                           << " data=0x" << std::hex << std::setw(2)
                           << std::setfill('0')
                           << static_cast<unsigned>(pipeline_data_[cell])
                           << std::dec << std::setfill(' ')
                           << " valid=" << (pipeline_valid_[cell] ? 1 : 0)
                           << '\n';
                }
            }
        }
    }
    return output.str();
}

HemisphereModel::HemisphereModel(std::size_t column_num,
                                 std::size_t superlane_num,
                                 std::size_t stream_num,
                                 std::size_t lane_num,
                                 std::size_t local_producers,
                                 std::size_t local_consumers)
    : east_(column_num, superlane_num, stream_num, lane_num,
            local_producers, local_consumers),
      west_(column_num, superlane_num, stream_num, lane_num,
            local_producers, local_consumers),
      cycle_(0) {
    reset();
}

void HemisphereModel::reset() {
    east_.reset();
    west_.reset();
    east_.set_direction(Direction::EAST);
    west_.set_direction(Direction::WEST);
    cycle_ = 0;
}

void HemisphereModel::step() {
    east_.step();
    west_.step();
    ++cycle_;
}

std::uint64_t HemisphereModel::cycle() const { return cycle_; }
std::size_t HemisphereModel::column_num() const { return east_.column_num(); }
std::size_t HemisphereModel::superlane_num() const { return east_.superlane_num(); }
std::size_t HemisphereModel::stream_num() const { return east_.stream_num(); }
std::size_t HemisphereModel::lane_num() const { return east_.lane_num(); }

SRFModel& HemisphereModel::model(Direction direction) {
    return direction == Direction::EAST ? east_ : west_;
}
const SRFModel& HemisphereModel::model(Direction direction) const {
    return direction == Direction::EAST ? east_ : west_;
}

bool HemisphereModel::inject_cell(Direction direction, std::uint8_t producer,
                                  std::uint8_t column, std::uint8_t superlane,
                                  std::uint8_t stream, std::uint8_t lane,
                                  std::uint8_t data) {
    return model(direction).inject_cell(producer, column, superlane, stream,
                                        lane, data);
}
bool HemisphereModel::consume_cell(Direction direction, std::uint8_t consumer,
                                   std::uint8_t column, std::uint8_t superlane,
                                   std::uint8_t stream, std::uint8_t lane) {
    return model(direction).consume_cell(consumer, column, superlane, stream,
                                         lane);
}
bool HemisphereModel::write_cell(Direction direction, std::uint8_t column,
                                 std::uint8_t superlane, std::uint8_t stream,
                                 std::uint8_t lane, std::uint8_t data) {
    return model(direction).write_cell(column, superlane, stream, lane, data);
}
CommandResult HemisphereModel::read_cell(Direction direction,
                                         std::uint8_t column,
                                         std::uint8_t superlane,
                                         std::uint8_t stream,
                                         std::uint8_t lane) const {
    return model(direction).read_cell(column, superlane, stream, lane);
}
bool HemisphereModel::collision_detected(Direction direction) const {
    return model(direction).collision_detected();
}
bool HemisphereModel::invalid_consume_detected(Direction direction) const {
    return model(direction).invalid_consume_detected();
}
bool HemisphereModel::hemisphere_collision_detected() const {
    return east_.collision_detected() || west_.collision_detected();
}
bool HemisphereModel::hemisphere_invalid_consume_detected() const {
    return east_.invalid_consume_detected() || west_.invalid_consume_detected();
}

std::vector<CellSnapshot> HemisphereModel::snapshot(
    Direction direction) const {
    return model(direction).snapshot();
}

std::string HemisphereModel::dump_state() const {
    std::ostringstream output;
    output << "cycle=" << cycle_ << '\n';
    const Direction directions[2] = {Direction::EAST, Direction::WEST};
    const char* names[2] = {"EAST", "WEST"};
    for (std::size_t direction_index = 0; direction_index < 2;
         ++direction_index) {
        output << "direction=" << names[direction_index] << '\n';
        for (std::size_t column = 0; column < column_num(); ++column) {
            for (std::size_t superlane = 0;
                 superlane < superlane_num(); ++superlane) {
                for (std::size_t stream = 0; stream < stream_num(); ++stream) {
                    for (std::size_t lane = 0; lane < lane_num(); ++lane) {
                        const CommandResult cell = read_cell(
                            directions[direction_index],
                            static_cast<std::uint8_t>(column),
                            static_cast<std::uint8_t>(superlane),
                            static_cast<std::uint8_t>(stream),
                            static_cast<std::uint8_t>(lane));
                        output << "column=" << column
                               << " superlane=" << superlane
                               << " stream=" << stream
                               << " lane=" << lane
                               << " data=0x" << std::hex << std::setw(2)
                               << std::setfill('0')
                               << static_cast<unsigned>(cell.data)
                               << std::dec << std::setfill(' ')
                               << " valid=" << (cell.valid ? 1 : 0) << '\n';
                    }
                }
            }
        }
    }
    return output.str();
}

FullChipModel::FullChipModel()
    : west_hemisphere_(COLUMN_NUM, SUPERLANE_NUM, STREAM_NUM, LANE_NUM,
                       LOCAL_PRODUCERS, LOCAL_CONSUMERS),
      east_hemisphere_(COLUMN_NUM, SUPERLANE_NUM, STREAM_NUM, LANE_NUM,
                       LOCAL_PRODUCERS, LOCAL_CONSUMERS),
      cycle_(0) {
    reset();
}

void FullChipModel::reset() {
    west_hemisphere_.reset();
    east_hemisphere_.reset();
    cycle_ = 0;
}

void FullChipModel::step() {
    west_hemisphere_.step();
    east_hemisphere_.step();
    ++cycle_;
}

std::uint64_t FullChipModel::cycle() const { return cycle_; }

HemisphereModel& FullChipModel::model(Hemisphere hemisphere) {
    return hemisphere == Hemisphere::WEST ? west_hemisphere_ : east_hemisphere_;
}
const HemisphereModel& FullChipModel::model(Hemisphere hemisphere) const {
    return hemisphere == Hemisphere::WEST ? west_hemisphere_ : east_hemisphere_;
}

bool FullChipModel::inject_cell(Hemisphere hemisphere, Direction direction,
                                std::uint8_t producer, std::uint8_t column,
                                std::uint8_t superlane, std::uint8_t stream,
                                std::uint8_t lane, std::uint8_t data) {
    return model(hemisphere).inject_cell(direction, producer, column, superlane,
                                         stream, lane, data);
}
bool FullChipModel::consume_cell(Hemisphere hemisphere, Direction direction,
                                 std::uint8_t consumer, std::uint8_t column,
                                 std::uint8_t superlane, std::uint8_t stream,
                                 std::uint8_t lane) {
    return model(hemisphere).consume_cell(direction, consumer, column,
                                          superlane, stream, lane);
}
bool FullChipModel::write_cell(Hemisphere hemisphere, Direction direction,
                               std::uint8_t column, std::uint8_t superlane,
                               std::uint8_t stream, std::uint8_t lane,
                               std::uint8_t data) {
    return model(hemisphere).write_cell(direction, column, superlane, stream,
                                        lane, data);
}
CommandResult FullChipModel::read_cell(Hemisphere hemisphere,
                                       Direction direction,
                                       std::uint8_t column,
                                       std::uint8_t superlane,
                                       std::uint8_t stream,
                                       std::uint8_t lane) const {
    return model(hemisphere).read_cell(direction, column, superlane, stream,
                                       lane);
}
bool FullChipModel::collision_detected(Hemisphere hemisphere,
                                       Direction direction) const {
    return model(hemisphere).collision_detected(direction);
}
bool FullChipModel::invalid_consume_detected(Hemisphere hemisphere,
                                             Direction direction) const {
    return model(hemisphere).invalid_consume_detected(direction);
}

std::vector<CellSnapshot> FullChipModel::snapshot(
    Hemisphere hemisphere, Direction direction) const {
    return model(hemisphere).snapshot(direction);
}

std::uint64_t FullChipModel::expected_arrival_cycle(
    std::uint64_t source_visible_cycle,
    std::size_t source_column,
    std::size_t destination_column) {
    return SRFModel::expected_arrival_cycle(
        source_visible_cycle, source_column, destination_column,
        P_SR_HOP_CYCLES);
}

std::string FullChipModel::dump_state() const {
    std::ostringstream output;
    output << "cycle=" << cycle_ << '\n';
    const Hemisphere hemispheres[2] = {Hemisphere::WEST, Hemisphere::EAST};
    const char* hemisphere_names[2] = {"WEST", "EAST"};
    const Direction directions[2] = {Direction::EAST, Direction::WEST};
    const char* direction_names[2] = {"EAST", "WEST"};

    for (std::size_t hemisphere_index = 0; hemisphere_index < 2;
         ++hemisphere_index) {
        output << "hemisphere=" << hemisphere_names[hemisphere_index] << '\n';
        for (std::size_t direction_index = 0; direction_index < 2;
             ++direction_index) {
            output << "direction=" << direction_names[direction_index] << '\n';
            for (std::size_t column = 0; column < COLUMN_NUM; ++column) {
                for (std::size_t superlane = 0;
                     superlane < SUPERLANE_NUM; ++superlane) {
                    for (std::size_t stream = 0; stream < STREAM_NUM; ++stream) {
                        for (std::size_t lane = 0; lane < LANE_NUM; ++lane) {
                            const CommandResult cell = read_cell(
                                hemispheres[hemisphere_index],
                                directions[direction_index],
                                static_cast<std::uint8_t>(column),
                                static_cast<std::uint8_t>(superlane),
                                static_cast<std::uint8_t>(stream),
                                static_cast<std::uint8_t>(lane));
                            output << "column=" << column
                                   << " superlane=" << superlane
                                   << " stream=" << stream
                                   << " lane=" << lane
                                   << " data=0x" << std::hex << std::setw(2)
                                   << std::setfill('0')
                                   << static_cast<unsigned>(cell.data)
                                   << std::dec << std::setfill(' ')
                                   << " valid=" << (cell.valid ? 1 : 0) << '\n';
                        }
                    }
                }
            }
        }
    }
    return output.str();
}
