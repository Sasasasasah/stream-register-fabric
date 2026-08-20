`timescale 1ns/1ps

// One superlane Stream Register leaf. This is the only SRF module that owns
// payload state. A cell is selected by [stream][lane] and contains
// P_SR_DATA_BITS
// of data plus one valid bit.
module sr_leaf #(
    parameter P_STREAMS_PER_DIR       = 32,
    parameter P_LANES_PER_SUPERLANE   = 8,
    parameter P_SR_DATA_BITS          = 8,
    parameter P_LOCAL_PRODUCERS       = 2,
    parameter P_LOCAL_CONSUMERS       = 2
) (
    input  wire                                      clk_i,
    input  wire                                      rst_ni,

    // Upstream propagation candidate, packed [stream][lane][data bit].
    input  wire [P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] upstream_data_i,
    input  wire [P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                upstream_valid_i,

    // Downstream view. Consume masks valid for the selected current cells.
    output wire [P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] downstream_data_o,
    output wire [P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                downstream_valid_o,

    // Raw current-state observation for local consumers. Unlike
    // downstream_valid_o, state_valid_o is not masked by consume_i.
    output wire [P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] state_data_o,
    output wire [P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]                state_valid_o,

    // Cell mapping:
    //   control bit = owner*CELL_NUM + stream*P_LANES_PER_SUPERLANE + lane
    //   data slice  = control bit*P_SR_DATA_BITS +: P_SR_DATA_BITS
    input  wire [P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] inject_valid_i,
    input  wire [P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0] inject_data_i,
    input  wire [P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0] consume_i,

    // Aggregated leaf status: high when any cell has the named condition.
    output wire                                      collision_o,
    output wire                                      invalid_consume_o
);

    localparam CELL_NUM   = P_STREAMS_PER_DIR * P_LANES_PER_SUPERLANE;
    localparam DATA_WIDTH = CELL_NUM * P_SR_DATA_BITS;

    reg [DATA_WIDTH-1:0] data_state;
    reg [CELL_NUM-1:0]   valid_state;
    reg [DATA_WIDTH-1:0] next_data;
    reg [CELL_NUM-1:0]   next_valid;
    reg [CELL_NUM-1:0]   consume_any;
    reg                  collision_comb;
    reg                  invalid_consume_comb;

    integer cell_index;
    integer producer_index;
    integer consumer_index;
    integer candidate_count;
    reg     inject_selected;

    // Next-state candidates are resolved independently for every cell.
    // Deterministic project policy when collision_o is asserted:
    //   lowest-index local inject > upstream propagation.
    // The winner policy is deterministic; collision_o remains asserted so a
    // multiple-producer condition is never silently hidden.
    always @(*) begin
        next_data               = upstream_data_i;
        next_valid              = upstream_valid_i;
        consume_any             = {CELL_NUM{1'b0}};
        collision_comb          = 1'b0;
        invalid_consume_comb    = 1'b0;
        candidate_count         = 0;
        inject_selected         = 1'b0;

        for (cell_index = 0; cell_index < CELL_NUM; cell_index = cell_index + 1) begin
            candidate_count = upstream_valid_i[cell_index] ? 1 : 0;
            inject_selected = 1'b0;

            for (consumer_index = 0;
                 consumer_index < P_LOCAL_CONSUMERS;
                 consumer_index = consumer_index + 1) begin
                if (consume_i[consumer_index*CELL_NUM + cell_index]) begin
                    consume_any[cell_index] = 1'b1;
                    if (!valid_state[cell_index])
                        invalid_consume_comb = 1'b1;
                end
            end

            for (producer_index = 0;
                 producer_index < P_LOCAL_PRODUCERS;
                 producer_index = producer_index + 1) begin
                if (inject_valid_i[producer_index*CELL_NUM + cell_index]) begin
                    candidate_count = candidate_count + 1;
                    if (!inject_selected) begin
                        next_data[cell_index*P_SR_DATA_BITS +: P_SR_DATA_BITS] =
                            inject_data_i[(producer_index*CELL_NUM + cell_index)*P_SR_DATA_BITS +: P_SR_DATA_BITS];
                        next_valid[cell_index] = 1'b1;
                        inject_selected = 1'b1;
                    end
                end
            end

            if (candidate_count >= 2)
                collision_comb = 1'b1;
        end
    end

    // Leaf state advances exactly one cycle. Reset is asynchronously asserted;
    // its release must be synchronized by the top-level reset source. Only the
    // valid bits require reset because payload is meaningless while valid is 0.
    // Consume affects the current downstream view, not next-state selection.
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_state <= {CELL_NUM{1'b0}};
        end else begin
            data_state  <= next_data;
            valid_state <= next_valid;
        end
    end

    assign state_data_o      = data_state;
    assign state_valid_o     = valid_state;
    assign downstream_data_o = data_state;
    assign downstream_valid_o = valid_state & ~consume_any;
    assign collision_o       = collision_comb;
    assign invalid_consume_o = invalid_consume_comb;

endmodule
