# Stream Register Fabric

A parameterized Verilog implementation of a distributed stream-register
datapath, accompanied by a cycle-aware C++ reference model and self-checking
verification environment. The project explores deterministic data movement in
a fixed-latency register fabric rather than a ready/valid queue.

## Features

- Parameterized RTL hierarchy: fabric, hemisphere, direction fabric, column,
  and leaf
- Fixed-latency East/West directional propagation
- Per-cell `data` and `valid` state held exclusively in `sr_leaf`
- Local inject and consume semantics with collision reporting
- Bubble preservation through synchronized `data` and `valid` propagation
- Cycle-aware C++ model with `step()` and RTL/CModel trace comparison
- Self-checking RTL testbenches, static checks, and Windows batch regressions

## Architecture

```text
sr_fabric
`-- sr_hemisphere_fabric
    `-- sr_direction_fabric
        `-- sr_column
            `-- sr_leaf
```

`sr_leaf` is the sole state holder for stream cells. `sr_column` is a
state-free structural wrapper around leaf instances. Direction fabrics connect
columns into registered paths, and hemisphere/fabric wrappers compose the
top-level hierarchy. See [Architecture Notes](docs/architecture.md) for the
implemented hierarchy and timing model.

## Project Structure

```text
rtl/        Synthesizable Verilog RTL modules
cmodel/     Cycle-aware C++ reference model
tb/         Self-checking RTL testbenches
scripts/    Build, regression, trace-comparison, and static-check scripts
docs/       Architecture and verification notes
```

## Verification

The regression covers reset behavior, leaf and column semantics, directional
propagation, hemisphere and full-fabric behavior, saturated traffic, hop
timing, and RTL/CModel trace comparison. Successful RTL testbenches print
`TEST_PASS`; a matching trace comparison prints `TRACE_MATCH`.

For verification details, see [Verification Notes](docs/verification.md).

## Quick Start

From the repository root on Windows, with Icarus Verilog, Python, and a C++17
toolchain available:

```bat
scripts\run_compile.bat
scripts\run_regression.bat
```

The main regression generates temporary outputs under `sim/`; these files are
ignored by Git. To run the trace comparison separately:

```bat
python scripts\compare_rtl_cmodel.py
```

## Design Notes

The fabric has fixed spatial paths and fixed cycle latency. `valid` travels
with its associated data, so an invalid cell represents a bubble at a defined
pipeline position. Local inject, consume, and propagation events are resolved
at the leaf according to the implementation's deterministic state-update
policy.
