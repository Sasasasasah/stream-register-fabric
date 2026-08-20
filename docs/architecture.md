# Stream Register Fabric Architecture

## Overview

The project models a statically scheduled register transport network. Data and valid state advance through a fixed topology on clock boundaries. There is no per-cell ready signal, replay mechanism, dynamic backpressure, or runtime route allocation.

## Hierarchy

```text
sr_fabric
`-- sr_hemisphere_fabric
    `-- sr_direction_fabric
        `-- sr_column
            `-- sr_leaf
```

### Leaf

`sr_leaf` is the only state owner. Each `[stream][lane]` cell stores a payload and a valid bit. The leaf evaluates upstream propagation, local Inject candidates, and Consume requests.

### Column

`sr_column` raises the superlane dimension and instantiates one leaf for each superlane. It contains only packed-vector slicing and structural connections. One column contributes one cycle because its path crosses one registered leaf.

### Direction Fabric

`sr_direction_fabric` connects a configurable number of columns. `DIRECTION=0` elaborates an Eastward chain from column 0 to column N-1; `DIRECTION=1` elaborates the reverse Westward chain. Direction is fixed at elaboration time.

### Hemisphere and Fabric

`sr_hemisphere_fabric` contains independent Eastward and Westward paths. `sr_fabric` raises the hierarchy once more to provide two independent path groups. Upper wrappers do not add payload/valid state or extra Pipeline stages.

## Timing

For state already visible in a source column:

```text
arrival_cycle(destination) = visible_cycle(source)
                           + abs(destination - source)
                           * hop_cycles
```

The default `hop_cycles` value is one. An external boundary candidate first enters the boundary leaf on a clock edge, so a chain of N registered columns has N-cycle boundary-to-boundary latency.

## Cell Semantics

- Normal propagation copies the upstream data/valid candidate into leaf state.
- Inject supplies a local producer candidate.
- Consume masks current valid state from downstream propagation.
- Multiple simultaneous producers assert collision status.
- Consuming an invalid cell asserts invalid-consume status.

When multiple local producers collide, the implementation chooses the lowest producer index for deterministic simulation. A selected local Inject candidate has priority over upstream propagation; collision status remains asserted so clients cannot treat the winning payload as conflict-free data.
