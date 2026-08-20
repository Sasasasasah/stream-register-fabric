#ifndef SRF_MODEL_H
#define SRF_MODEL_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

enum class Direction {
    EAST,
    WEST
};

enum class Hemisphere {
    WEST,
    EAST
};

struct Command {
    // OPTIONAL COMPATIBILITY command representation retained for legacy tests.
    std::uint8_t opcode;
    std::uint8_t column;
    std::uint8_t superlane;
    std::uint8_t stream;
    std::uint8_t lane;
    std::uint8_t data;

    static Command decode(std::uint64_t raw_command);
};

struct CommandResult {
    bool success;
    bool valid;
    std::uint8_t data;
};

struct CellSnapshot {
    std::uint64_t cycle;
    std::size_t column;
    std::size_t superlane;
    std::size_t stream;
    std::size_t lane;
    bool valid;
    std::uint8_t data;
};

class SRFModel {
public:
    // Legacy mini-profile constants retained for v7/v8 regression code.
    static constexpr std::size_t COLUMN_NUM = 4;
    static constexpr std::size_t SUPERLANE_NUM = 2;
    static constexpr std::size_t STREAM_NUM = 4;
    static constexpr std::size_t LANE_NUM = 4;
    static constexpr std::size_t LOCAL_PRODUCERS = 2;
    static constexpr std::size_t LOCAL_CONSUMERS = 2;
    static constexpr std::size_t P_SR_HOP_CYCLES = 1;

    static constexpr std::uint8_t OPCODE_WRITE = 0x01;
    static constexpr std::uint8_t OPCODE_READ = 0x02;

    explicit SRFModel(std::size_t column_num = COLUMN_NUM,
                      std::size_t superlane_num = SUPERLANE_NUM,
                      std::size_t stream_num = STREAM_NUM,
                      std::size_t lane_num = LANE_NUM,
                      std::size_t local_producers = LOCAL_PRODUCERS,
                      std::size_t local_consumers = LOCAL_CONSUMERS);

    void reset();
    void step();
    void set_direction(Direction direction);
    std::string dump_state() const;
    std::vector<CellSnapshot> snapshot() const;
    static std::uint64_t expected_arrival_cycle(
        std::uint64_t source_visible_cycle,
        std::size_t source_column,
        std::size_t destination_column,
        std::size_t hop_cycles = P_SR_HOP_CYCLES);
    std::uint64_t cycle() const;

    std::size_t column_num() const;
    std::size_t superlane_num() const;
    std::size_t stream_num() const;
    std::size_t lane_num() const;

    // OPTIONAL COMPATIBILITY command/direct-write APIs. Core cycle behavior does
    // not call these methods and remains usable through inject/consume/step.
    CommandResult execute(Command command);

    bool inject_cell(std::uint8_t producer,
                     std::uint8_t column,
                     std::uint8_t superlane,
                     std::uint8_t stream,
                     std::uint8_t lane,
                     std::uint8_t data);

    bool consume_cell(std::uint8_t consumer,
                      std::uint8_t column,
                      std::uint8_t superlane,
                      std::uint8_t stream,
                      std::uint8_t lane);

    bool write_cell(std::uint8_t column,
                    std::uint8_t superlane,
                    std::uint8_t stream,
                    std::uint8_t lane,
                    std::uint8_t data);

    CommandResult read_cell(std::uint8_t column,
                            std::uint8_t superlane,
                            std::uint8_t stream,
                            std::uint8_t lane) const;

    bool collision_detected() const;
    bool invalid_consume_detected() const;

private:
    bool address_valid(std::uint8_t column,
                       std::uint8_t superlane,
                       std::uint8_t stream,
                       std::uint8_t lane) const;
    std::size_t cell_index(std::size_t column,
                           std::size_t superlane,
                           std::size_t stream,
                           std::size_t lane) const;
    void begin_pending_cycle();
    void clear_pending_events();
    bool consume_any(std::size_t cell) const;

    std::size_t column_num_;
    std::size_t superlane_num_;
    std::size_t stream_num_;
    std::size_t lane_num_;
    std::size_t local_producers_;
    std::size_t local_consumers_;
    std::size_t cell_count_;

    std::vector<std::uint8_t> pipeline_data_;
    std::vector<bool> pipeline_valid_;
    std::vector<bool> inject_pending_;
    std::vector<std::uint8_t> inject_data_;
    std::vector<bool> consume_pending_;
    std::vector<bool> access_pending_;
    std::vector<std::uint8_t> access_data_;

    Direction direction_;
    std::uint64_t cycle_;
    bool pending_cycle_started_;
    bool collision_;
    bool invalid_consume_;
};

class HemisphereModel {
public:
    explicit HemisphereModel(
        std::size_t column_num = SRFModel::COLUMN_NUM,
        std::size_t superlane_num = SRFModel::SUPERLANE_NUM,
        std::size_t stream_num = SRFModel::STREAM_NUM,
        std::size_t lane_num = SRFModel::LANE_NUM,
        std::size_t local_producers = SRFModel::LOCAL_PRODUCERS,
        std::size_t local_consumers = SRFModel::LOCAL_CONSUMERS);

    void reset();
    void step();
    std::uint64_t cycle() const;

    bool inject_cell(Direction direction,
                     std::uint8_t producer,
                     std::uint8_t column,
                     std::uint8_t superlane,
                     std::uint8_t stream,
                     std::uint8_t lane,
                     std::uint8_t data);
    bool consume_cell(Direction direction,
                      std::uint8_t consumer,
                      std::uint8_t column,
                      std::uint8_t superlane,
                      std::uint8_t stream,
                      std::uint8_t lane);
    // OPTIONAL COMPATIBILITY helper retained outside the core propagation path.
    bool write_cell(Direction direction,
                    std::uint8_t column,
                    std::uint8_t superlane,
                    std::uint8_t stream,
                    std::uint8_t lane,
                    std::uint8_t data);
    CommandResult read_cell(Direction direction,
                            std::uint8_t column,
                            std::uint8_t superlane,
                            std::uint8_t stream,
                            std::uint8_t lane) const;

    bool collision_detected(Direction direction) const;
    bool invalid_consume_detected(Direction direction) const;
    bool hemisphere_collision_detected() const;
    bool hemisphere_invalid_consume_detected() const;
    std::string dump_state() const;
    std::vector<CellSnapshot> snapshot(Direction direction) const;

    std::size_t column_num() const;
    std::size_t superlane_num() const;
    std::size_t stream_num() const;
    std::size_t lane_num() const;

private:
    SRFModel& model(Direction direction);
    const SRFModel& model(Direction direction) const;

    SRFModel east_;
    SRFModel west_;
    std::uint64_t cycle_;
};

class FullChipModel {
public:
    static constexpr std::size_t HEMISPHERE_NUM = 2;
    static constexpr std::size_t DIRECTION_NUM = 2;
    static constexpr std::size_t COLUMN_NUM = 16;
    static constexpr std::size_t SUPERLANE_NUM = 4;
    static constexpr std::size_t STREAM_NUM = 32;
    static constexpr std::size_t LANE_NUM = 8;
    static constexpr std::size_t DATA_BITS = 8;
    static constexpr std::size_t LOCAL_PRODUCERS = 2;
    static constexpr std::size_t LOCAL_CONSUMERS = 2;
    static constexpr std::size_t P_SR_HOP_CYCLES =
        SRFModel::P_SR_HOP_CYCLES;

    FullChipModel();

    void reset();
    void step();
    std::uint64_t cycle() const;

    bool inject_cell(Hemisphere hemisphere,
                     Direction direction,
                     std::uint8_t producer,
                     std::uint8_t column,
                     std::uint8_t superlane,
                     std::uint8_t stream,
                     std::uint8_t lane,
                     std::uint8_t data);
    bool consume_cell(Hemisphere hemisphere,
                      Direction direction,
                      std::uint8_t consumer,
                      std::uint8_t column,
                      std::uint8_t superlane,
                      std::uint8_t stream,
                      std::uint8_t lane);
    // OPTIONAL COMPATIBILITY helper retained for compatibility regression.
    bool write_cell(Hemisphere hemisphere,
                    Direction direction,
                    std::uint8_t column,
                    std::uint8_t superlane,
                    std::uint8_t stream,
                    std::uint8_t lane,
                    std::uint8_t data);
    CommandResult read_cell(Hemisphere hemisphere,
                            Direction direction,
                            std::uint8_t column,
                            std::uint8_t superlane,
                            std::uint8_t stream,
                            std::uint8_t lane) const;

    bool collision_detected(Hemisphere hemisphere,
                            Direction direction) const;
    bool invalid_consume_detected(Hemisphere hemisphere,
                                  Direction direction) const;
    std::string dump_state() const;
    std::vector<CellSnapshot> snapshot(Hemisphere hemisphere,
                                       Direction direction) const;
    static std::uint64_t expected_arrival_cycle(
        std::uint64_t source_visible_cycle,
        std::size_t source_column,
        std::size_t destination_column);

private:
    HemisphereModel& model(Hemisphere hemisphere);
    const HemisphereModel& model(Hemisphere hemisphere) const;

    HemisphereModel west_hemisphere_;
    HemisphereModel east_hemisphere_;
    std::uint64_t cycle_;
};

#endif
